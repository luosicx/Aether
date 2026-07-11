import XCTest
import CryptoKit
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

    /// verifySHA256 空字符串期望值应视为匹配（源码：!expectedSHA256.isEmpty 时才校验）
    func testVerifySHA256EmptyExpectedReturnsTrue() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test-model-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: testFile) }

        try "content".data(using: .utf8)!.write(to: testFile)

        // 空字符串期望值：源码中 !expectedSHA256.isEmpty 为 false，跳过校验直接成功
        let result = await downloader.verifySHA256(filePath: testFile, expected: "")
        XCTAssertTrue(result, "空字符串期望值应跳过校验返回 true")
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
    func testInsufficientMemoryErrorDescription() {
        let error = OnDeviceError.insufficientMemory
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("内存") == true,
                      "insufficientMemory 描述应含「内存」")
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
    func testSHA256MismatchErrorDescription() {
        let error = OnDeviceError.sha256Mismatch(expected: "abcdef1234567890", actual: "9876543210fedcba")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("校验失败") == true,
                      "sha256Mismatch 描述应含「校验失败」")
    }

    /// OnDeviceError.unsupportedQuantization 错误描述
    func testUnsupportedQuantizationErrorDescription() {
        let error = OnDeviceError.unsupportedQuantization
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("量化") == true,
                      "unsupportedQuantization 描述应含「量化」")
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

    // MARK: - 辅助

    /// 复用下载器单例，简化测试代码
    private var downloader: OnDeviceModelDownloader { OnDeviceModelDownloader.shared }
}
