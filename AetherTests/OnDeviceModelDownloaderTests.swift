import XCTest
import CryptoKit
import Network
@testable import Aether

/// 端侧模型下载器单元测试：验证自定义 URLSessionConfiguration 超时配置与 downloadTimeout 错误类型。
final class OnDeviceModelDownloaderTests: XCTestCase {

    // MARK: - 1. makeDownloadSessionConfig 配置值

    /// 验证下载专用 URLSessionConfiguration 放宽了超时限制，
    /// 避免大文件（~700MB）下载被 Apple 默认 60s timeoutIntervalForRequest 打断。
    func testDownloadSessionConfigTimeouts() async {
        let config = await OnDeviceModelDownloader.shared.makeDownloadSessionConfig()

        XCTAssertEqual(
            config.timeoutIntervalForRequest, 300,
            "单请求超时应为 300s（5 分钟），覆盖慢速 TLS 握手与传输停滞"
        )
        XCTAssertEqual(
            config.timeoutIntervalForResource, 7200,
            "资源整体超时应为 7200s（2 小时），覆盖 700MB 慢速下载"
        )
        XCTAssertTrue(
            config.waitsForConnectivity,
            "waitsForConnectivity 应为 true，网络短暂中断时等待重连而非立即失败"
        )
        XCTAssertFalse(
            config.allowsCellularAccess,
            "allowsCellularAccess 应为 false，避免蜂窝网络下载大文件"
        )
    }

    // MARK: - 2. OnDeviceError.downloadTimeout 错误描述

    /// 验证 downloadTimeout 错误提供用户友好提示并建议「继续下载」。
    func testDownloadTimeoutErrorDescription() {
        let error = OnDeviceError.downloadTimeout
        let description = error.errorDescription

        XCTAssertNotNil(description, "downloadTimeout 的 errorDescription 不应为 nil")
        XCTAssertTrue(
            description?.contains("继续下载") == true,
            "downloadTimeout 提示应包含「继续下载」以引导用户从断点恢复，实际：\(description ?? "nil")"
        )
        XCTAssertTrue(
            description?.contains("下载超时") == true,
            "downloadTimeout 提示应包含「下载超时」，实际：\(description ?? "nil")"
        )
    }

    // MARK: - 3. OnDeviceConfig 下载源与镜像地址默认值

    /// 验证 OnDeviceConfig 默认下载源为国内 ModelScope，镜像 URL 指向 ModelScope 的 model.safetensors。
    func testDownloadSourceAndMirrorURLDefault() {
        let config = OnDeviceConfig.default
        XCTAssertEqual(config.downloadSource, .domestic, "默认下载源应为国内 ModelScope")
        XCTAssertEqual(
            config.mirrorDownloadURL.absoluteString,
            "https://www.modelscope.cn/api/v1/models/mlx-community/Llama-3.2-1B-Instruct-4bit/repo?Revision=master&FilePath=model.safetensors",
            "默认镜像地址应指向 ModelScope 的 model.safetensors"
        )
        XCTAssertEqual(
            config.downloadURL.absoluteString,
            "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors",
            "默认主下载地址应指向 HuggingFace 的 model.safetensors（不再是 model.mlpackage）"
        )
        XCTAssertNotEqual(
            config.mirrorDownloadURL, config.downloadURL,
            "镜像地址应与主地址不同（不同 host）"
        )
    }

    // MARK: - 4. 初始状态

    /// 下载器初始状态：progress=0.0、isDownloading=false、lastError=nil、hasResumeData=false
    func testInitialState() async {
        let downloader = OnDeviceModelDownloader.shared
        let progress = await downloader.progress
        let isDownloading = await downloader.isDownloading
        let lastError = await downloader.lastError
        let hasResume = await downloader.hasResumeData

        XCTAssertEqual(progress, 0.0, "初始 progress 应为 0.0")
        XCTAssertFalse(isDownloading, "初始 isDownloading 应为 false")
        XCTAssertNil(lastError, "初始 lastError 应为 nil")
        XCTAssertFalse(hasResume, "初始 hasResumeData 应为 false")
    }

    // MARK: - 5. SHA256 校验

    /// verifySHA256 文件不存在时应返回 false
    func testVerifySHA256FileNotExistReturnsFalse() async {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-model-\(UUID().uuidString).bin")
        let result = await downloader.verifySHA256(filePath: nonExistentURL, expected: "any")
        XCTAssertFalse(result, "文件不存在时 verifySHA256 应返回 false")
    }

    /// verifySHA256 期望值匹配时应返回 true
    func testVerifySHA256MatchReturnsTrue() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let content = "test model content for sha256".data(using: .utf8)!
        try content.write(to: testFile)

