import XCTest
import AetherRust

/// Rust 脱敏包装器单元测试。
/// 验证 AetherRustRedactor.redact 的脱敏行为。
final class RedactorRustTests: XCTestCase {

    // MARK: - UUID 脱敏

    func testRedactUUID() {
        let input = "User 550e8400-e29b-41d4-a716-446655440000 logged in"
        let result = AetherRustRedactor.redact(input)
        XCTAssertFalse(result.contains("550e8400"), "UUID 应被脱敏")
        XCTAssertTrue(result.contains("User"), "普通文本应保留")
        XCTAssertTrue(result.contains("logged in"), "普通文本应保留")
    }

    // MARK: - 邮箱脱敏

    func testRedactEmail() {
        let input = "Contact user@example.com for help"
        let result = AetherRustRedactor.redact(input)
        XCTAssertFalse(result.contains("user@example.com"), "邮箱应被脱敏")
        XCTAssertTrue(result.contains("Contact"), "普通文本应保留")
    }

    // MARK: - URL 脱敏

    func testRedactURL() {
        let input = "Visit https://example.com/path?token=secret for more"
        let result = AetherRustRedactor.redact(input)
        XCTAssertFalse(result.contains("example.com"), "URL 应被脱敏")
    }

    // MARK: - Token 脱敏

    func testRedactBearerToken() {
        let input = "Authorization: Bearer sk-1234567890abcdef"
        let result = AetherRustRedactor.redact(input)
        XCTAssertFalse(result.contains("sk-1234567890abcdef"), "Bearer token 应被脱敏")
    }

    // MARK: - 密码字段脱敏

    func testRedactPassword() {
        let input = #"{"password": "mySecret123"}"#
        let result = AetherRustRedactor.redact(input)
        XCTAssertFalse(result.contains("mySecret123"), "密码字段应被脱敏")
    }

    // MARK: - 普通文本保留

    func testNormalTextPreserved() {
        let input = "Network timeout occurred while connecting to server"
        let result = AetherRustRedactor.redact(input)
        XCTAssertEqual(result, input, "普通错误信息不应被修改")
    }

    func testEmptyString() {
        let result = AetherRustRedactor.redact("")
        XCTAssertEqual(result, "", "空字符串应返回空字符串")
    }

    // MARK: - 中文文本

    func testChineseTextPreserved() {
        let input = "用户登录失败，请重试"
        let result = AetherRustRedactor.redact(input)
        XCTAssertEqual(result, input, "中文普通文本不应被修改")
    }

    // MARK: - 混合内容

    func testMixedSensitiveAndNormal() {
        let input = "Error: API key abc123 expired. Please renew at https://api.example.com"
        let result = AetherRustRedactor.redact(input)
        XCTAssertTrue(result.contains("Error"), "普通文本应保留")
        XCTAssertTrue(result.contains("expired"), "普通文本应保留")
        // 敏感信息应被脱敏
        XCTAssertFalse(result.contains("api.example.com"), "URL 应被脱敏")
    }
}