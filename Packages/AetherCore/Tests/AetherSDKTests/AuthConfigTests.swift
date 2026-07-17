import XCTest
@testable import AetherSDK

/// Task 24 阶段 4: AuthConfig 四种鉴权方案测试
final class AuthConfigTests: XCTestCase {

    // MARK: - API Key 方案

    func testAPIKeyScheme() {
        let auth: AuthConfig = .apiKey
        XCTAssertEqual(auth.schemeName, "api_key")
        // apiKey 方案不直接注入 header（由 AetherClient 在请求层填充 Bearer）
        XCTAssertTrue(auth.headers.isEmpty)
    }

    func testAPIKeyDefault() {
        XCTAssertEqual(AuthConfig.default, .apiKey)
    }

    // MARK: - OAuth 2.0

    func testOAuthScheme() {
        let cred = OAuthCredential(
            accessToken: "access-123",
            refreshToken: "refresh-456",
            expiresAt: Date(timeIntervalSinceNow: 3600),
            tokenType: "Bearer"
        )
        let auth = AuthConfig.oauth(cred)
        XCTAssertEqual(auth.schemeName, "oauth2")
        XCTAssertEqual(auth.headers["Authorization"], "Bearer access-123")
    }

    func testOAuthCredentialExpiration() {
        // 已过期
        let expiredCred = OAuthCredential(
            accessToken: "x",
            expiresAt: Date(timeIntervalSinceNow: -100)
        )
        XCTAssertTrue(expiredCred.isExpired)

        // 未过期
        let validCred = OAuthCredential(
            accessToken: "x",
            expiresAt: Date(timeIntervalSinceNow: 100)
        )
        XCTAssertFalse(validCred.isExpired)

        // 无 expiresAt：视为未过期
        let noExpiryCred = OAuthCredential(accessToken: "x")
        XCTAssertFalse(noExpiryCred.isExpired)
    }

    func testOAuthCredentialDefaults() {
        let cred = OAuthCredential(accessToken: "tok")
        XCTAssertEqual(cred.tokenType, "Bearer")
        XCTAssertNil(cred.refreshToken)
        XCTAssertNil(cred.expiresAt)
    }

    // MARK: - JWT

    func testJWTScheme() {
        let cred = JWTCredential(
            token: "header.payload.signature",
            issuer: "aether",
            audience: "bff",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        let auth = AuthConfig.jwt(cred)
        XCTAssertEqual(auth.schemeName, "jwt")
        XCTAssertEqual(auth.headers["Authorization"], "Bearer header.payload.signature")
    }

    func testJWTCredentialExpiration() {
        let expired = JWTCredential(token: "x.y.z", expiresAt: Date(timeIntervalSinceNow: -100))
        XCTAssertTrue(expired.isExpired)

        let valid = JWTCredential(token: "x.y.z", expiresAt: Date(timeIntervalSinceNow: 100))
        XCTAssertFalse(valid.isExpired)

        let noExpiry = JWTCredential(token: "x.y.z")
        XCTAssertFalse(noExpiry.isExpired)
    }

    func testJWTDecodePayload() {
        // 构造一个真实 JWT payload（base64url 编码的 JSON）
        // {"sub":"1234567890","name":"John Doe","iat":1516239022}
        let payload = "{\"sub\":\"1234567890\",\"name\":\"John Doe\",\"iat\":1516239022}"
        let payloadData = payload.data(using: .utf8)!
        var base64 = payloadData.base64EncodedString()
        // 转 base64url
        base64 = base64.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        // 去掉 padding
        while base64.hasSuffix("=") {
            base64.removeLast()
        }
        let token = "header.\(base64).signature"

        let cred = JWTCredential(token: token)
        let decoded = cred.decodePayload()
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?["sub"] as? String, "1234567890")
        XCTAssertEqual(decoded?["name"] as? String, "John Doe")
        XCTAssertEqual(decoded?["iat"] as? Int, 1516239022)
    }

    func testJWTDecodeInvalidPayloadReturnsNil() {
        let cred = JWTCredential(token: "not.a.valid.jwt")
        XCTAssertNil(cred.decodePayload())

        let cred2 = JWTCredential(token: "onlyonepart")
        XCTAssertNil(cred2.decodePayload())
    }

    // MARK: - Device Bound

    func testDeviceBoundScheme() {
        let auth = AuthConfig.deviceBound(deviceID: "device-abc", apiKey: "sk-test")
        XCTAssertEqual(auth.schemeName, "device_bound")
        XCTAssertEqual(auth.headers["X-API-Key"], "sk-test")
        XCTAssertEqual(auth.headers["X-Device-ID"], "device-abc")
    }

    // MARK: - Equatable

    func testAuthConfigEquality() {
        XCTAssertEqual(AuthConfig.apiKey, AuthConfig.apiKey)
        XCTAssertEqual(AuthConfig.default, .apiKey)

        let oauth1 = AuthConfig.oauth(OAuthCredential(accessToken: "a"))
        let oauth2 = AuthConfig.oauth(OAuthCredential(accessToken: "a"))
        let oauth3 = AuthConfig.oauth(OAuthCredential(accessToken: "b"))
        XCTAssertEqual(oauth1, oauth2)
        XCTAssertNotEqual(oauth1, oauth3)

        let jwt1 = AuthConfig.jwt(JWTCredential(token: "t"))
        let jwt2 = AuthConfig.jwt(JWTCredential(token: "t"))
        XCTAssertEqual(jwt1, jwt2)

        let db1 = AuthConfig.deviceBound(deviceID: "d", apiKey: "k")
        let db2 = AuthConfig.deviceBound(deviceID: "d", apiKey: "k")
        XCTAssertEqual(db1, db2)

        XCTAssertNotEqual(AuthConfig.apiKey, oauth1)
    }

    // MARK: - Sendable

    func testAuthConfigIsSendable() {
        let auth: AuthConfig = .apiKey
        let closure: @Sendable () -> String = { auth.schemeName }
        XCTAssertEqual(closure(), "api_key")
    }
}
