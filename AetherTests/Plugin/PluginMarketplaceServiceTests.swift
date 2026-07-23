import XCTest
import CryptoKit
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// v1.1 Phase C 测试：PluginMarketplaceService 的下载、签名校验与搜索。
///
/// 覆盖范围：
/// 1. Ed25519 签名校验（verifySignature）
/// 2. 搜索过滤（searchPlugins）
/// 3. fetchPluginList（通过 URLProtocol mock）
/// 4. downloadPlugin（通过 URLProtocol mock，验证文件写入）
@MainActor
final class PluginMarketplaceServiceTests: XCTestCase {

    // MARK: - 签名校验

    /// Ed25519 签名校验：有效签名应返回 true
    func testVerifySignatureValid() throws {
        // 生成 Ed25519 密钥对
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let pubKeyData = publicKey.rawRepresentation
        let pubKeyBase64 = pubKeyData.base64EncodedString()

        // 签名数据
        let data = "test plugin content".data(using: .utf8)!
        let signature = try privateKey.signature(for: data)
        let signatureBase64 = signature.base64EncodedString()

        // 验签
        let result = PluginMarketplaceService.verifySignature(
            data: data,
            signature: signatureBase64,
            publicKeyBase64: pubKeyBase64
        )
        XCTAssertTrue(result, "有效签名应验签通过")
    }

    /// Ed25519 签名校验：篡改数据后应返回 false
    func testVerifySignatureTamperedData() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let pubKeyBase64 = publicKey.rawRepresentation.base64EncodedString()

        let originalData = "original content".data(using: .utf8)!
        let signature = try privateKey.signature(for: originalData)
        let signatureBase64 = signature.base64EncodedString()

