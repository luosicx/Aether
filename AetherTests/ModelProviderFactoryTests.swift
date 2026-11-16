import XCTest
import AetherFoundation
import AetherServices
import AetherDesign
import AetherUI
@testable import Aether

/// Day 13/15: ModelProviderFactory 单元测试
/// 验证工厂方法根据 ModelProvider 与 BFFConfig 返回正确类型的 LLMProvider 实例。
/// 仅校验返回类型，不发起任何网络请求。
final class ModelProviderFactoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 生产由 AetherApp.sharedInit 注入；单元测试显式注入 App 层真实实现
        ModelProviderFactory.onDeviceProviderFactory = { OfflineLLMProvider() }
    }

    override func tearDown() {
        ModelProviderFactory.onDeviceProviderFactory = nil
        super.tearDown()
    }

    // MARK: - make(_:) 直连分支

    func testMakeDeepseekReturnsDeepSeekClient() {
        let provider = ModelProviderFactory.make(.deepseek)
        XCTAssertTrue(provider is DeepSeekClient,
                      "make(.deepseek) 应返回 DeepSeekClient 实例")
    }

    func testMakeQwenReturnsQwenClient() {
        let provider = ModelProviderFactory.make(.qwen)
        XCTAssertTrue(provider is QwenClient,
                      "make(.qwen) 应返回 QwenClient 实例")
    }

    func testMakeOnDeviceReturnsOfflineLLMProvider() {
        let provider = ModelProviderFactory.make(.onDevice)
        XCTAssertTrue(provider is OfflineLLMProvider,
                      "make(.onDevice) 应返回 OfflineLLMProvider 实例")
    }

    /// 回归测试：端侧工厂未注入时不得 fatalError（设置页可选端侧推理，断网也会自动切换）。
    /// 兜底 provider 应上报 llmErrorOccurred 并结束流。
    func testMakeOnDeviceWithoutFactoryFallsBackWithoutCrashing() async {
        ModelProviderFactory.onDeviceProviderFactory = nil
        let expectation = XCTNSNotificationExpectation(name: .llmErrorOccurred, object: nil)
        nonisolated(unsafe) var capturedError: LLMError?
        expectation.handler = { note in
            if let err = note.userInfo?["error"] as? LLMError {
                capturedError = err
                return true
            }
            return false
        }

        let provider = ModelProviderFactory.make(.onDevice)
        var collected = ""
        for await chunk in provider.chat(
            messages: [], config: ChatConfig.default, apiKey: ""
        ) {
            collected += chunk
        }
        XCTAssertEqual(collected, "", "兜底 provider 不应产出内容")

        await fulfillment(of: [expectation], timeout: 2.0)
        guard case .llmErrorOccurred(let msg) = capturedError else {
            XCTFail("期望 .llmErrorOccurred，实际：\(String(describing: capturedError))")
            return
        }
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - make(bffConfig:provider:) BFF 代理分支

    func testMakeWithBFFEnabledReturnsBFFProxyClient() {
        let bffConfig = BFFConfig(
            enabled: true,
            endpointURL: URL(string: "https://bff.example.com"),
            userToken: "test-token",
            chatRateLimitPerMin: 20,
            embedRateLimitPerMin: 10
        )
        let provider = ModelProviderFactory.make(bffConfig: bffConfig, provider: .deepseek)
        XCTAssertTrue(provider is BFFProxyClient,
                      "bffConfig.enabled == true 时应返回 BFFProxyClient 实例")
    }

    // MARK: - make(bffConfig:provider:) 直连分支（enabled == false，三种 provider 全覆盖）

    func testMakeWithBFFDisabledDeepseekReturnsDeepSeekClient() {
        let bffConfig = BFFConfig.default // enabled == false
        let provider = ModelProviderFactory.make(bffConfig: bffConfig, provider: .deepseek)
        XCTAssertTrue(provider is DeepSeekClient,
                      "enabled == false 时 make(.deepseek) 应返回 DeepSeekClient")
        XCTAssertFalse(provider is BFFProxyClient,
                       "enabled == false 时不应返回 BFFProxyClient")
    }

    func testMakeWithBFFDisabledQwenReturnsQwenClient() {
        let bffConfig = BFFConfig.default
        let provider = ModelProviderFactory.make(bffConfig: bffConfig, provider: .qwen)
        XCTAssertTrue(provider is QwenClient,
                      "enabled == false 时 make(.qwen) 应返回 QwenClient")
        XCTAssertFalse(provider is BFFProxyClient,
                       "enabled == false 时不应返回 BFFProxyClient")
    }

    func testMakeWithBFFDisabledOnDeviceReturnsOfflineLLMProvider() {
        let bffConfig = BFFConfig.default
        let provider = ModelProviderFactory.make(bffConfig: bffConfig, provider: .onDevice)
        XCTAssertTrue(provider is OfflineLLMProvider,
                      "enabled == false 时 make(.onDevice) 应返回 OfflineLLMProvider")
        XCTAssertFalse(provider is BFFProxyClient,
                       "enabled == false 时不应返回 BFFProxyClient")
    }

    // MARK: - 边界：enabled == false 但其他字段非默认，仍走直连分支

    func testMakeWithBFFDisabledButNonDefaultFieldsStillDirectConnect() {
        let bffConfig = BFFConfig(
            enabled: false,
            endpointURL: URL(string: "https://non-default.example.com"),
            userToken: "non-default-token",
            chatRateLimitPerMin: 99,
            embedRateLimitPerMin: 88
        )
        let provider = ModelProviderFactory.make(bffConfig: bffConfig, provider: .deepseek)
        XCTAssertTrue(provider is DeepSeekClient,
                      "enabled == false 即使其他字段非默认，仍应走直连返回 DeepSeekClient")
        XCTAssertFalse(provider is BFFProxyClient,
                       "enabled == false 时不应返回 BFFProxyClient")
    }

    // MARK: - make(bffConfig:provider:) 与 make(_:) 返回类型一致性（三种 provider 全覆盖）

    func testMakeWithBFFDisabledTypeConsistentWithMakeForAllProviders() {
        let bffConfig = BFFConfig.default
        for mp in ModelProvider.allCases {
            let direct = ModelProviderFactory.make(mp)
            let viaBFF = ModelProviderFactory.make(bffConfig: bffConfig, provider: mp)
            XCTAssertEqual(String(describing: type(of: direct)), String(describing: type(of: viaBFF)),
                           "enabled == false 时 make(bffConfig:provider:) 与 make(_:) 对 \(mp) 应返回相同类型")
            XCTAssertFalse(viaBFF is BFFProxyClient,
                          "enabled == false 时对 \(mp) 不应返回 BFFProxyClient")
        }
    }
}
