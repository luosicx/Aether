import Foundation
import CryptoKit
import Security

/// P1-12 (H-S1): BFF endpoint SSL Pinning（证书固定）实现。
///
/// 通过 URLSessionDelegate 拦截 `didReceive challenge` 回调，校验服务器证书链中
/// 叶子证书的 SPKI (Subject Public Key Info) SHA256 hash 是否匹配预置 pin。
/// 防止 MITM 攻击场景：
/// - 攻击者伪造 CA 签发证书（需先通过系统证书链校验）
/// - 企业代理拦截 HTTPS 流量
/// - 用户设备被安装恶意根证书
/// - 上游 CA 被攻破
///
/// 校验流程（两步）：
/// 1. **系统证书链校验**：`SecTrustEvaluateWithError` 验证证书链有效（防止无效证书）
/// 2. **SPKI hash 校验**：从证书 DER 中提取 SubjectPublicKeyInfo，计算 SHA256 后与预置 pin 比较
///
/// 任何一步失败都取消连接（`cancelAuthenticationChallenge`）。
/// 预置 pin 为空时不启用 Pinning，仅依赖系统证书链（向后兼容）；
/// 一旦配置了 pin 但全部无效（非 Base64 / 长度不是 32 字节），则拒绝所有连接（fail-closed）。
///
/// `@unchecked Sendable`：URLSessionDelegate 要求 NSObject 继承，无法纯 Sendable；
/// 但实例本身为不可变（pinnedHashes 在 init 后只读），可安全跨 actor 传递。
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    /// 预置的 SPKI SHA256 hash 列表（Base64 编码，已规范化）
    /// 支持多个 hash 以便证书轮换（主备 pin）
    private(set) var pinnedHashes: Set<String>
    /// 是否配置了 pin。配置过 pin 时必须成功匹配，避免「配了但解析失败 → 跳过校验」
    private(set) var pinningConfigured: Bool

    /// 创建 Pinning Delegate
    /// - Parameter pinnedHashes: 预置的 SPKI SHA256 hash 列表（Base64 编码，也接受 `sha256/` 前缀）
    init(pinnedHashes: [String]) {
        self.pinnedHashes = Set(pinnedHashes.compactMap(Self.normalizePin))
        self.pinningConfigured = !pinnedHashes.isEmpty
    }

    /// URLSession 委托：处理 SSL 证书挑战
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // 仅处理 HTTPS 服务器信任挑战；其他类型使用默认处理
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 步骤 1：系统证书链校验（防止无效证书）
        var trustError: CFError?
        let systemValidationPassed = SecTrustEvaluateWithError(serverTrust, &trustError)
        guard systemValidationPassed else {
            // 系统证书链校验失败：取消连接（防止自签名/过期证书）
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 步骤 2：未配置 pin 时不启用 Pinning，信任系统证书链（向后兼容）
        guard pinningConfigured else {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }

        // 配置了 pin 但没有任何有效 hash：拒绝连接，避免配置错误导致 Pinning 被静默跳过
        guard !pinnedHashes.isEmpty else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 步骤 3：提取叶子证书并计算标准 SPKI hash
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCert = certificateChain.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 提取叶子证书公钥并计算 SHA256 hash
        guard let spkiHash = CertificatePinningDelegate.computeSPKIHash(of: leafCert) else {
            // 无法提取公钥或计算 hash：取消连接
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // 步骤 4：与预置 pin 比对
        if pinnedHashes.contains(spkiHash) {
            // 匹配：信任证书
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // 不匹配：取消连接（疑似 MITM）
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - SPKI Hash 计算

    /// 将配置中的 pin 规范化为标准 Base64（兼容 `sha256/` 前缀与首尾空白）
    /// - Parameter raw: 原始 pin 字符串
    /// - Returns: 规范化后的 Base64；非 Base64 或长度不是 32 字节时返回 nil
    static func normalizePin(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("sha256/") {
            value = String(value.dropFirst("sha256/".count))
        }
        guard let data = Data(base64Encoded: value), data.count == 32 else {
            return nil
        }
        return data.base64EncodedString()
    }

    /// 计算证书的标准 SPKI (Subject Public Key Info) SHA256 hash（Base64 编码）
    /// - Parameter certificate: SecCertificate 证书
    /// - Returns: Base64 编码的 SHA256 hash，失败返回 nil
    ///
    /// 实现说明：
    /// - 直接解析证书 DER，取出 `tbsCertificate.subjectPublicKeyInfo` 的完整 TLV
    /// - 对 SPKI 的 DER 编码做 SHA256（与 OkHttp / TrustKit / openssl 的 pin 一致）
    /// - 不能对 `SecKeyCopyExternalRepresentation` 的结果直接 hash：RSA 返回 PKCS#1
    ///   RSAPublicKey、EC 返回 X9.62 点，均缺少 AlgorithmIdentifier，得到的 pin 与业界不兼容
    static func computeSPKIHash(of certificate: SecCertificate) -> String? {
        let certificateDER = SecCertificateCopyData(certificate) as Data
        guard let spki = extractSPKI(fromCertificateDER: certificateDER) else {
            return nil
        }
        let hash = SHA256.hash(data: spki)
        return Data(hash).base64EncodedString()
    }

    /// 从 X.509 证书 DER 中提取 subjectPublicKeyInfo 的完整 DER TLV
    /// - Parameter der: 证书 DER
    /// - Returns: SPKI TLV；结构不合法时返回 nil
    ///
    /// Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
    /// tbsCertificate ::= SEQUENCE {
    ///   [0] version OPTIONAL, serialNumber, signature, issuer, validity, subject, subjectPublicKeyInfo, ...
    /// }
    static func extractSPKI(fromCertificateDER der: Data) -> Data? {
        let bytes = [UInt8](der)
        guard let certificate = readTLV(bytes, at: 0), certificate.tag == 0x30,
              let tbs = readTLV(bytes, at: certificate.contentStart), tbs.tag == 0x30 else {
            return nil
        }

        var fields: [TLV] = []
        var offset = tbs.contentStart
        while offset < tbs.end {
            guard let field = readTLV(bytes, at: offset) else { return nil }
            fields.append(field)
            offset = field.end
        }

        // 有 version 时字段整体后移一位：serial/signature/issuer/validity/subject/SPKI
        let spkiIndex = fields.first?.tag == 0xA0 ? 6 : 5
        guard fields.count > spkiIndex, fields[spkiIndex].tag == 0x30 else {
            return nil
        }
        let spki = fields[spkiIndex]
        return Data(bytes[spki.start..<spki.end])
    }

    /// DER TLV 描述（仅支持 definite length，X.509 不使用 indefinite length）
    private struct TLV {
        let tag: UInt8
        /// TLV 起始偏移（含 tag）
        let start: Int
        /// 内容起始偏移
        let contentStart: Int
        /// TLV 结束偏移（不含）
        let end: Int
    }

    /// 读取一个 DER TLV
    private static func readTLV(_ bytes: [UInt8], at offset: Int) -> TLV? {
        guard offset < bytes.count else { return nil }
        let tag = bytes[offset]
        var index = offset + 1
        guard index < bytes.count else { return nil }

        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let byteCount = length & 0x7F
            guard byteCount > 0, byteCount <= 4, index + byteCount <= bytes.count else {
                return nil
            }
            length = 0
            for _ in 0..<byteCount {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard length >= 0, index + length <= bytes.count else { return nil }
        return TLV(tag: tag, start: offset, contentStart: index, end: index + length)
    }
}
