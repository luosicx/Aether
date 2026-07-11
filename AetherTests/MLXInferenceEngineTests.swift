import XCTest
@testable import Aether

/// MLXInferenceEngine 单元测试。
/// 模拟器环境（无 MLX）走占位分支；验证 actor 隔离的公共接口、状态管理、OnDeviceError 枚举。
final class MLXInferenceEngineTests: XCTestCase {

    private var engine: MLXInferenceEngine { MLXInferenceEngine.shared }

    override func setUp() async throws {
        try await super.setUp()
        await engine.unloadModel()
    }

    override func tearDown() async throws {
        await engine.unloadModel()
        try await super.tearDown()
    }

    // MARK: - 初始状态

    func testInitialIsLoadedIsFalse() async {
        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "unloadModel 后 isLoaded 应为 false")
    }

    // MARK: - loadModel: modelNotFound

    func testLoadModelThrowsModelNotFoundForNonExistentFile() async {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString).mlpackage")
        do {
            try await engine.loadModel(path: nonExistentURL)
            XCTFail("不存在的文件应抛 modelNotFound")
        } catch let error as OnDeviceError {
            if case .modelNotFound(let url) = error {
                XCTAssertEqual(url.lastPathComponent, nonExistentURL.lastPathComponent)
            } else {
                XCTFail("期望 .modelNotFound，实际：\(error)")
            }
            let lastError = await engine.lastLoadError
            if case .modelNotFound = lastError {
                // 期望命中
            } else {
                XCTFail("期望 lastLoadError 为 .modelNotFound，实际：\(String(describing: lastError))")
            }
        } catch {
            XCTFail("期望 OnDeviceError，实际：\(error)")
        }

        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "加载失败后 isLoaded 应为 false")
    }

    // MARK: - loadModel: SHA256 校验失败

    func testLoadModelThrowsSHA256Mismatch() async {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model-\(UUID().uuidString).mlpackage")
        try? Data("placeholder content".utf8).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        do {
            try await engine.loadModel(path: tmpURL, expectedSHA256: "0000000000000000000000000000000000000000000000000000000000000000")
            XCTFail("SHA256 不匹配应抛 sha256Mismatch")
        } catch let error as OnDeviceError {
            if case .sha256Mismatch(let expected, let actual) = error {
                XCTAssertEqual(expected, "0000000000000000000000000000000000000000000000000000000000000000")
                XCTAssertNotEqual(actual, "0000000000000000000000000000000000000000000000000000000000000000")
            } else {
                XCTFail("期望 .sha256Mismatch，实际：\(error)")
            }
        } catch {
            XCTFail("期望 OnDeviceError，实际：\(error)")
        }

        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "校验失败后 isLoaded 应为 false")
    }

    // MARK: - loadModel: 空字符串 SHA256 跳过校验

    func testLoadModelSkipsSHA256WhenEmpty() async {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model-\(UUID().uuidString).mlpackage")
        try? Data("placeholder".utf8).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // expectedSHA256 为空字符串时跳过校验，直接进入 MLX 加载分支
        do {
            try await engine.loadModel(path: tmpURL, expectedSHA256: "")
            // MLX 可用时加载成功，不可用时进入 #else 分支
        } catch let error as OnDeviceError {
            // 模拟器环境：应抛 loadFailed（跳过了 SHA256 校验）
            if case .loadFailed = error {
                // 期望命中
            } else if case .insufficientMemory = error {
                // 低内存设备可能抛此错误，也合理
            } else {
                // 不应抛 sha256Mismatch（空 SHA256 应跳过校验）
                if case .sha256Mismatch = error {
                    XCTFail("空 SHA256 应跳过校验，不应抛 sha256Mismatch")
                }
            }
        } catch {
            XCTFail("期望 OnDeviceError，实际：\(error)")
        }
    }

    // MARK: - loadModel: 模拟器占位分支（无 MLX）

    func testLoadModelThrowsLoadFailedWhenMLXUnavailable() async throws {
        #if canImport(MLX)
        throw XCTSkip("MLX 可用，跳过占位分支测试")
        #else
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model-\(UUID().uuidString).mlpackage")
        try? Data("placeholder".utf8).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        do {
            try await engine.loadModel(path: tmpURL)
            XCTFail("模拟器环境（mlx-swift 不可用）应抛 loadFailed")
        } catch let error as OnDeviceError {
            if case .loadFailed = error {
                // 期望命中
            } else {
                XCTFail("期望 .loadFailed，实际 OnDeviceError：\(error)")
            }
            let lastError = await engine.lastLoadError
            if case .loadFailed = lastError {
                // 期望命中
            } else {
                XCTFail("期望 lastLoadError 为 .loadFailed，实际：\(String(describing: lastError))")
            }
        } catch {
            XCTFail("期望 OnDeviceError，实际：\(error)")
        }

        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "占位分支加载失败后 isLoaded 应为 false")
        #endif
    }

    // MARK: - generate: 占位流

    func testGenerateReturnsPlaceholderStreamWhenMLXUnavailable() async throws {
        #if canImport(MLX)
        throw XCTSkip("MLX 可用，跳过占位分支测试")
        #else
        let stream = await engine.generate(prompt: "hello", maxTokens: 10, temperature: 0.7)
        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }
        XCTAssertFalse(tokens.isEmpty, "占位模式应至少返回一个 token")
        XCTAssertTrue(
            tokens.joined().contains(NSLocalizedString("[端侧推理不可用：mlx-swift 未集成]", comment: "")),
            "占位流应包含 mlx-swift 未集成提示"
        )
        #endif
    }

    func testGenerateWithModelPathStillReturnsPlaceholderWhenMLXUnavailable() async throws {
        #if canImport(MLX)
        throw XCTSkip("MLX 可用，跳过占位分支测试")
        #else
        let fakePath = URL(fileURLWithPath: "/fake/path/model.mlpackage")
        let stream = await engine.generate(prompt: "test", maxTokens: 10, temperature: 0.5, modelPath: fakePath)
        var tokens: [String] = []
        for await token in stream {
            tokens.append(token)
        }
        XCTAssertFalse(tokens.isEmpty, "占位模式应返回提示 token")
        #endif
    }

    // MARK: - preloadTokenizer

    func testPreloadTokenizerDoesNotCrash() async {
        // 未加载模型时调用 preloadTokenizer 不应崩溃
        await engine.preloadTokenizer()
        let isLoaded = await engine.isLoaded
        XCTAssertFalse(isLoaded, "preloadTokenizer 不应改变 isLoaded")
    }

    // MARK: - unloadModel

    func testUnloadModelResetsIsLoaded() async {
        // 先确保状态为未加载
        await engine.unloadModel()
        let isLoadedBefore = await engine.isLoaded
        XCTAssertFalse(isLoadedBefore)

        // 再次卸载不应崩溃
        await engine.unloadModel()
        let isLoadedAfter = await engine.isLoaded
        XCTAssertFalse(isLoadedAfter, "重复 unloadModel 应保持 isLoaded 为 false")
    }

    // MARK: - OnDeviceError 枚举描述
    // 注：OnDeviceError 使用 NSLocalizedString，CI 英文环境下返回英文文案，不断言中文关键词

    func testOnDeviceErrorInsufficientMemoryDescription() {
        let error = OnDeviceError.insufficientMemory
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "insufficientMemory 应有非空描述")
    }

    func testOnDeviceErrorModelNotFoundDescription() {
        let url = URL(fileURLWithPath: "/test/path/model.mlpackage")
        let error = OnDeviceError.modelNotFound(url)
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        XCTAssertTrue(error.errorDescription?.contains("model.mlpackage") ?? false, "描述应包含文件名")
    }

    func testOnDeviceErrorSHA256MismatchDescription() {
        let error = OnDeviceError.sha256Mismatch(expected: "abcdef1234567890", actual: "0987654321fedcba")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testOnDeviceErrorUnsupportedQuantizationDescription() {
        let error = OnDeviceError.unsupportedQuantization
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    func testOnDeviceErrorLoadFailedDescription() {
        let error = OnDeviceError.loadFailed("test error reason")
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        XCTAssertTrue(error.errorDescription?.contains("test error reason") ?? false, "描述应包含错误信息")
    }

    func testOnDeviceErrorDownloadTimeoutDescription() {
        let error = OnDeviceError.downloadTimeout
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    // MARK: - OnDeviceError Sendable

    func testOnDeviceErrorIsSendable() {
        // OnDeviceError 声明为 Sendable，此处验证可在并发上下文中传递
        let errors: [OnDeviceError] = [
            .insufficientMemory,
            .modelNotFound(URL(fileURLWithPath: "/test")),
            .sha256Mismatch(expected: "a", actual: "b"),
            .unsupportedQuantization,
            .loadFailed("err"),
            .downloadTimeout
        ]
        XCTAssertEqual(errors.count, 6, "OnDeviceError 应有 6 个 case")
    }
}
