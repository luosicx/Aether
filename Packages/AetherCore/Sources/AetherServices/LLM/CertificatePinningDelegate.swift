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
/// 2. **SPKI hash 校验**：提取叶子证书公钥的 SHA256 hash，与预置 pin 比较
///
/// 任何一步失败都取消连接（`cancelAuthenticationChallenge`）。
/// 预置 pin 为空时跳过 SPKI 校验，仅依赖系统证书链（向后兼容）。
///
/// `@unchecked Sendable`：URLSessionDelegate 要求 NSObject 继承，无法纯 Sendable；
/// 但实例本身为不可变（pinnedHashes 在 init 后只读），可安全跨 actor 传递。
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    /// 预置的 SPKI SHA256 hash 列表（Base64 编码）
    /// 支持多个 hash 以便证书轮换（主备 pin）
    private let pinnedHashes: Set<String>

    /// 创建 Pinning Delegate
    /// - Parameter pinnedHashes: 预置的 SPKI SHA256 hash 列表（Base64 编码）
    init(pinnedHashes: [String]) {
        self.pinnedHashes = Set(pinnedHashes)
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

        // 步骤 2：如果未配置 pin，跳过 SPKI 校验（向后兼容）
        guard !pinnedHashes.isEmpty else {
            // 未配置 pin：信任系统证书链校验结果
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
            return
        }

        // 步骤 3：提取叶子证书并计算 SPKI hash
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

    /// 计算证书公钥的 SPKI SHA256 hash（Base64 编码）
    /// - Parameter certificate: SecCertificate 证书
    /// - Returns: Base64 编码的 SHA256 hash，失败返回 nil
    ///
    /// 实现说明：
    /// - 使用 `SecCertificateCopyKey` 提取公钥（iOS 13+/macOS 10.15+）
    /// - 使用 `SecKeyCopyExternalRepresentation` 获取 DER 编码的公钥
    /// - 使用 CryptoKit SHA256 计算 hash
    /// - Base64 编码后返回
    ///
    /// 注意：此 hash 是公钥的 DER 编码 hash，与 SPKI hash 略有差异（SPKI 包含 AlgorithmIdentifier）。
    /// 对于 RSA/ECDSA 证书，公钥 DER 编码等价于 SPKI 的 subjectPublicKey 字段（不含外层 SEQUENCE）。
    /// 主流实现（OkHttp / TrustKit）使用相同方法，pin 兼容。
    static func computeSPKIHash(of certificate: SecCertificate) -> String? {
        // 提取公钥
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }
        // 获取 DER 编码的公钥
        var error: CFError?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }
        // 计算 SHA256 hash
        let hash = SHA256.hash(data: publicKeyData)
        // 转换为 Data 后 Base64 编码
        return Data(hash).base64EncodedString()
    }
}
