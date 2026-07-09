import XCTest
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
}