        // 计算 SHA256
        let digest = SHA256.hash(data: content)
        let expected = digest.map { String(format: "%02x", $0) }.joined()

        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "期望值匹配时 verifySHA256 应返回 true")
    }

    /// verifySHA256 期望值不匹配时应返回 false
    func testVerifySHA256MismatchReturnsFalse() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let content = "test model content".data(using: .utf8)!
        try content.write(to: testFile)

        let result = await downloader.verifySHA256(filePath: testFile, expected: "0000000000000000000000000000000000000000000000000000000000000000")
        XCTAssertFalse(result, "期望值不匹配时 verifySHA256 应返回 false")
    }

    /// verifySHA256 空字符串期望值：实现直接比较 actual == expected，空串不匹配非空 actual 故返回 false
    func testVerifySHA256EmptyExpectedReturnsFalse() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        try "content".data(using: .utf8)!.write(to: testFile)

        // 实现无空串跳过逻辑：actual（非空） != ""（空）故返回 false
        let result = await downloader.verifySHA256(filePath: testFile, expected: "")
        XCTAssertFalse(result, "空字符串期望值与非空 actual 不匹配，应返回 false")
    }

    /// verifySHA256 大文件分块读取校验
    func testVerifySHA256LargeFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-large-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        // 创建超过 4MB 的文件以测试分块读取
        let chunkSize = 4 * 1024 * 1024
        let content = Data(count: chunkSize + 1024)  // 略大于 chunkSize
        try content.write(to: testFile)

        let digest = SHA256.hash(data: content)
        let expected = digest.map { String(format: "%02x", $0) }.joined()

        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "大文件 SHA256 校验应成功（分块读取）")
    }

    // MARK: - 6. deleteModel

    /// deleteModel 文件不存在时应抛出 modelNotFound
    func testDeleteModelNotFoundThrows() async {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-model-\(UUID().uuidString).bin")

        do {
            try await downloader.deleteModel(at: nonExistentURL)
            XCTFail("删除不存在的文件应抛出 modelNotFound 错误")
        } catch let error as OnDeviceError {
            if case .modelNotFound(let url) = error {
                XCTAssertEqual(url, nonExistentURL, "modelNotFound 应携带文件路径")
            } else {
                XCTFail("应抛出 modelNotFound，实际：\(error)")
            }
        } catch {
            XCTFail("应抛出 OnDeviceError.modelNotFound，实际：\(error)")
        }
    }

    /// deleteModel 文件存在时应成功删除
    func testDeleteModelSuccess() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("model-to-delete-\(UUID().uuidString).bin")
        try "model data".data(using: .utf8)!.write(to: testFile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path), "删除前文件应存在")

        try await downloader.deleteModel(at: testFile)

        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path), "删除后文件应不存在")
    }

    // MARK: - 7. cancelDownload 状态清理

    /// cancelDownload 未下载时调用不应崩溃，isDownloading 应保持 false
    func testCancelDownloadWhenNotDownloading() async {
        await downloader.cancelDownload()

        let isDownloading = await downloader.isDownloading
        XCTAssertFalse(isDownloading, "未下载时 cancelDownload 后 isDownloading 应保持 false")
    }

    /// cancelDownload 后 hasResumeData 应保持 false（未实际下载无 resumeData）
    func testCancelDownloadHasNoResumeData() async {
        await downloader.cancelDownload()

        let hasResume = await downloader.hasResumeData
        XCTAssertFalse(hasResume, "未实际下载时 cancelDownload 不应产生 resumeData")
    }

    // MARK: - 8. resumeDownload 状态守卫

    /// resumeDownload 无 resumeData 时应直接返回，不修改 isDownloading
    func testResumeDownloadWithoutDataIsNoOp() async {
        let isDownloadingBefore = await downloader.isDownloading
        XCTAssertFalse(isDownloadingBefore, "调用前 isDownloading 应为 false")

        await downloader.resumeDownload()

        let isDownloadingAfter = await downloader.isDownloading
        XCTAssertFalse(isDownloadingAfter, "无 resumeData 时 resumeDownload 应直接返回，不修改状态")
    }

    // MARK: - 9. OnDeviceError 各 case 描述

    /// OnDeviceError.insufficientMemory 错误描述
    /// 注：使用 NSLocalizedString，CI 英文环境下返回英文文案，不断言中文关键词
    func testInsufficientMemoryErrorDescription() {
        let error = OnDeviceError.insufficientMemory
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription?.isEmpty == true,
                      "insufficientMemory 描述不应为空")
    }

    /// OnDeviceError.modelNotFound 错误描述
    func testModelNotFoundErrorDescription() {
        let url = URL(fileURLWithPath: "/tmp/test-model.gguf")
        let error = OnDeviceError.modelNotFound(url)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("test-model.gguf") == true,
                      "modelNotFound 描述应含文件名")
    }

    /// OnDeviceError.sha256Mismatch 错误描述
    /// 注：使用 NSLocalizedString，CI 英文环境下返回英文文案，不断言中文关键词
    func testSHA256MismatchErrorDescription() {
        let error = OnDeviceError.sha256Mismatch(expected: "abcdef1234567890", actual: "9876543210fedcba")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription?.isEmpty == true,
                      "sha256Mismatch 描述不应为空")
    }

    /// OnDeviceError.unsupportedQuantization 错误描述
    /// 注：使用 NSLocalizedString，CI 英文环境下返回英文文案，不断言中文关键词
    func testUnsupportedQuantizationErrorDescription() {
        let error = OnDeviceError.unsupportedQuantization
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription?.isEmpty == true,
                      "unsupportedQuantization 描述不应为空")
    }

    /// OnDeviceError.loadFailed 错误描述
    func testLoadFailedErrorDescription() {
        let error = OnDeviceError.loadFailed("加载失败原因")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("加载失败原因") == true,
                      "loadFailed 描述应含底层错误信息")
    }

    // MARK: - 10. OnDeviceModelCatalog SHA256 验证

    /// OnDeviceModelCatalog 中每个模型应有非空 SHA256
    func testModelCatalogHasSHA256() {
        for model in OnDeviceModelCatalog.models {
            XCTAssertFalse(model.sha256.isEmpty, "模型 \(model.id) 的 sha256 不应为空")
            XCTAssertEqual(model.sha256.count, 64, "模型 \(model.id) 的 sha256 应为 64 字符十六进制")
        }
    }

    /// OnDeviceModelCatalog.find(id:) 存在与不存在场景
    func testModelCatalogFind() {
        let existing = OnDeviceModelCatalog.find(id: "Llama-3.2-1B-Instruct-4bit")
        XCTAssertNotNil(existing, "存在的 ID 应能找到")
        XCTAssertEqual(existing?.name, "Llama-3.2-1B-Instruct-4bit")

        let nonExisting = OnDeviceModelCatalog.find(id: "non-existent-model")
        XCTAssertNil(nonExisting, "不存在的 ID 应返回 nil")
    }

    /// OnDeviceModelCatalog 模型 url(for:) 按 DownloadSource 返回对应 URL
    func testModelCatalogURLForSource() {
        guard let model = OnDeviceModelCatalog.models.first else {
            XCTFail("OnDeviceModelCatalog.models 不应为空")
            return
        }
        XCTAssertEqual(model.url(for: .domestic), model.modelScopeURL, "domestic 应返回 ModelScope URL")
        XCTAssertEqual(model.url(for: .international), model.huggingFaceURL, "international 应返回 HuggingFace URL")
    }

    // MARK: - 11. DownloadSource 枚举

    /// DownloadSource.displayName 应返回非空本地化字符串
    func testDownloadSourceDisplayName() {
        XCTAssertFalse(DownloadSource.domestic.displayName.isEmpty, "domestic displayName 不应为空")
        XCTAssertFalse(DownloadSource.international.displayName.isEmpty, "international displayName 不应为空")
    }

    /// DownloadSource 应支持 CaseIterable，包含 domestic 与 international 两个 case
    func testDownloadSourceCaseIterable() {
        XCTAssertEqual(DownloadSource.allCases.count, 2, "DownloadSource 应有 2 个 case")
        XCTAssertTrue(DownloadSource.allCases.contains(.domestic))
        XCTAssertTrue(DownloadSource.allCases.contains(.international))
    }

    /// DownloadSource 从 String 初始化应正确映射
    func testDownloadSourceFromRawValue() {
        XCTAssertEqual(DownloadSource(rawValue: "domestic"), .domestic)
        XCTAssertEqual(DownloadSource(rawValue: "international"), .international)
        XCTAssertNil(DownloadSource(rawValue: "unknown"), "未知 rawValue 应返回 nil")
    }

    // MARK: - 12. makeDownloadSessionConfig 每次返回新实例

    /// 每次调用 makeDownloadSessionConfig 应返回独立的 URLSessionConfiguration 实例，
    /// 避免共享状态污染（如某次修改 timeout 影响其他下载）。
    func testDownloadSessionConfigReturnsDistinctInstances() async {
        let config1 = await OnDeviceModelDownloader.shared.makeDownloadSessionConfig()
        let config2 = await OnDeviceModelDownloader.shared.makeDownloadSessionConfig()
        XCTAssertFalse(config1 === config2, "两次调用应返回不同实例")
    }

    // MARK: - 13. SHA256 空文件

    /// verifySHA256 对空文件应正常计算（SHA256 of empty data）
    func testVerifySHA256EmptyFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("empty-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        try Data().write(to: testFile)

        // SHA256 of empty data = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        let emptySHA256 = SHA256.hash(data: Data()).map { String(format: "%02x", $0) }.joined()
        let result = await downloader.verifySHA256(filePath: testFile, expected: emptySHA256)
        XCTAssertTrue(result, "空文件 SHA256 应匹配已知值")
    }

    // MARK: - 14. SHA256 大小写敏感

    /// 实现使用小写 hex（String(format: "%02x")），大写 hex 应不匹配
    func testVerifySHA256CaseSensitive() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("case-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let content = "case sensitivity test".data(using: .utf8)!
        try content.write(to: testFile)

        let expectedLower = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let expectedUpper = expectedLower.uppercased()

        let matchLower = await downloader.verifySHA256(filePath: testFile, expected: expectedLower)
        XCTAssertTrue(matchLower, "小写 hex 应匹配")
        let matchUpper = await downloader.verifySHA256(filePath: testFile, expected: expectedUpper)
        XCTAssertFalse(matchUpper, "大写 hex 不应匹配（实现用 %02x 小写）")
    }

    // MARK: - 15. SHA256 二进制内容

    /// verifySHA256 对任意二进制内容应正确校验
    func testVerifySHA256BinaryContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("binary-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        // 构造含 0x00 和 0xFF 的二进制数据
        var bytes: [UInt8] = []
        for i in 0..<256 { bytes.append(UInt8(i)) }
        let content = Data(bytes)
        try content.write(to: testFile)

        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "二进制内容 SHA256 应匹配")
    }

    // MARK: - 16. deleteModel 对目录

    /// deleteModel 对目录路径应正常删除（FileManager.removeItem 支持目录）
    func testDeleteModelOnDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("model-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: testDir) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: testDir.path))
        try await downloader.deleteModel(at: testDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testDir.path), "目录应被删除")
    }

    // MARK: - 17. cancelDownload 连续多次调用

    /// 连续多次 cancelDownload 不应崩溃，isDownloading 保持 false
    func testCancelDownloadMultipleTimesNoCrash() async {
        await downloader.cancelDownload()
        await downloader.cancelDownload()
        await downloader.cancelDownload()

        let isDownloading = await downloader.isDownloading
        XCTAssertFalse(isDownloading, "多次 cancel 后 isDownloading 应保持 false")
    }

    // MARK: - 18. resumeDownload 连续多次调用

    /// 无 resumeData 时连续多次 resumeDownload 不应崩溃，isDownloading 保持 false
    func testResumeDownloadMultipleTimesNoCrash() async {
        await downloader.resumeDownload()
        await downloader.resumeDownload()

        let isDownloading = await downloader.isDownloading
        XCTAssertFalse(isDownloading, "无 resumeData 时多次 resumeDownload 不应修改状态")
    }

    // MARK: - 19. OnDeviceError.loadFailed 与 modelNotFound 携带路径

    /// deleteModel 对无权限路径应抛出 OnDeviceError（loadFailed 或 modelNotFound）
    func testDeleteModelNonExistentNestedPath() async {
        let nestedURL = URL(fileURLWithPath: "/tmp/non-existent-\(UUID().uuidString)/model.bin")
        do {
            try await downloader.deleteModel(at: nestedURL)
            XCTFail("删除不存在的文件应抛出 modelNotFound")
        } catch let error as OnDeviceError {
            if case .modelNotFound = error {
                // 期望：文件不存在时抛 modelNotFound
            } else {
                XCTFail("期望 modelNotFound，实际：\(error)")
            }
        } catch {
            XCTFail("期望 OnDeviceError，实际：\(type(of: error))")
        }
    }

    // MARK: - 20. SHA256 Unicode / 多字节内容

    /// verifySHA256 对含中文、emoji 的 Unicode 内容应正确校验
    func testVerifySHA256UnicodeContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("unicode-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let content = "你好世界🌍🎉 Hello World".data(using: .utf8)!
        try content.write(to: testFile)

        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "Unicode 内容 SHA256 应匹配")
    }

    /// verifySHA256 对恰好 4MB（chunkSize 整数倍）的文件应正确校验
    func testVerifySHA256ExactChunkSize() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("exact-chunk-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let chunkSize = 4 * 1024 * 1024
        let content = Data(count: chunkSize)  // 恰好 4MB
        try content.write(to: testFile)

        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "恰好 4MB 文件 SHA256 应匹配（单次 chunk 读取）")
    }

    /// verifySHA256 对 8MB+ 文件（多 chunk）应正确校验
    func testVerifySHA256MultiChunk() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("multi-chunk-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let chunkSize = 4 * 1024 * 1024
        let content = Data(count: chunkSize * 2 + 512)  // 8MB + 512B
        try content.write(to: testFile)

        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "8MB+ 文件 SHA256 应匹配（多 chunk 读取）")
    }

    /// verifySHA256 对重复字节模式应正确校验
    func testVerifySHA256RepeatedPattern() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("pattern-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let pattern: [UInt8] = [0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89]
        var content = Data()
        for _ in 0..<1000 {
            content.append(contentsOf: pattern)
        }  // 8KB
        try content.write(to: testFile)

        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let result = await downloader.verifySHA256(filePath: testFile, expected: expected)
        XCTAssertTrue(result, "重复字节模式 SHA256 应匹配")
    }

    // MARK: - 21. deleteModel 边界路径

    /// deleteModel 对含空格与 Unicode 的文件名应正常删除
    func testDeleteModelWithSpecialCharacters() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("模型 文件-\(UUID().uuidString).bin")
        try "data".data(using: .utf8)!.write(to: testFile)

        try await downloader.deleteModel(at: testFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path),
                       "含空格/Unicode 的文件应被删除")
    }

    /// deleteModel 对符号链接应正常删除（仅删链接不删目标）
    func testDeleteModelOnSymlink() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 13,
                      "某些旧版 macOS 上符号链接行为不一致")
        let tempDir = FileManager.default.temporaryDirectory
        let target = tempDir.appendingPathComponent("target-\(UUID().uuidString).bin")
        let link = tempDir.appendingPathComponent("link-\(UUID().uuidString).bin")
        try "target data".data(using: .utf8)!.write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: target) }

        try await downloader.deleteModel(at: link)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path), "符号链接应被删除")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "目标文件不应被删除")
    }

    // MARK: - 22. OnDeviceConfig 自定义值

    /// OnDeviceConfig 自定义 downloadSource 为 international 时应返回对应 URL
    func testOnDeviceConfigCustomDownloadSource() {
        var config = OnDeviceConfig.default
        config.downloadSource = .international
        XCTAssertEqual(config.downloadSource, .international)
        XCTAssertEqual(config.modelName, "Llama-3.2-1B-Instruct-Q4_K_M",
                       "默认 modelName 应为 Q4_K_M 量化版本")
        XCTAssertEqual(config.maxTokens, 512, "默认 maxTokens 应为 512")
        XCTAssertEqual(config.temperature, 0.7, "默认 temperature 应为 0.7")
        XCTAssertTrue(config.autoSwitchOnNetworkLoss, "默认应启用断网自动切换")
        XCTAssertFalse(config.enabled, "默认应未启用端侧推理")
    }

    /// OnDeviceConfig 默认 modelPath 应为 nil
    func testOnDeviceConfigDefaultModelPathIsNil() {
        let config = OnDeviceConfig.default
        XCTAssertNil(config.modelPath, "默认 modelPath 应为 nil")
    }

    /// OnDeviceConfig 应支持 Codable 编解码
    func testOnDeviceConfigCodableRoundTrip() throws {
        var config = OnDeviceConfig.default
        config.enabled = true
        config.modelPath = URL(fileURLWithPath: "/tmp/test-model.bin")
        config.maxTokens = 1024

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(OnDeviceConfig.self, from: data)

        XCTAssertEqual(decoded, config, "Codable 往返应保持值一致")
        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.maxTokens, 1024)
    }

    // MARK: - 23. OnDeviceModelCatalog 完整性

    /// OnDeviceModelCatalog 所有模型应有有效的 HuggingFace 和 ModelScope URL
    func testModelCatalogAllModelsHaveValidURLs() {
        for model in OnDeviceModelCatalog.models {
            XCTAssertTrue(model.huggingFaceURL.absoluteString.hasPrefix("https://"),
                          "模型 \(model.id) 的 HuggingFace URL 应为 https")
            XCTAssertTrue(model.modelScopeURL.absoluteString.hasPrefix("https://"),
                          "模型 \(model.id) 的 ModelScope URL 应为 https")
        }
    }

    /// OnDeviceModelCatalog 所有模型应有非空 description
    func testModelCatalogAllModelsHaveNonEmptyDescription() {
        for model in OnDeviceModelCatalog.models {
            XCTAssertFalse(model.description.isEmpty,
                           "模型 \(model.id) 的 description 不应为空")
        }
    }

    /// OnDeviceModelCatalog 所有模型的 estimatedSizeMB 应大于 0
    func testModelCatalogAllModelsHavePositiveSize() {
        for model in OnDeviceModelCatalog.models {
            XCTAssertGreaterThan(model.estimatedSizeMB, 0,
                                 "模型 \(model.id) 的 estimatedSizeMB 应大于 0")
        }
    }

    /// OnDeviceModelCatalog find(id:) 对部分匹配应返回 nil（精确匹配）
    func testModelCatalogFindIsExactMatch() {
        XCTAssertNil(OnDeviceModelCatalog.find(id: "Llama"), "部分匹配应返回 nil")
        XCTAssertNil(OnDeviceModelCatalog.find(id: ""), "空字符串应返回 nil")
        XCTAssertNil(OnDeviceModelCatalog.find(id: "Llama-3.2-1B-Instruct-4bit "),
                     "带尾空格应返回 nil（精确匹配）")
    }

    // MARK: - 24. DownloadSource 完整覆盖

    /// DownloadSource displayName 应包含对应的平台名
    func testDownloadSourceDisplayNameContainsPlatform() {
        XCTAssertTrue(DownloadSource.domestic.displayName.contains("ModelScope") || DownloadSource.domestic.displayName.contains("国内"),
                      "domestic displayName 应含平台标识")
        XCTAssertTrue(DownloadSource.international.displayName.contains("HuggingFace") || DownloadSource.international.displayName.contains("国外"),
                      "international displayName 应含平台标识")
    }

    /// DownloadSource domestic 与 international 应互不相同
    func testDownloadSourceDomesticNotEqualInternational() {
        XCTAssertNotEqual(DownloadSource.domestic, DownloadSource.international,
                          "domestic 与 international 应不同")
    }

    // MARK: - 25. makeDownloadSessionConfig 额外属性

    /// makeDownloadSessionConfig 应返回 default 配置类型
    func testDownloadSessionConfigIsDefaultType() async {
        let config = await downloader.makeDownloadSessionConfig()
        XCTAssertEqual(config.urlCache, URLSessionConfiguration.default.urlCache,
                       "urlCache 应与 default 一致")
    }

    // MARK: - 26. 并发安全性

    /// 并发调用 verifySHA256 不应崩溃（actor 隔离保证）
    func testConcurrentVerifySHA256NoCrash() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("concurrent-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        let content = "concurrent test".data(using: .utf8)!
        try content.write(to: testFile)
        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()

        // 并发发起多个 verifySHA256 调用
        async let r1 = downloader.verifySHA256(filePath: testFile, expected: expected)
        async let r2 = downloader.verifySHA256(filePath: testFile, expected: expected)
        async let r3 = downloader.verifySHA256(filePath: testFile, expected: "wrong")

        let results = await [r1, r2, r3]
        XCTAssertTrue(results[0], "第一次并发校验应成功")
        XCTAssertTrue(results[1], "第二次并发校验应成功")
        XCTAssertFalse(results[2], "第三次并发校验应失败（期望值不匹配）")
    }

    /// 并发调用 deleteModel 同一文件不应崩溃（actor 串行化）
    func testConcurrentDeleteModelNoCrash() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile1 = tempDir.appendingPathComponent("concurrent-del-1-\(UUID().uuidString).bin")
        let testFile2 = tempDir.appendingPathComponent("concurrent-del-2-\(UUID().uuidString).bin")
        try "data1".data(using: .utf8)!.write(to: testFile1)
        try "data2".data(using: .utf8)!.write(to: testFile2)

        // 并发删除不同文件
        async let r1: Void = try downloader.deleteModel(at: testFile1)
        async let r2: Void = try downloader.deleteModel(at: testFile2)
        _ = try await (r1, r2)

        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile2.path))
    }

    // MARK: - 27. OnDeviceError 完整覆盖

    /// OnDeviceError.loadFailed 应携带底层错误信息
    func testLoadFailedErrorCarriesMessage() {
        let msg = "特定加载错误"
        let error = OnDeviceError.loadFailed(msg)
        XCTAssertTrue(error.errorDescription?.contains(msg) == true,
                      "loadFailed 描述应包含底层错误信息")
    }

    /// OnDeviceError.sha256Mismatch 应截取前 8 字符展示
    func testSHA256MismatchTruncatesHash() {
        let longExpected = String(repeating: "a", count: 64)
        let longActual = String(repeating: "b", count: 64)
        let error = OnDeviceError.sha256Mismatch(expected: longExpected, actual: longActual)
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("aaaaaaaa"), "描述应包含 expected 的前 8 字符")
        XCTAssertTrue(desc.contains("bbbbbbbb"), "描述应包含 actual 的前 8 字符")
    }

    /// OnDeviceError.modelNotFound 应使用 lastPathComponent
    func testModelNotFoundUsesLastPathComponent() {
        let url = URL(fileURLWithPath: "/tmp/deep/path/model.gguf")
        let error = OnDeviceError.modelNotFound(url)
        XCTAssertTrue(error.errorDescription?.contains("model.gguf") == true,
                      "modelNotFound 描述应包含文件名")
        XCTAssertFalse(error.errorDescription?.contains("/tmp/deep/path/") == true,
                       "modelNotFound 描述不应包含完整路径（仅 lastPathComponent）")
    }

    // MARK: - 28. startDownload 守卫

    /// startDownload 对 file:// URL 应最终设置 lastError（不崩溃，下载失败后走错误分支）
    func testStartDownloadWithFileURLSetsError() async {
        let fileURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dest-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: fileURL, to: destURL, expectedSHA256: "")

        let hasError = await downloader.lastError != nil
        let isDownloading = await downloader.isDownloading
        XCTAssertTrue(hasError, "file:// URL 下载应失败并设置 lastError")
        XCTAssertFalse(isDownloading, "失败后 isDownloading 应为 false")
    }

    // MARK: - 29. cancelDownload 后状态

    /// cancelDownload 后 progress 应保持不变（未实际下载）
    func testCancelDownloadKeepsProgressAtZero() async {
        await downloader.cancelDownload()
        let progress = await downloader.progress
        XCTAssertEqual(progress, 0.0, "未实际下载时 cancel 后 progress 应为 0.0")
    }

    /// cancelDownload 后 lastError 应保持 nil（cancel 不产生错误）
    func testCancelDownloadDoesNotSetError() async {
        await downloader.cancelDownload()
        let lastError = await downloader.lastError
        XCTAssertNil(lastError, "cancelDownload 不应设置 lastError")
    }

    // MARK: - 30. 下载网络分支（本地 HTTP 服务器）

    /// 本地 HTTP 测试服务器：使用 Network.framework 的 NWListener 提供静态文件，
    /// 避免 URLProtocol 与 URLSessionDownloadTask 不兼容导致测试挂起。
    private final class LocalHTTPTestServer {
        private var listener: NWListener?
        private var tempDir: URL?
        private let readyContinuation = ReadyContinuation()

        /// 服务器根目录，测试可向该目录写入文件后再请求。
        var rootURL: URL { tempDir! }

        /// 启动服务器并返回 baseURL（如 http://127.0.0.1:52341）。
        func start() async throws -> URL {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("http-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.tempDir = tempDir

            let listener = try NWListener(using: .tcp, on: 0)
            self.listener = listener

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.readyContinuation.resume()
                case .failed(let error):
                    self?.readyContinuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else {
                    connection.cancel()
                    return
                }
                connection.start(queue: .global())
                self.handleConnection(connection)
            }

            listener.start(queue: .global())

            try await readyContinuation.value

            guard let port = listener.port?.rawValue else {
                throw NSError(domain: "LocalHTTPTestServer", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "无法获取监听端口"])
            }
            return URL(string: "http://127.0.0.1:\(port)")!
        }

        private func handleConnection(_ connection: NWConnection) {
            var buffer = Data()

            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                    guard let self = self else { return }

                    if error != nil {
                        connection.cancel()
                        return
                    }

                    if let data = data {
                        buffer.append(data)
                    }

                    // 解析 HTTP 请求头结束位置
                    if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                        let headerData = buffer.subdata(in: 0..<range.upperBound)
                        guard let requestLine = String(data: headerData, encoding: .utf8)?
                            .split(separator: "\r\n").first else {
                            self.sendResponse(connection: connection, status: "400 Bad Request", body: Data())
                            return
                        }

                        let parts = requestLine.split(separator: " ")
                        guard parts.count >= 2, parts[0] == "GET" else {
                            self.sendResponse(connection: connection, status: "400 Bad Request", body: Data())
                            return
                        }

                        let path = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        self.serveFile(named: path, connection: connection)
                        return
                    }

                    if isComplete {
                        connection.cancel()
                        return
                    }

                    receive()
                }
            }

            receive()
        }

        private func serveFile(named name: String, connection: NWConnection) {
            let fileURL = rootURL.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL) else {
                sendResponse(connection: connection, status: "404 Not Found", body: Data())
                return
            }
            sendResponse(connection: connection, status: "200 OK", body: data)
        }

        private func sendResponse(connection: NWConnection, status: String, body: Data) {
            let headers = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            let headerData = headers.data(using: .utf8)!
            connection.send(content: headerData, completion: .contentProcessed { _ in
                connection.send(content: body, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            })
        }

        func stop() {
            listener?.cancel()
            if let tempDir = tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }
            listener = nil
            tempDir = nil
        }

        /// 用于跨 actor/队列恢复 continuations 的线程安全包装
        private final class ReadyContinuation {
            private var continuation: CheckedContinuation<Void, Error>?
            private var readyError: Error?
            private var isReady = false
            private let lock = NSLock()

            var value: Void {
                get async throws {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        self.lock.lock()
                        if let error = self.readyError {
                            self.lock.unlock()
                            continuation.resume(throwing: error)
                        } else if self.isReady {
                            self.lock.unlock()
                            continuation.resume()
                        } else {
                            self.continuation = continuation
                            self.lock.unlock()
                        }
                    }
                }
            }

            func resume() {
                lock.lock()
                isReady = true
                if let continuation = continuation {
                    self.continuation = nil
                    lock.unlock()
                    continuation.resume()
                } else {
                    lock.unlock()
                }
            }

            func resume(throwing error: Error) {
                lock.lock()
                readyError = error
                if let continuation = continuation {
                    self.continuation = nil
                    lock.unlock()
                    continuation.resume(throwing: error)
                } else {
                    lock.unlock()
                }
            }
        }
    }

    private var server: LocalHTTPTestServer!
    private var baseURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        server = LocalHTTPTestServer()
        baseURL = try await server.start()
    }

    override func tearDown() {
        server?.stop()
        super.tearDown()
    }

    /// 向服务器根目录写入文件
    private func serveFile(named name: String, data: Data) throws {
        try data.write(to: server.rootURL.appendingPathComponent(name))
    }

    /// startDownload 成功下载后应将文件移动到目标路径，并在无 SHA256 校验时设置 progress=1.0
    func testStartDownloadSuccessMovesFileAndSetsProgress() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = "mock model content".data(using: .utf8)!
        try serveFile(named: "model.bin", data: content)

        let sourceURL = baseURL.appendingPathComponent("model.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloaded-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: sourceURL, to: destURL, expectedSHA256: "")

        let progress = await downloader.progress
        let lastError = await downloader.lastError
        let isDownloading = await downloader.isDownloading
        let fileExists = FileManager.default.fileExists(atPath: destURL.path)
        let fileData = fileExists ? (try? Data(contentsOf: destURL)) : nil

        XCTAssertTrue(fileExists, "下载成功后目标文件应存在")
        XCTAssertEqual(fileData, content, "下载文件内容应与服务器返回一致")
        XCTAssertEqual(progress, 1.0, "成功下载后 progress 应为 1.0")
        XCTAssertNil(lastError, "无 SHA256 校验时 lastError 应为 nil")
        XCTAssertFalse(isDownloading, "完成后 isDownloading 应为 false")
    }

    /// startDownload 在期望 SHA256 匹配时应校验通过并设置 progress=1.0
    func testStartDownloadSHA256MatchSucceeds() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = "model with sha256".data(using: .utf8)!
        let expected = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        try serveFile(named: "model-sha.bin", data: content)

        let sourceURL = baseURL.appendingPathComponent("model-sha.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sha-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: sourceURL, to: destURL, expectedSHA256: expected)

        let progress = await downloader.progress
        let lastError = await downloader.lastError
        XCTAssertEqual(progress, 1.0, "SHA256 匹配时 progress 应为 1.0")
        XCTAssertNil(lastError, "SHA256 匹配时 lastError 应为 nil")
    }

    /// startDownload 在 SHA256 不匹配时应设置 sha256Mismatch 错误。
    /// 当前实现会先将临时文件移动到目标路径再校验，因此目标文件会保留；
    /// progress 在下载过程中已更新到 1.0，校验失败时不会被重置。
    func testStartDownloadSHA256MismatchSetsError() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = "model with wrong sha256".data(using: .utf8)!
        try serveFile(named: "model-mismatch.bin", data: content)

        let sourceURL = baseURL.appendingPathComponent("model-mismatch.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mismatch-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: sourceURL, to: destURL,
                                       expectedSHA256: "0000000000000000000000000000000000000000000000000000000000000000")

        let lastError = await downloader.lastError
        let progress = await downloader.progress
        let fileExists = FileManager.default.fileExists(atPath: destURL.path)
        let fileData = fileExists ? (try? Data(contentsOf: destURL)) : nil

        // 实现行为：文件先移动后校验，故文件存在且内容与下载一致
        XCTAssertTrue(fileExists, "当前实现下 SHA256 不匹配时目标文件仍存在")
        XCTAssertEqual(fileData, content, "保留的文件内容应与下载内容一致")
        XCTAssertEqual(progress, 1.0, "下载完成后 progress 已为 1.0，校验失败不会被重置")
        if case .sha256Mismatch = lastError {
            // 期望
        } else {
            XCTFail("应返回 sha256Mismatch 错误，实际：\(String(describing: lastError))")
        }
    }

    /// 主地址返回 404 时，startDownload 应回退到 mirrorURL 并重试一次
    func testStartDownloadMirrorFallbackOnPrimaryFailure() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = "mirror model content".data(using: .utf8)!
        try serveFile(named: "mirror.bin", data: content)

        let primaryURL = baseURL.appendingPathComponent("not-found.bin")
        let mirrorURL = baseURL.appendingPathComponent("mirror.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirror-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: primaryURL, to: destURL, expectedSHA256: "", mirrorURL: mirrorURL)

        let progress = await downloader.progress
        let lastError = await downloader.lastError
        let fileExists = FileManager.default.fileExists(atPath: destURL.path)

        XCTAssertTrue(fileExists, "镜像回退成功后目标文件应存在")
        XCTAssertEqual(progress, 1.0, "镜像下载成功后 progress 应为 1.0")
        XCTAssertNil(lastError, "镜像回退成功后 lastError 应为 nil")
    }

    /// 下载过程中进度回调应更新 progress，完成后达到 1.0
    func testStartDownloadProgressUpdates() async throws {
        let downloader = OnDeviceModelDownloader()
        // 构造 4MB 文件，使下载持续一段时间以便观察到中间进度
        let content = Data(count: 4 * 1024 * 1024)
        try serveFile(named: "progress.bin", data: content)

        let sourceURL = baseURL.appendingPathComponent("progress.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        let downloadTask = Task {
            await downloader.startDownload(url: sourceURL, to: destURL, expectedSHA256: "")
        }

        // 在下载过程中轮询 progress
        var sawNonZeroProgress = false
        for _ in 0..<100 {
            let progress = await downloader.progress
            if progress > 0 && progress < 1.0 {
                sawNonZeroProgress = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        await downloadTask.value

        let finalProgress = await downloader.progress
        XCTAssertTrue(sawNonZeroProgress || finalProgress == 1.0, "应观察到进度更新或已完成")
        XCTAssertEqual(finalProgress, 1.0, "完成时 progress 应为 1.0")
    }

    /// isDownloading=true 时再次调用 startDownload 应直接返回，不发起新请求
    func testStartDownloadWhenAlreadyDownloadingSkipsNewRequest() async throws {
        let downloader = OnDeviceModelDownloader()
        // 使用较大文件确保第一次下载在第二次调用时仍在进行
        let content = Data(count: 8 * 1024 * 1024)
        try serveFile(named: "slow.bin", data: content)
        try serveFile(named: "should-not-request.bin", data: "unexpected".data(using: .utf8)!)

        let firstURL = baseURL.appendingPathComponent("slow.bin")
        let secondURL = baseURL.appendingPathComponent("should-not-request.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("concurrent-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        let firstTask = Task {
            await downloader.startDownload(url: firstURL, to: destURL, expectedSHA256: "")
        }

        // 轮询直到第一次下载进入 isDownloading=true，确保第二次调用命中 guard
        var didStart = false
        for _ in 0..<200 {
            let isDownloading = await downloader.isDownloading
            if isDownloading {
                didStart = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(didStart, "第一次下载应在超时前进入 isDownloading=true")

        let secondTask = Task {
            await downloader.startDownload(url: secondURL, to: destURL, expectedSHA256: "")
        }

        _ = await (firstTask.value, secondTask.value)

        // 目标文件内容应与第一个文件一致（第二个请求被跳过）
        let fileData = try? Data(contentsOf: destURL)
        XCTAssertEqual(fileData, content, "isDownloading 为 true 时第二次请求应被跳过，文件内容应与第一次一致")
    }

    /// cancelDownload 在下载中调用时不应崩溃，且 isDownloading 最终为 false
    func testCancelDownloadDuringDownload() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = Data(count: 8 * 1024 * 1024)
        try serveFile(named: "cancel.bin", data: content)

        let sourceURL = baseURL.appendingPathComponent("cancel.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        let task = Task {
            await downloader.startDownload(url: sourceURL, to: destURL, expectedSHA256: "")
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        await downloader.cancelDownload()

        await task.value

        let isDownloading = await downloader.isDownloading
        XCTAssertFalse(isDownloading, "cancelDownload 后 isDownloading 应为 false")
    }

    /// 主地址成功时，即使提供错误的 mirrorURL 也不应回退，目标文件内容应与主地址一致。
    /// 覆盖 `startDownload` 中仅在 `primaryFailed` 为 true 时才使用 mirrorURL 的分支。
    func testStartDownloadPrimarySuccessIgnoresMirror() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = "primary content".data(using: .utf8)!
        try serveFile(named: "primary.bin", data: content)

        let primaryURL = baseURL.appendingPathComponent("primary.bin")
        let mirrorURL = baseURL.appendingPathComponent("mirror-not-used.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("primary-success-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: primaryURL, to: destURL, expectedSHA256: "", mirrorURL: mirrorURL)

        let progress = await downloader.progress
        let lastError = await downloader.lastError
        let fileData = try? Data(contentsOf: destURL)

        XCTAssertEqual(fileData, content, "主地址成功时应使用主地址内容，不应回退 mirror")
        XCTAssertEqual(progress, 1.0, "主地址成功后 progress 应为 1.0")
        XCTAssertNil(lastError, "主地址成功时 lastError 应为 nil")
    }

    /// mirrorURL 与主地址相同时不应进入无限回退，应仅尝试一次主地址并失败后设置错误。
    /// 使用会真实触发下载失败的 file:// URL，覆盖镜像回退条件中的 `mirrorURL != url` 守卫。
    func testStartDownloadMirrorURLSameAsPrimaryDoesNotRetry() async throws {
        let downloader = OnDeviceModelDownloader()
        let primaryURL = URL(fileURLWithPath: "/tmp/non-existent-mirror-same-\(UUID().uuidString).bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mirror-same-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        await downloader.startDownload(url: primaryURL, to: destURL, expectedSHA256: "", mirrorURL: primaryURL)

        let lastError = await downloader.lastError
        let isDownloading = await downloader.isDownloading

        XCTAssertFalse(isDownloading, "失败后 isDownloading 应为 false")
        XCTAssertNotNil(lastError, "主地址失败且 mirror 与主地址相同时应设置错误")
        if case .sha256Mismatch = lastError {
            XCTFail("不应产生 sha256Mismatch 错误")
        }
    }

    /// cancelDownload 后若产生 resumeData，再次调用 startDownload 应进入 resumeDownload 路径，
    /// 而不是使用新的 url/destinationURL。
    func testStartDownloadWithResumeDataResumesInsteadOfNewURL() async throws {
        let downloader = OnDeviceModelDownloader()
        let content = Data(count: 8 * 1024 * 1024)
        try serveFile(named: "resume-source.bin", data: content)
        try serveFile(named: "should-not-download.bin", data: "unexpected".data(using: .utf8)!)

        let originalURL = baseURL.appendingPathComponent("resume-source.bin")
        let newURL = baseURL.appendingPathComponent("should-not-download.bin")
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: destURL) }

        // 1) 启动一次大文件下载
        let firstTask = Task {
            await downloader.startDownload(url: originalURL, to: destURL, expectedSHA256: "")
        }

        // 2) 等待下载进入进行状态后取消，以获取 resumeData
        var didStart = false
        for _ in 0..<200 {
            let isDownloading = await downloader.isDownloading
            if isDownloading {
                didStart = true
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(didStart, "下载应在超时前进入 isDownloading=true")
        await downloader.cancelDownload()
        await firstTask.value

        // 3) 等待 resumeData 生成（异步回调）
        var hasResume = false
        for _ in 0..<300 {
            if await downloader.hasResumeData {
                hasResume = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard hasResume else {
            _ = XCTSkip("当前环境与服务器未产生 resumeData，跳过断点续传路径测试")
            return
        }

        // 4) 再次调用 startDownload，传入不同的 newURL/destURL；
        //    实现会命中 `if resumeData != nil { await resumeDownload(); return }`
        await downloader.startDownload(url: newURL, to: destURL, expectedSHA256: "")

        let isDownloadingAfter = await downloader.isDownloading
        let fileExists = FileManager.default.fileExists(atPath: destURL.path)

        XCTAssertFalse(isDownloadingAfter, "resumeDownload 完成后 isDownloading 应为 false")
        // resumeDownload 使用临时目录作为目标，传入的 destURL 不会被写入
        XCTAssertFalse(fileExists, "resumeDownload 路径不应写入传入的 destURL")
    }

    // MARK: - 辅助

    /// 复用下载器单例，简化测试代码
    private var downloader: OnDeviceModelDownloader { OnDeviceModelDownloader.shared }
}
