import XCTest
import AetherRust

/// Rust SHA-256 包装器单元测试。
/// 验证 AetherRustSha256 的流式哈希、finalize 输出、文件哈希等。
final class Sha256RustTests: XCTestCase {

    // MARK: - 基本哈希

    func testHashEmptyData() {
        let hasher = AetherRustSha256()
        let result = hasher.finalize()
        // 空数据 SHA-256 固定值
        XCTAssertEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    func testHashHelloWorld() {
        let hasher = AetherRustSha256()
        hasher.update("Hello, World!".data(using: .utf8)!)
        let result = hasher.finalize()
        XCTAssertEqual(result, "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f")
    }

    // MARK: - 流式哈希

    func testStreamingHash() {
        let hasher = AetherRustSha256()
        hasher.update("Hello".data(using: .utf8)!)
        hasher.update(", ".data(using: .utf8)!)
        hasher.update("World!".data(using: .utf8)!)
        let result = hasher.finalize()
        // 应与一次性哈希结果一致
        XCTAssertEqual(result, "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f")
    }

    func testUpdateEmptyDataDoesNotCrash() {
        let hasher = AetherRustSha256()
        hasher.update(Data())
        let result = hasher.finalize()
        XCTAssertEqual(result, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - finalize 后可继续 update

    func testFinalizeDoesNotConsumeState() {
        let hasher = AetherRustSha256()
        hasher.update("ABC".data(using: .utf8)!)
        let first = hasher.finalize()
        XCTAssertFalse(first.isEmpty)
        // 继续追加数据
        hasher.update("DEF".data(using: .utf8)!)
        let second = hasher.finalize()
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second, "追加数据后哈希应不同")
    }

    // MARK: - 确定性

    func testHashIsDeterministic() {
        let data = "Deterministic test".data(using: .utf8)!
        let h1 = AetherRustSha256()
        h1.update(data)
        let r1 = h1.finalize()

        let h2 = AetherRustSha256()
        h2.update(data)
        let r2 = h2.finalize()

        XCTAssertEqual(r1, r2, "相同输入应产生相同哈希")
    }

    // MARK: - 输出格式

    func testHashOutputIs64HexChars() {
        let hasher = AetherRustSha256()
        hasher.update("test".data(using: .utf8)!)
        let result = hasher.finalize()
        XCTAssertEqual(result.count, 64, "SHA-256 输出应为 64 个十六进制字符")
        XCTAssertTrue(result.allSatisfy { $0.isHexDigit }, "输出应全部为十六进制字符")
    }

    // MARK: - 中文支持

    func testHashChineseText() {
        let hasher = AetherRustSha256()
        hasher.update("你好世界".data(using: .utf8)!)
        let result = hasher.finalize()
        XCTAssertEqual(result.count, 64)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - 大文件分块哈希 (aetherSha256)

    func testAetherSha256Helper() {
        // 创建临时文件
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("sha256_test_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        try? "Hello, Aether!".data(using: .utf8)?.write(to: tmpFile)

        let result = aetherSha256(of: tmpFile)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.count, 64)
    }

    func testAetherSha256NonExistentFile() {
        let nonExistent = URL(fileURLWithPath: "/tmp/nonexistent_sha256_test_\(UUID().uuidString).txt")
        let result = aetherSha256(of: nonExistent)
        XCTAssertEqual(result, "", "不存在的文件应返回空字符串")
    }
}