import XCTest
import Security
@testable import AetherServices

/// P1-6: SSL Pinning SPKI 标准兼容性与 fail-closed 行为测试。
///
/// 期望 hash 由 openssl 独立计算：
///   openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
/// 若实现错误地 hash 公钥原始 DER（EC 点 / PKCS#1），这些断言会失败。
final class CertificatePinningDelegateTests: XCTestCase {
    // Apple Root CA - G3（EC P-384）
    private let ecCertificateDER = """
    MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==
    """
    private let ecExpectedSPKIHash = "myGdD7/zal+zIJBXGQa87qaGF8gzo/YbgeliqOZNuK8="

    // DigiCert Global Root CA（RSA 2048）
    private let rsaCertificateDER = """
    MIIDrzCCApegAwIBAgIQCDvgVpBCRrGhdWrJWZHHSjANBgkqhkiG9w0BAQUFADBhMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSAwHgYDVQQDExdEaWdpQ2VydCBHbG9iYWwgUm9vdCBDQTAeFw0wNjExMTAwMDAwMDBaFw0zMTExMTAwMDAwMDBaMGExCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xIDAeBgNVBAMTF0RpZ2lDZXJ0IEdsb2JhbCBSb290IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4jvhEXLeqKTTo1eqUKKPC3eQyaKl7hLOllsBCSDMAZOnTjC3U/dDxGkAV53ijSLdhwZAAIEJzs4bg7/fzTtxRuLWZscFs3YnFo97nh6Vfe63SKMI2tavegw5BmV/Sl0fvBf4q77uKNd0f3p4mVmFaG5cIzJLv07A6Fpt43C/dxC//AH2hdmoRBBYMql1GNXRor5H4idq9Joz+EkIYIvUX7Q6hL+hqkpMfT7PT19sdl6gSzeRntwi5m3OFBqOasv+zbMUZBfHWymeMr/y7vrTC0LUq7dBMtoM1O/4gdW7jVg/tRvoSSiicNoxBN33shbyTApOB6jtSj1etX+jkMOvJwIDAQABo2MwYTAOBgNVHQ8BAf8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUA95QNVbRTLtm8KPiGxvDl7I90VUwHwYDVR0jBBgwFoAUA95QNVbRTLtm8KPiGxvDl7I90VUwDQYJKoZIhvcNAQEFBQADggEBAMucN6pIExIK+t1EnE9SsPTfrgT1eXkIoyQY/EsrhMAtudXH/vTBH1jLuG2cenTnmCmrEbXjcKChzUyImZOMkXDiqw8cvpOp/2PV5Adg06O/nVsJ8dWO41P0jmP6P6fbtGbfYmbW0W5BjfIttep3Sp+dWOIrWcBAI+0tKIJFPnlUkiaY4IBIqDfv8NZ5YBberOgOzW6sRBc4L0na4UU+Krk2U886UAb3LujEV0lsYSEY1QSteDwsOoBrp+uvFRTp2InBuThs4pFsiv9kuXclVzDAGySj4dzp30d8tbQkCAUw7C29C79Fv1C5qfPrmAESrciIxpg0X40KPMbp1ZWVbd4=
    """
    private let rsaExpectedSPKIHash = "r/mIkG3eEpVdm+u/ko/cwxzOMo1bk4TyHIlByibiA5E="

    /// 从 Base64 DER 构造 SecCertificate
    private func certificate(fromBase64 base64: String) throws -> SecCertificate {
        let cleaned = base64.components(separatedBy: .whitespacesAndNewlines).joined()
        let data = try XCTUnwrap(Data(base64Encoded: cleaned))
        return try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
    }

    // MARK: - SPKI hash

    func testSPKIHashMatchesOpenSSLForECCertificate() throws {
        let cert = try certificate(fromBase64: ecCertificateDER)
        XCTAssertEqual(
            CertificatePinningDelegate.computeSPKIHash(of: cert),
            ecExpectedSPKIHash
        )
    }

    func testSPKIHashMatchesOpenSSLForRSACertificate() throws {
        let cert = try certificate(fromBase64: rsaCertificateDER)
        XCTAssertEqual(
            CertificatePinningDelegate.computeSPKIHash(of: cert),
            rsaExpectedSPKIHash
        )
    }

    func testExtractSPKIProducesDERSequence() throws {
        let cert = try certificate(fromBase64: ecCertificateDER)
        let der = SecCertificateCopyData(cert) as Data
        let spki = try XCTUnwrap(CertificatePinningDelegate.extractSPKI(fromCertificateDER: der))
        XCTAssertEqual(spki.first, 0x30, "SPKI 应为 DER SEQUENCE")
        XCTAssertGreaterThan(spki.count, 32)
    }

    func testExtractSPKIReturnsNilForMalformedDER() {
        XCTAssertNil(CertificatePinningDelegate.extractSPKI(fromCertificateDER: Data()))
        XCTAssertNil(CertificatePinningDelegate.extractSPKI(fromCertificateDER: Data([0x30, 0x03, 0x01])))
        XCTAssertNil(
            CertificatePinningDelegate.extractSPKI(fromCertificateDER: Data(repeating: 0xFF, count: 64))
        )
    }

    // MARK: - Pin 规范化

    func testNormalizePinAcceptsPlainBase64() {
        XCTAssertEqual(
            CertificatePinningDelegate.normalizePin(ecExpectedSPKIHash),
            ecExpectedSPKIHash
        )
    }

    func testNormalizePinStripsSHA256PrefixAndWhitespace() {
        XCTAssertEqual(
            CertificatePinningDelegate.normalizePin("  sha256/\(ecExpectedSPKIHash)\n"),
            ecExpectedSPKIHash
        )
        XCTAssertEqual(
            CertificatePinningDelegate.normalizePin("SHA256/\(ecExpectedSPKIHash)"),
            ecExpectedSPKIHash
        )
    }

    func testNormalizePinRejectsInvalidValues() {
        XCTAssertNil(CertificatePinningDelegate.normalizePin(""))
        XCTAssertNil(CertificatePinningDelegate.normalizePin("not-base64!!"))
        // 合法 Base64 但长度不是 32 字节
        XCTAssertNil(CertificatePinningDelegate.normalizePin(Data("short".utf8).base64EncodedString()))
    }

    // MARK: - fail-closed

    func testEmptyPinListDoesNotEnablePinning() {
        let delegate = CertificatePinningDelegate(pinnedHashes: [])
        XCTAssertFalse(delegate.pinningConfigured)
        XCTAssertTrue(delegate.pinnedHashes.isEmpty)
    }

    func testAllInvalidPinsKeepPinningConfiguredButNoUsableHash() {
        let delegate = CertificatePinningDelegate(pinnedHashes: ["bad-pin", "sha256/also-bad"])
        XCTAssertTrue(delegate.pinningConfigured, "配置过 pin 就必须启用校验")
        XCTAssertTrue(delegate.pinnedHashes.isEmpty, "无效 pin 不应产生可匹配 hash")
    }

    func testMixOfValidAndInvalidPinsKeepsValidPin() {
        let delegate = CertificatePinningDelegate(
            pinnedHashes: ["bad-pin", "sha256/\(ecExpectedSPKIHash)"]
        )
        XCTAssertTrue(delegate.pinningConfigured)
        XCTAssertEqual(delegate.pinnedHashes, [ecExpectedSPKIHash])
    }
}