        // 篡改数据
        let tamperedData = "tampered content".data(using: .utf8)!
        let result = PluginMarketplaceService.verifySignature(
            data: tamperedData,
            signature: signatureBase64,
            publicKeyBase64: pubKeyBase64
        )
        XCTAssertFalse(result, "篡改数据后验签应失败")
    }

    /// Ed25519 签名校验：无效 base64 应返回 false
    func testVerifySignatureInvalidBase64() {
        let data = Data([0x01, 0x02])
        let result = PluginMarketplaceService.verifySignature(
            data: data,
            signature: "not-valid-base64!!!",
            publicKeyBase64: "also-not-valid!!!"
        )
        XCTAssertFalse(result, "无效 base64 输入应返回 false")
    }

    /// 实例方法 verifySignature：未配置公钥时应跳过验签返回 true
    func testVerifySignatureNoPublicKeyReturnsTrue() {
        let service = PluginMarketplaceService(publicKeyBase64: nil)
        let data = Data([0x01, 0x02])
        let result = service.verifySignature(data: data, signature: "any")
        XCTAssertTrue(result, "未配置公钥时应跳过验签返回 true")
    }

    // MARK: - 搜索过滤

    /// searchPlugins 应按 name / description / author 过滤
    func testSearchPluginsFiltersByName() async throws {
        let service = try await makeServiceWithPlugins([
            makeManifest(id: "1", name: "Weather Plugin", description: "天气", author: "Alice"),
            makeManifest(id: "2", name: "Calculator", description: "计算器", author: "Bob"),
            makeManifest(id: "3", name: "Translator", description: "weather forecast", author: "Carol"),
        ])

        // 按名称搜索
        XCTAssertEqual(service.searchPlugins(query: "Weather").count, 2, "应匹配 name 和 description 含 weather 的插件")

        // 按作者搜索
        XCTAssertEqual(service.searchPlugins(query: "Bob").count, 1, "应匹配 author 含 Bob 的插件")

        // 空查询返回全部
        XCTAssertEqual(service.searchPlugins(query: "").count, 3, "空查询应返回全部插件")

        // 无匹配
        XCTAssertEqual(service.searchPlugins(query: "nonexistent").count, 0, "无匹配应返回空数组")
    }

    /// searchPlugins 应大小写不敏感
    func testSearchPluginsCaseInsensitive() async throws {
        let service = try await makeServiceWithPlugins([
            makeManifest(id: "1", name: "WeatherPlugin", description: "天气", author: "Alice"),
        ])

        XCTAssertEqual(service.searchPlugins(query: "weather").count, 1)
        XCTAssertEqual(service.searchPlugins(query: "WEATHER").count, 1)
        XCTAssertEqual(service.searchPlugins(query: "WeatherPlugin").count, 1)
    }

    // MARK: - fetchPluginList（URLProtocol mock）

    /// fetchPluginList 应从远程 JSON 解码插件列表
    func testFetchPluginListWithMockURLProtocol() async throws {
        let plugins = [
            makeManifest(id: "fetch-1", name: "Fetched Plugin", version: "1.0.0"),
        ]
        let jsonData = try JSONEncoder().encode(plugins)

        let mockURL = URL(string: "https://mock.example.com/registry.json")!
        let session = makeMockSession(for: mockURL, data: jsonData)

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        try await service.fetchPluginList()

        XCTAssertEqual(service.plugins.count, 1)
        XCTAssertEqual(service.plugins.first?.id, "fetch-1")
        XCTAssertEqual(service.plugins.first?.name, "Fetched Plugin")
    }

    /// fetchPluginList HTTP 错误应抛出异常
    func testFetchPluginListHTTPError() async {
        let mockURL = URL(string: "https://mock.example.com/error.json")!
        let session = makeMockSession(for: mockURL, data: Data(), error: NSError(domain: "test", code: 500))

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        do {
            try await service.fetchPluginList()
            XCTFail("应抛出错误")
        } catch {
            XCTAssertNotNil(service.lastError)
        }
    }

    // MARK: - downloadPlugin（URLProtocol mock）

    /// downloadPlugin 应下载 JS 文件并写入插件目录
    func testDownloadPluginWritesFiles() async throws {
        let pluginID = "download-test-\(UUID().uuidString.prefix(8))"
        let jsContent = "function execute(args) { return 'downloaded'; }"
        let jsData = jsContent.data(using: .utf8)!

        let downloadURL = URL(string: "https://mock.example.com/\(pluginID).js")!
        let session = makeMockSession(for: downloadURL, data: jsData)

        let manifest = PluginManifest(
            id: pluginID, name: "下载测试", version: "1.0.0", author: "测试",
            description: "下载测试", tools: [], permissions: [],
            entryPoint: "main.js",
            downloadURL: downloadURL
        )

        let service = PluginMarketplaceService(urlSession: session)
        try await service.downloadPlugin(manifest: manifest)

        // 验证文件写入
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)

        defer { try? fm.removeItem(at: pluginDir) }

        let jsFileURL = pluginDir.appendingPathComponent("main.js")
        let manifestURL = pluginDir.appendingPathComponent("manifest.json")

        XCTAssertTrue(fm.fileExists(atPath: jsFileURL.path), "JS 入口文件应被写入")
        XCTAssertTrue(fm.fileExists(atPath: manifestURL.path), "manifest.json 应被写入")

        let writtenJS = try String(contentsOf: jsFileURL, encoding: .utf8)
        XCTAssertEqual(writtenJS, jsContent, "写入的 JS 内容应与下载内容一致")

        let writtenManifestData = try Data(contentsOf: manifestURL)
        let writtenManifest = try JSONDecoder().decode(PluginManifest.self, from: writtenManifestData)
        XCTAssertEqual(writtenManifest.id, pluginID)
    }

    /// downloadPlugin 缺少 downloadURL 应抛出错误
    func testDownloadPluginWithoutURLThrows() async {
        let manifest = PluginManifest(
            id: "no-url", name: "无URL", version: "1.0.0", author: "测试",
            description: "无下载地址", tools: [], permissions: [],
            entryPoint: "main.js",
            downloadURL: nil
        )
        let service = PluginMarketplaceService()
        do {
            try await service.downloadPlugin(manifest: manifest)
            XCTFail("应抛出无下载地址错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("下载地址"))
        }
    }

    // MARK: - checkUpdate

    /// checkUpdate 远程存在新版本时应返回非 nil 版本号
    func testCheckUpdateReturnsNewVersionWhenAvailable() async throws {
        let plugins = [
            makeManifest(id: "update-target", name: "可更新插件", version: "2.5.0"),
        ]
        let jsonData = try JSONEncoder().encode(plugins)
        let mockURL = URL(string: "https://mock.example.com/check-update-new.json")!
        let session = makeMockSession(for: mockURL, data: jsonData)

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        let version = try await service.checkUpdate(for: "update-target")
        XCTAssertEqual(version, "2.5.0", "远程存在插件时应返回版本号")
    }

    /// checkUpdate 在 plugins 已预加载但不含目标插件时应返回 nil（不重新 fetch）
    func testCheckUpdateReturnsNilWhenNoUpdateAvailable() async throws {
        // 预加载一个不含目标插件的列表
        let plugins = [
            makeManifest(id: "other-plugin", name: "其他插件", version: "1.0.0"),
        ]
        let jsonData = try JSONEncoder().encode(plugins)
        let mockURL = URL(string: "https://mock.example.com/check-update-none.json")!
        let session = makeMockSession(for: mockURL, data: jsonData)

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        try await service.fetchPluginList()
        // plugins 非空，checkUpdate 不会重新 fetch，直接返回 nil
        let version = try await service.checkUpdate(for: "missing-target")
        XCTAssertNil(version, "预加载列表中无目标插件时应返回 nil")
    }

    /// checkUpdate 在远程列表中找不到指定插件时应返回 nil
    func testCheckUpdateReturnsNilWhenPluginNotFound() async throws {
        let plugins = [
            makeManifest(id: "exists", name: "存在插件", version: "1.0.0"),
        ]
        let jsonData = try JSONEncoder().encode(plugins)
        let mockURL = URL(string: "https://mock.example.com/check-update-notfound.json")!
        let session = makeMockSession(for: mockURL, data: jsonData)

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        let version = try await service.checkUpdate(for: "non-existent-id")
        XCTAssertNil(version, "远程列表中找不到插件时应返回 nil")
    }

    // MARK: - downloadPlugin 错误路径

    /// downloadPlugin 配置了公钥但签名不匹配时应抛出错误
    func testDownloadPluginSignatureVerificationFailure() async throws {
        // 生成两个不同的密钥对
        let keyA = Curve25519.Signing.PrivateKey()
        let keyB = Curve25519.Signing.PrivateKey()
        let pubKeyA = keyA.publicKey.rawRepresentation.base64EncodedString()

        // 下载内容
        let jsContent = "function execute(args) { return 'tampered'; }"
        let jsData = jsContent.data(using: .utf8)!

        // 用 keyB 签名（与配置的 keyA 公钥不匹配）
        let signature = try keyB.signature(for: jsData)
        let signatureBase64 = signature.base64EncodedString()

        let downloadURL = URL(string: "https://mock.example.com/sig-fail-\(UUID().uuidString.prefix(8)).js")!
        let session = makeMockSession(for: downloadURL, data: jsData)

        let manifest = PluginManifest(
            id: "sig-fail-test", name: "签名失败", version: "1.0.0", author: "测试",
            description: "签名校验失败", tools: [], permissions: [],
            entryPoint: "main.js",
            downloadURL: downloadURL,
            signature: signatureBase64
        )

        let service = PluginMarketplaceService(publicKeyBase64: pubKeyA, urlSession: session)
        do {
            try await service.downloadPlugin(manifest: manifest)
            XCTFail("签名不匹配应抛出错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("签名"), "错误信息应包含'签名'，实际：\(error.localizedDescription)")
        }

        // 清理可能写入的目录
        cleanupPluginDirectory(for: "sig-fail-test")
    }

    /// downloadPlugin HTTP 404 应抛出错误
    func testDownloadPluginHTTP404() async {
        let downloadURL = URL(string: "https://mock.example.com/404-\(UUID().uuidString.prefix(8)).js")!
        MockURLProtocol.mockData[downloadURL] = Data()
        MockURLProtocol.mockStatusCode[downloadURL] = 404

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let manifest = PluginManifest(
            id: "http-404-test", name: "404", version: "1.0.0", author: "测试",
            description: "404", tools: [], permissions: [],
            entryPoint: "main.js",
            downloadURL: downloadURL
        )

        let service = PluginMarketplaceService(urlSession: session)
        do {
            try await service.downloadPlugin(manifest: manifest)
            XCTFail("HTTP 404 应抛出错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"), "错误信息应包含 404")
        }

        MockURLProtocol.mockStatusCode.removeValue(forKey: downloadURL)
        MockURLProtocol.mockData.removeValue(forKey: downloadURL)
    }

    /// downloadPlugin HTTP 500 应抛出错误
    func testDownloadPluginHTTP500() async {
        let downloadURL = URL(string: "https://mock.example.com/500-\(UUID().uuidString.prefix(8)).js")!
        MockURLProtocol.mockData[downloadURL] = Data()
        MockURLProtocol.mockStatusCode[downloadURL] = 500

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let manifest = PluginManifest(
            id: "http-500-test", name: "500", version: "1.0.0", author: "测试",
            description: "500", tools: [], permissions: [],
            entryPoint: "main.js",
            downloadURL: downloadURL
        )

        let service = PluginMarketplaceService(urlSession: session)
        do {
            try await service.downloadPlugin(manifest: manifest)
            XCTFail("HTTP 500 应抛出错误")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("500"), "错误信息应包含 500")
        }

        MockURLProtocol.mockStatusCode.removeValue(forKey: downloadURL)
        MockURLProtocol.mockData.removeValue(forKey: downloadURL)
    }

    // MARK: - downloadPlugin 进度更新

    /// downloadPlugin 过程中 downloadProgress 应经历 0 → 0.5 → 1.0 并在完成后清除
    func testDownloadPluginProgressUpdates() async throws {
        let pluginID = "progress-test-\(UUID().uuidString.prefix(8))"
        let jsContent = "function execute(args) { return 'progress'; }"
        let jsData = jsContent.data(using: .utf8)!
        let downloadURL = URL(string: "https://mock.example.com/progress-\(pluginID).js")!

        // 配置延迟 mock 以便观察下载中状态
        MockURLProtocol.mockData[downloadURL] = jsData
        MockURLProtocol.mockDelay[downloadURL] = 0.3

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let manifest = PluginManifest(
            id: pluginID, name: "进度测试", version: "1.0.0", author: "测试",
            description: "进度", tools: [], permissions: [],
            entryPoint: "main.js",
            downloadURL: downloadURL
        )

        let service = PluginMarketplaceService(urlSession: session)

        // 在子任务中启动下载（@MainActor 继承）
        let downloadTask = Task { @MainActor in
            try await service.downloadPlugin(manifest: manifest)
        }

        // 等待下载任务启动并设置初始进度 0（在 urlSession.data 挂起期间观察）
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // 下载中：progress 应为 0（初始值，数据尚未到达）
        XCTAssertTrue(service.downloadingPluginIDs.contains(pluginID), "下载中应包含插件 ID")
        XCTAssertEqual(service.downloadProgress[pluginID], 0.0, "初始进度应为 0")

        // 等待下载完成（0.5 → 1.0 在 await 返回后同步设置，随后 defer 清除条目）
        try await downloadTask.value

        // 完成后：progress 条目应被 defer 清除
        XCTAssertFalse(service.downloadingPluginIDs.contains(pluginID), "完成后应移除插件 ID")
        XCTAssertNil(service.downloadProgress[pluginID], "完成后应清除进度条目")

        // 清理
        cleanupPluginDirectory(for: pluginID)
        MockURLProtocol.mockData.removeValue(forKey: downloadURL)
        MockURLProtocol.mockDelay.removeValue(forKey: downloadURL)
    }

    // MARK: - fetchPluginList 错误处理

    /// fetchPluginList 在返回 200 但非 JSON 格式时应抛出解码错误并设置 lastError
    func testFetchPluginListJSONDecodeFailure() async {
        let mockURL = URL(string: "https://mock.example.com/decode-fail.json")!
        let session = makeMockSession(for: mockURL, data: "this is not json".data(using: .utf8)!)

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        do {
            try await service.fetchPluginList()
            XCTFail("非 JSON 数据应抛出解码错误")
        } catch {
            XCTAssertNotNil(service.lastError, "lastError 应被设置")
        }
    }

    /// fetchPluginList 第一次失败后第二次成功时应清除 lastError
    func testFetchPluginListClearsLastErrorOnSuccess() async throws {
        let mockURL = URL(string: "https://mock.example.com/clear-last-error.json")!
        // 第一次：返回非 JSON 数据
        let session = makeMockSession(for: mockURL, data: "not json".data(using: .utf8)!)

        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)

        // 第一次调用：失败
        do {
            try await service.fetchPluginList()
            XCTFail("首次调用应抛出错误")
        } catch {
            XCTAssertNotNil(service.lastError, "失败后 lastError 应被设置")
        }

        // 更新 mock 数据为有效 JSON
        let validPlugins = [makeManifest(id: "recovery", name: "Recovery")]
        MockURLProtocol.mockData[mockURL] = try JSONEncoder().encode(validPlugins)

        // 第二次调用：成功
        try await service.fetchPluginList()
        XCTAssertNil(service.lastError, "成功后 lastError 应被置 nil")
        XCTAssertEqual(service.plugins.count, 1)
    }

    // MARK: - searchPlugins 去重

    /// searchPlugins 在 name 和 description 同时命中同一插件时应只返回 1 条
    func testSearchPluginsDeduplicatesMultiFieldHits() async throws {
        let service = try await makeServiceWithPlugins([
            makeManifest(id: "dedup-1", name: "Weather Tool", description: "weather forecast tool", author: "Alice"),
        ])

        // "weather" 同时命中 name 和 description，但应只返回 1 条
        let results = service.searchPlugins(query: "weather")
        XCTAssertEqual(results.count, 1, "多字段命中同一插件时应去重，返回 1 条而非 2 条")
        XCTAssertEqual(results.first?.id, "dedup-1")
    }

    // MARK: - 辅助

    /// 清理指定插件 ID 的本地目录
    private func cleanupPluginDirectory(for pluginID: String) {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let pluginDir = appSupport.appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(pluginID, isDirectory: true)
        try? fm.removeItem(at: pluginDir)
    }

    /// 构造测试用 manifest
    private func makeManifest(id: String, name: String, version: String = "1.0.0",
                              description: String = "", author: String = "测试") -> PluginManifest {
        PluginManifest(
            id: id, name: name, version: version, author: author,
            description: description, tools: [], permissions: [],
            entryPoint: "main.js"
        )
    }

    /// 构造一个已预设 plugins 的 service（通过 mock fetchPluginList 加载）
    private func makeServiceWithPlugins(_ plugins: [PluginManifest]) async throws -> PluginMarketplaceService {
        let jsonData = try JSONEncoder().encode(plugins)
        let mockURL = URL(string: "https://mock.example.com/search-registry.json")!
        let session = makeMockSession(for: mockURL, data: jsonData)
        let service = PluginMarketplaceService(registryURL: mockURL, urlSession: session)
        try await service.fetchPluginList()
        return service
    }

    /// 构造使用 MockURLProtocol 的 URLSession
    private func makeMockSession(for url: URL, data: Data, error: Error? = nil) -> URLSession {
        MockURLProtocol.mockData[url] = data
        if let error = error {
            MockURLProtocol.mockError[url] = error
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - MockURLProtocol

/// 用于 mock 网络请求的 URLProtocol 实现。
final class MockURLProtocol: URLProtocol {
    /// mock 响应数据，key 为请求 URL
    static var mockData: [URL: Data] = [:]
    /// mock 错误，key 为请求 URL
    static var mockError: [URL: Error] = [:]
    /// mock HTTP 状态码，key 为请求 URL（默认 200）
    static var mockStatusCode: [URL: Int] = [:]
    /// mock 响应延迟（秒），key 为请求 URL（默认 0，同步响应）
    static var mockDelay: [URL: TimeInterval] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!

        let sendResponse: () -> Void = { [weak self] in
            guard let self = self else { return }
            if let error = Self.mockError[url] {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else if let data = Self.mockData[url] {
                let statusCode = Self.mockStatusCode[url] ?? 200
                let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if let delay = Self.mockDelay[url], delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: sendResponse)
        } else {
            sendResponse()
        }
    }

    override func stopLoading() {}
}
