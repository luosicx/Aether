import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Task 6: 遥测日志脱敏单元测试。
/// 验证 `TelemetrySanitizer.redact` 对常见敏感模式的脱敏效果，
/// 并确保原始敏感字符串不会出现在输出中。
final class TelemetrySanitizerTests: XCTestCase {

    // MARK: - 单一模式脱敏

    func testRedactsFilePath() {
        let input = "无法读取 /Users/alice/.ssh/id_rsa"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_PATH]"))
        XCTAssertFalse(output.contains("/Users/alice/.ssh/id_rsa"))
    }

    func testRedactsVarPath() {
        let input = "Log at /var/mobile/Containers/Data/Application/xxx/Documents/app.log"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_PATH]"))
        XCTAssertFalse(output.contains("/var/mobile"))
    }

    func testRedactsURL() {
        let input = "请求失败: https://api.example.com/v1/chat?token=abc123"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_URL]"))
        XCTAssertFalse(output.contains("https://api.example.com"))
        XCTAssertFalse(output.contains("token=abc123"))
    }

    func testRedactsHTTPURL() {
        let input = "请访问 http://internal.corp.local:8080/admin"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_URL]"))
        XCTAssertFalse(output.contains("http://internal.corp.local"))
    }

    func testRedactsUUID() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let input = "会话 ID: \(uuid)"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_UUID]"))
        XCTAssertFalse(output.contains(uuid))
    }

    func testRedactsEmail() {
        let email = "alice.smith+dev@example.co.uk"
        let input = "请联系 \(email) 获取支持"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_EMAIL]"))
        XCTAssertFalse(output.contains(email))
    }

    func testRedactsSKToken() {
        let token = "sk-abcdefghijklmnopqrstuvwxyz123456"
        let input = "API key: \(token)"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_TOKEN]"))
        XCTAssertFalse(output.contains(token))
    }

    func testRedactsBearerToken() {
        let token = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test"
        let input = "Authorization: \(token)"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_TOKEN]"))
        XCTAssertFalse(output.contains("eyJhbGciOiJIUzI1Ni"))
    }

    func testRedactsPasswordField() {
        let input = "表单提交失败: password=MyS3cret!&username=alice"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_CREDENTIAL]"))
        XCTAssertFalse(output.contains("MyS3cret!"))
        XCTAssertTrue(output.contains("username=alice"))
    }

    func testRedactsTokenField() {
        let input = "query: token=abc-def_123&user=1"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_CREDENTIAL]"))
        XCTAssertFalse(output.contains("abc-def_123"))
    }

    func testRedactsApiKeyField() {
        let input = "header x-api-key=secretvalue"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_CREDENTIAL]"))
        XCTAssertFalse(output.contains("secretvalue"))
    }

    // MARK: - 复合场景

    func testRedactsMultipleSensitivePatterns() {
        let input = """
        用户 alice@example.com (id: 550e8400-e29b-41d4-a716-446655440000) \
        在 /Users/alice/.ssh 使用 sk-live-123456 访问 https://api.example.com \
        失败，password=hello
        """
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_EMAIL]"))
        XCTAssertTrue(output.contains("[REDACTED_UUID]"))
        XCTAssertTrue(output.contains("[REDACTED_PATH]"))
        XCTAssertTrue(output.contains("[REDACTED_TOKEN]"))
        XCTAssertTrue(output.contains("[REDACTED_URL]"))
        XCTAssertTrue(output.contains("[REDACTED_CREDENTIAL]"))
        XCTAssertFalse(output.contains("alice@example.com"))
        XCTAssertFalse(output.contains("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertFalse(output.contains("/Users/alice/.ssh"))
        XCTAssertFalse(output.contains("sk-live-123456"))
        XCTAssertFalse(output.contains("https://api.example.com"))
        XCTAssertFalse(output.contains("password=hello"))
    }

    // MARK: - 不误伤普通信息

    func testDoesNotAlterPlainErrorMessage() {
        let input = "Network timeout after 30 seconds"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertEqual(output, input)
    }

    func testDoesNotAlterGenericWords() {
        let input = "The password field is required but user did not provide one"
        let output = TelemetrySanitizer.redact(input)
        // 没有 "password=..." 或 "password: ..." 形式，不应脱敏
        XCTAssertEqual(output, input)
    }

    func testDoesNotAlterNumbersAndPunctuation() {
        let input = "Error code: 404, retry count: 3"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertEqual(output, input)
    }

    // MARK: - 边界情况

    func testEmptyStringReturnsEmpty() {
        XCTAssertEqual(TelemetrySanitizer.redact(""), "")
    }

    func testPathInURLNotLeaked() {
        // URL 应被整体替换，输出中不应残留 URL 的 path
        let input = "Failed to open https://example.com/Users/alice/secret.txt"
        let output = TelemetrySanitizer.redact(input)
        XCTAssertTrue(output.contains("[REDACTED_URL]"))
        XCTAssertFalse(output.contains("/Users/alice/secret.txt"))
        XCTAssertFalse(output.contains("https://example.com"))
    }

    func testSKTokenStyleInQueryRedacted() {
        let input = "https://api.example.com/v1?api_key=sk-test-123456"
        let output = TelemetrySanitizer.redact(input)
        // URL 整体先被替换，因此输出只有 [REDACTED_URL]
        XCTAssertEqual(output, "[REDACTED_URL]")
    }
}
