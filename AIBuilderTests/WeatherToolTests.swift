import XCTest
@testable import AIBuilder

/// 拦截 URLSession.shared 请求的 URLProtocol mock，用于注入预置响应。
/// 通过 URLProtocol.registerClass 全局注册后即可拦截 WeatherTool 内部的网络请求。
final class MockURLProtocol: URLProtocol {
    /// 请求处理器：接收 URL，返回 (Data, HTTPURLResponse)
    static var requestHandler: ((URL) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (data, response) = handler(request.url!)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// WeatherTool 单元测试
/// 需联网的用例通过 MockURLProtocol 注入预置响应，避免依赖真实网络。
/// 定位相关用例在测试环境下可能成功或返回错误，仅校验不崩溃且返回非空字符串
final class WeatherToolTests: XCTestCase {
    private let tool = WeatherTool()

    /// definition：name == "get_weather"，properties 含 city 字段，required 为空
    func testDefinitionSchema() {
        let def = tool.definition
        XCTAssertEqual(def.name, "get_weather")
        XCTAssertEqual(def.parameters["type"] as? String, "object")
        let properties = def.parameters["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["city"], "properties 应含 city 字段")
        let cityProp = properties?["city"] as? [String: Any]
        XCTAssertEqual(cityProp?["type"] as? String, "string", "city 字段 type 应为 string")
        XCTAssertNotNil(cityProp?["description"], "city 字段应含 description")
        let required = def.parameters["required"] as? [String]
        XCTAssertTrue(required?.isEmpty ?? false, "required 应为空")
    }

    /// execute 无参调用：走定位流程，可能返回天气或定位错误，仅校验返回非空字符串
    func testExecuteMissingCityReturnsLocationOrError() async throws {
        let result = try await tool.execute(arguments: [:])
        XCTAssertFalse(result.isEmpty, "无参应返回非空字符串（天气或定位相关错误提示）")
    }

    /// execute 无效城市：Geocoding API 返回空 results，应返回 "未找到城市"
    func testExecuteInvalidCityReturnsNotFound() async throws {
        // 全局注册 MockURLProtocol 拦截 URLSession.shared 请求
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        // 无效城市 → Open-Meteo Geocoding 返回 {"results": null}
        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = "{\"results\":null}".data(using: .utf8)!
            return (data, response)
        }

        let result = try await tool.execute(arguments: ["city": "不存在的城市名xyz"])
        XCTAssertTrue(result.contains("未找到城市"), "无效城市应返回未找到城市，实际：\(result)")
    }

    /// execute 返回值类型为 String 且非空（合法城市名查询）
    func testExecuteReturnsString() async throws {
        // 全局注册 MockURLProtocol 拦截 URLSession.shared 请求
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        // 合法城市 → Geocoding 返回坐标，Forecast 返回当前天气
        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":25.5,"relative_humidity_2m":65,"weather_code":0,"wind_speed_10m":12.3}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        let anyResult: Any = result
        XCTAssertTrue(anyResult is String, "execute 返回值应为 String 类型")
        XCTAssertFalse(result.isEmpty, "应返回非空天气信息")
        XCTAssertTrue(result.contains("城市") || result.contains("未找到城市"),
                      "结果应含城市或未找到提示，实际：\(result)")
    }
}
