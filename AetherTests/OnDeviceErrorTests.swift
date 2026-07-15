import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// OnDeviceError 单元测试
/// errorDescription 使用 NSLocalizedString，测试仅断言非空，
/// 对携带关联值的 case 额外验证关联值出现在描述中（关联值非本地化文案）。
final class OnDeviceErrorTests: XCTestCase {

    // MARK: - errorDescription 非空

    /// insufficientMemory 的 errorDescription 应非空
    func testInsufficientMemoryErrorDescriptionNonEmpty() {
        let error = OnDeviceError.insufficientMemory
        XCTAssertNotNil(error.errorDescription, "insufficientMemory 的 errorDescription 应非 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                       "insufficientMemory 的 errorDescription 应非空字符串")
    }

    /// modelNotFound 的 errorDescription 应非空，且包含 URL 的 lastPathComponent
    func testModelNotFoundErrorDescriptionContainsFileName() {
        let url = URL(fileURLWithPath: "/tmp/models/qwen-0.5b.gguf")
        let error = OnDeviceError.modelNotFound(url)
        XCTAssertNotNil(error.errorDescription, "modelNotFound 的 errorDescription 应非 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                       "modelNotFound 的 errorDescription 应非空字符串")
        // 关联值（文件名）应出现在描述中
        XCTAssertTrue(error.errorDescription?.contains("qwen-0.5b.gguf") ?? false,
                      "modelNotFound 描述应包含文件名 qwen-0.5b.gguf")
    }

    /// sha256Mismatch 的 errorDescription 应非空，且包含期望值与实际值的前 8 字符
    func testSha256MismatchErrorDescriptionContainsHashes() {
        let expected = "abcdef1234567890abcdef1234567890"
        let actual = "0987654321fedcba0987654321fedcba"
        let error = OnDeviceError.sha256Mismatch(expected: expected, actual: actual)
        XCTAssertNotNil(error.errorDescription, "sha256Mismatch 的 errorDescription 应非 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                       "sha256Mismatch 的 errorDescription 应非空字符串")
        // 前 8 字符的期望值与实际值应出现在描述中
        XCTAssertTrue(error.errorDescription?.contains(String(expected.prefix(8))) ?? false,
                      "sha256Mismatch 描述应包含期望值前 8 字符 abcdef12")
        XCTAssertTrue(error.errorDescription?.contains(String(actual.prefix(8))) ?? false,
                      "sha256Mismatch 描述应包含实际值前 8 字符 09876543")
    }

    /// unsupportedQuantization 的 errorDescription 应非空
    func testUnsupportedQuantizationErrorDescriptionNonEmpty() {
        let error = OnDeviceError.unsupportedQuantization
        XCTAssertNotNil(error.errorDescription, "unsupportedQuantization 的 errorDescription 应非 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                       "unsupportedQuantization 的 errorDescription 应非空字符串")
    }

    /// loadFailed 的 errorDescription 应非空，且包含传入的错误信息
    func testLoadFailedErrorDescriptionContainsMessage() {
        let message = "ggml backend init failed"
        let error = OnDeviceError.loadFailed(message)
        XCTAssertNotNil(error.errorDescription, "loadFailed 的 errorDescription 应非 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                       "loadFailed 的 errorDescription 应非空字符串")
        // 关联值（底层错误信息）应出现在描述中
        XCTAssertTrue(error.errorDescription?.contains(message) ?? false,
                      "loadFailed 描述应包含底层错误信息")
    }

    /// downloadTimeout 的 errorDescription 应非空
    func testDownloadTimeoutErrorDescriptionNonEmpty() {
        let error = OnDeviceError.downloadTimeout
        XCTAssertNotNil(error.errorDescription, "downloadTimeout 的 errorDescription 应非 nil")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                       "downloadTimeout 的 errorDescription 应非空字符串")
    }

    // MARK: - LocalizedError 契约

    /// LocalizedError 协议：errorDescription 对所有 case 均应返回非 nil 值
    func testAllCasesReturnNonNilErrorDescription() {
        let url = URL(fileURLWithPath: "/tmp/model.gguf")
        let cases: [OnDeviceError] = [
            .insufficientMemory,
            .modelNotFound(url),
            .sha256Mismatch(expected: "aaa", actual: "bbb"),
            .unsupportedQuantization,
            .loadFailed("err"),
            .downloadTimeout
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription,
                           "所有 case 的 errorDescription 均应非 nil")
        }
    }

    /// 不同 case 的 errorDescription 应可区分（至少不全相等）
    func testErrorDescriptionsAreDistinguishable() {
        let url = URL(fileURLWithPath: "/tmp/model.gguf")
        let descriptions: [String] = [
            OnDeviceError.insufficientMemory.errorDescription ?? "",
            OnDeviceError.modelNotFound(url).errorDescription ?? "",
            OnDeviceError.unsupportedQuantization.errorDescription ?? "",
            OnDeviceError.downloadTimeout.errorDescription ?? ""
        ]
        // 转为 Set 去重，应至少有 2 个不同值
        let unique = Set(descriptions)
        XCTAssertGreaterThanOrEqual(unique.count, 2,
                                   "不同 case 的 errorDescription 应可区分")
    }
}
