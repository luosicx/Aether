import XCTest
@testable import Aether

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
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下 CLLocationManager 定位耗时过长")
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

    // MARK: - 不同天气条件映射

    /// 天气码 0 应映射为「晴天」
    func testWeatherCode0MapsToSunny() async throws {
        try await assertWeatherCode(0, mapsTo: "晴天")
    }

    /// 天气码 2 应映射为「多云」
    func testWeatherCode2MapsToCloudy() async throws {
        try await assertWeatherCode(2, mapsTo: "多云")
    }

    /// 天气码 45 应映射为「雾」
    func testWeatherCode45MapsToFog() async throws {
        try await assertWeatherCode(45, mapsTo: "雾")
    }

    /// 天气码 51 应映射为「毛毛雨」
    func testWeatherCode51MapsToDrizzle() async throws {
        try await assertWeatherCode(51, mapsTo: "毛毛雨")
    }

    /// 天气码 61 应映射为「雨」
    func testWeatherCode61MapsToRain() async throws {
        try await assertWeatherCode(61, mapsTo: "雨")
    }

    /// 天气码 71 应映射为「雪」
    func testWeatherCode71MapsToSnow() async throws {
        try await assertWeatherCode(71, mapsTo: "雪")
    }

    /// 天气码 80 应映射为「阵雨」
    func testWeatherCode80MapsToShowers() async throws {
        try await assertWeatherCode(80, mapsTo: "阵雨")
    }

    /// 天气码 95 应映射为「雷暴」
    func testWeatherCode95MapsToThunderstorm() async throws {
        try await assertWeatherCode(95, mapsTo: "雷暴")
    }

    /// 天气码 999（未知码）应映射为「未知」
    func testWeatherCodeUnknownMapsToUnknown() async throws {
        try await assertWeatherCode(999, mapsTo: "未知")
    }

    /// 辅助：注入指定 weather_code 的 mock 响应，验证输出含期望的中文天气描述
    private func assertWeatherCode(_ code: Int, mapsTo expectedDescription: String) async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"测试城市","latitude":30.0,"longitude":120.0}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":20,"relative_humidity_2m":50,"weather_code":\(code),"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "测试城市"])
        XCTAssertTrue(result.contains(expectedDescription),
                      "weather_code=\(code) 应映射为「\(expectedDescription)」，实际：\(result)")
    }

    // MARK: - 格式化输出验证

    /// execute 输出应包含城市/温度/天气/湿度/风速字段
    func testExecuteOutputContainsAllFields() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"北京","latitude":39.9042,"longitude":116.4074}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":15.5,"relative_humidity_2m":45,"weather_code":1,"wind_speed_10m":3.5}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "北京"])
        XCTAssertTrue(result.contains("城市：北京"), "输出应含城市字段，实际：\(result)")
        XCTAssertTrue(result.contains("温度："), "输出应含温度字段")
        XCTAssertTrue(result.contains("天气："), "输出应含天气字段")
        XCTAssertTrue(result.contains("湿度："), "输出应含湿度字段")
        XCTAssertTrue(result.contains("风速："), "输出应含风速字段")
    }

    /// execute 温度/湿度/风速应使用 %g 格式化去掉浮点尾零
    func testExecuteFormatUsesTrimmedNumbers() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"格式化测试","latitude":0.0,"longitude":0.0}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                // 整数值 25 应显示为 25 而非 25.0
                let json = """
                {"current":{"temperature_2m":25,"relative_humidity_2m":60,"weather_code":0,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "格式化测试"])
        // %g 格式：25.0 → "25"
        XCTAssertTrue(result.contains("温度：25°C"), "整数值不应有 .0 后缀，实际：\(result)")
        XCTAssertTrue(result.contains("湿度：60%"), "湿度整数不应有 .0 后缀")
        XCTAssertTrue(result.contains("风速：10 km/h"), "风速整数不应有 .0 后缀")
    }

    // MARK: - HTTP 错误码处理

    /// Geocoding 返回 4xx 应返回天气查询失败提示
    func testGeocodingHTTPErrorReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        let result = try await tool.execute(arguments: ["city": "任何城市"])
        XCTAssertTrue(result.contains("天气查询失败"), "Geocoding HTTP 错误应返回天气查询失败，实际：\(result)")
    }

    /// Geocoding 返回 5xx 应返回天气查询失败提示
    func testGeocodingServerErrorReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        let result = try await tool.execute(arguments: ["city": "任何城市"])
        XCTAssertTrue(result.contains("天气查询失败"), "Geocoding 5xx 应返回天气查询失败，实际：\(result)")
    }

    /// Forecast 返回 4xx 应返回天气查询失败提示
    func testForecastHTTPErrorReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                // Forecast 返回 503
                let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "Forecast HTTP 错误应返回天气查询失败，实际：\(result)")
    }

    // MARK: - API 响应解析异常

    /// Geocoding 返回无 results 字段的 JSON 应返回未找到城市
    func testGeocodingNoResultsFieldReturnsNotFound() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = "{\"error\":\"invalid\"}"
            return (json.data(using: .utf8)!, response)
        }

        let result = try await tool.execute(arguments: ["city": "任何城市"])
        XCTAssertTrue(result.contains("未找到城市"), "无 results 字段应返回未找到城市，实际：\(result)")
    }

    /// Geocoding 返回 results 为空数组应返回未找到城市
    func testGeocodingEmptyResultsReturnsNotFound() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = "{\"results\":[]}"
            return (json.data(using: .utf8)!, response)
        }

        let result = try await tool.execute(arguments: ["city": "任何城市"])
        XCTAssertTrue(result.contains("未找到城市"), "空 results 数组应返回未找到城市，实际：\(result)")
    }

    /// Geocoding 返回 results 缺少 latitude 字段应返回未找到城市
    func testGeocodingMissingLatitudeReturnsNotFound() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = """
            {"results":[{"name":"测试","longitude":120.0}]}
            """
            return (json.data(using: .utf8)!, response)
        }

        let result = try await tool.execute(arguments: ["city": "测试"])
        XCTAssertTrue(result.contains("未找到城市"), "缺少 latitude 应返回未找到城市，实际：\(result)")
    }

    /// Forecast 返回非 JSON 数据应返回天气查询失败
    func testForecastInvalidJSONReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                return ("not json".data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "非 JSON 应返回天气查询失败，实际：\(result)")
    }

    /// Forecast 返回缺少 current 字段应返回天气查询失败
    func testForecastMissingCurrentReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let urlString = url.absoluteString
            if urlString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = "{\"error\":\"no data\"}"
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "缺少 current 字段应返回天气查询失败，实际：\(result)")
    }

    /// Forecast 返回缺少 weather_code 字段应返回天气查询失败
    func testForecastMissingWeatherCodeReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

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
                {"current":{"temperature_2m":25,"relative_humidity_2m":60,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "缺少 weather_code 应返回天气查询失败，实际：\(result)")
    }

    // MARK: - 坐标解析边界

    /// execute 空字符串城市名应走定位流程或返回定位相关提示（不查 geocoding）
    func testExecuteEmptyStringCityDoesNotGeocode() async throws {
        // 空字符串 city 会走 LocationTool → CLLocationManager.requestWhenInUseAuthorization()
        // CI 环境下系统权限对话框无人交互会挂起
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位权限请求对话框无人交互会挂起")
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        var geocodingCalled = false
        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                geocodingCalled = true
            }
            let json = "{\"results\":null}"
            return (json.data(using: .utf8)!, response)
        }

        // 空字符串 city 应被 trim 为空，走定位流程而非 geocoding
        _ = try await tool.execute(arguments: ["city": "   "])
        XCTAssertFalse(geocodingCalled, "空字符串 city 不应调用 geocoding API")
    }

    /// execute city 含前后空格应被 trim 后查询
    func testExecuteCityWithWhitespaceTrimmed() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":25,"relative_humidity_2m":60,"weather_code":0,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "  上海  "])
        XCTAssertTrue(result.contains("城市：上海"), "带空格的城市名应被 trim，实际：\(result)")
    }

    /// execute city 参数非 String 类型应走定位流程
    func testExecuteNonStringCityFallsBackToLocation() async throws {
        // 非 String city 会走 LocationTool → CLLocationManager.requestWhenInUseAuthorization()
        // CI 环境下系统权限对话框无人交互会挂起
        try XCTSkipIf(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil || ProcessInfo.processInfo.environment["CI"] != nil,
                      "跳过：模拟器/CI 环境下定位权限请求对话框无人交互会挂起")
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        var geocodingCalled = false
        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                geocodingCalled = true
            }
            return (Data(), response)
        }

        // 传入 Int 类型 city，应被忽略走定位流程
        _ = try await tool.execute(arguments: ["city": 123])
        XCTAssertFalse(geocodingCalled, "非 String city 应走定位流程而非 geocoding")
    }

    // MARK: - Forecast 缺少字段

    /// Forecast 返回缺少 temperature_2m 字段应返回天气查询失败
    func testForecastMissingTemperatureReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                // 缺少 temperature_2m
                let json = """
                {"current":{"relative_humidity_2m":60,"weather_code":0,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "缺少 temperature 应返回天气查询失败，实际：\(result)")
    }

    /// Forecast 返回缺少 relative_humidity_2m 字段应返回天气查询失败
    func testForecastMissingHumidityReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                // 缺少 relative_humidity_2m
                let json = """
                {"current":{"temperature_2m":25,"weather_code":0,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "缺少 humidity 应返回天气查询失败，实际：\(result)")
    }

    /// Forecast 返回缺少 wind_speed_10m 字段应返回天气查询失败
    func testForecastMissingWindSpeedReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                // 缺少 wind_speed_10m
                let json = """
                {"current":{"temperature_2m":25,"relative_humidity_2m":60,"weather_code":0}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("天气查询失败"), "缺少 wind_speed 应返回天气查询失败，实际：\(result)")
    }

    // MARK: - Geocoding 缺少字段

    /// Geocoding 返回 results 缺少 name 字段应返回未找到城市
    func testGeocodingMissingNameReturnsNotFound() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // 缺少 name
            let json = """
            {"results":[{"latitude":31.23,"longitude":121.47}]}
            """
            return (json.data(using: .utf8)!, response)
        }

        let result = try await tool.execute(arguments: ["city": "测试"])
        XCTAssertTrue(result.contains("未找到城市"), "缺少 name 应返回未找到城市，实际：\(result)")
    }

    /// Geocoding 返回 results 缺少 longitude 字段应返回未找到城市
    func testGeocodingMissingLongitudeReturnsNotFound() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // 缺少 longitude
            let json = """
            {"results":[{"name":"上海","latitude":31.2304}]}
            """
            return (json.data(using: .utf8)!, response)
        }

        let result = try await tool.execute(arguments: ["city": "上海"])
        XCTAssertTrue(result.contains("未找到城市"), "缺少 longitude 应返回未找到城市，实际：\(result)")
    }

    // MARK: - 天气码 85/86（阵雪）

    /// 天气码 85 应映射为「阵雪」
    func testWeatherCode85MapsToSnowShowers() async throws {
        try await assertWeatherCode(85, mapsTo: "阵雪")
    }

    /// 天气码 86 应映射为「阵雪」
    func testWeatherCode86MapsToSnowShowers() async throws {
        try await assertWeatherCode(86, mapsTo: "阵雪")
    }

    // MARK: - 天气码边界值

    /// 天气码 1 应映射为「多云」（1...3 范围边界）
    func testWeatherCode1MapsToCloudy() async throws {
        try await assertWeatherCode(1, mapsTo: "多云")
    }

    /// 天气码 3 应映射为「多云」（1...3 范围边界）
    func testWeatherCode3MapsToCloudy() async throws {
        try await assertWeatherCode(3, mapsTo: "多云")
    }

    /// 天气码 48 应映射为「雾」（45...48 范围边界）
    func testWeatherCode48MapsToFog() async throws {
        try await assertWeatherCode(48, mapsTo: "雾")
    }

    /// 天气码 57 应映射为「毛毛雨」（51...57 范围边界）
    func testWeatherCode57MapsToDrizzle() async throws {
        try await assertWeatherCode(57, mapsTo: "毛毛雨")
    }

    /// 天气码 67 应映射为「雨」（61...67 范围边界）
    func testWeatherCode67MapsToRain() async throws {
        try await assertWeatherCode(67, mapsTo: "雨")
    }

    /// 天气码 77 应映射为「雪」（71...77 范围边界）
    func testWeatherCode77MapsToSnow() async throws {
        try await assertWeatherCode(77, mapsTo: "雪")
    }

    /// 天气码 82 应映射为「阵雨」（80...82 范围边界）
    func testWeatherCode82MapsToShowers() async throws {
        try await assertWeatherCode(82, mapsTo: "阵雨")
    }

    /// 天气码 99 应映射为「雷暴」（95...99 范围边界）
    func testWeatherCode99MapsToThunderstorm() async throws {
        try await assertWeatherCode(99, mapsTo: "雷暴")
    }

    // MARK: - definition 结构验证

    /// definition 的 description 不应为空
    func testDefinitionDescriptionIsNotEmpty() {
        let def = tool.definition
        XCTAssertFalse(def.description.isEmpty, "definition.description 不应为空")
        XCTAssertTrue(def.description.contains("天气"), "description 应含「天气」关键词")
    }

    /// definition 的 city 字段 description 不应为空
    func testDefinitionCityDescriptionIsNotEmpty() {
        let def = tool.definition
        let properties = def.parameters["properties"] as? [String: Any]
        let cityProp = properties?["city"] as? [String: Any]
        let cityDesc = cityProp?["description"] as? String
        XCTAssertFalse(cityDesc?.isEmpty ?? true, "city 字段 description 不应为空")
    }

    // MARK: - URL 构造验证

    /// execute 合法城市名时 geocoding URL 应包含编码后的城市名
    func testGeocodingURLEncodesCityName() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                capturedURL = url
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":25,"relative_humidity_2m":60,"weather_code":0,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        _ = try await tool.execute(arguments: ["city": "上海"])

        XCTAssertNotNil(capturedURL, "应捕获 geocoding URL")
        XCTAssertTrue(capturedURL?.absoluteString.contains("name=%E4%B8%8A%E6%B5%B7") ?? false,
                       "geocoding URL 应包含 URL 编码后的城市名，实际：\(capturedURL?.absoluteString ?? "nil")")
        XCTAssertTrue(capturedURL?.absoluteString.contains("count=1") ?? false,
                       "geocoding URL 应含 count=1 参数")
        XCTAssertTrue(capturedURL?.absoluteString.contains("language=zh") ?? false,
                       "geocoding URL 应含 language=zh 参数")
    }

    /// execute 合法城市名时 forecast URL 应包含经纬度参数
    func testForecastURLContainsCoordinates() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        var forecastURL: URL?
        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"上海","latitude":31.2304,"longitude":121.4737}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                forecastURL = url
                let json = """
                {"current":{"temperature_2m":25,"relative_humidity_2m":60,"weather_code":0,"wind_speed_10m":10}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        _ = try await tool.execute(arguments: ["city": "上海"])

        XCTAssertNotNil(forecastURL, "应捕获 forecast URL")
        let urlString = forecastURL?.absoluteString ?? ""
        XCTAssertTrue(urlString.contains("latitude=31.2304"), "forecast URL 应含 latitude 参数，实际：\(urlString)")
        XCTAssertTrue(urlString.contains("longitude=121.4737"), "forecast URL 应含 longitude 参数，实际：\(urlString)")
        XCTAssertTrue(urlString.contains("current=temperature_2m"), "forecast URL 应含 current 参数")
    }

    // MARK: - 负经纬度城市

    /// execute 西半球城市（负经纬度）应正确构造 forecast URL 并返回天气
    func testExecuteWithNegativeCoordinates() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                // 纽约：负经度
                let json = """
                {"results":[{"name":"New York","latitude":40.7128,"longitude":-74.0060}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":15,"relative_humidity_2m":55,"weather_code":1,"wind_speed_10m":8}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "New York"])
        XCTAssertTrue(result.contains("城市：New York"), "应返回城市名，实际：\(result)")
        XCTAssertTrue(result.contains("温度："), "应含温度字段")
        XCTAssertTrue(result.contains("天气：多云"), "weather_code=1 应映射为多云，实际：\(result)")
    }

    // MARK: - 完整输出格式

    /// execute 输出温度为浮点数时应正确格式化（25.5 → "25.5"）
    func testExecuteFormatFloatTemperature() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"测试","latitude":30.0,"longitude":120.0}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":25.5,"relative_humidity_2m":65.5,"weather_code":0,"wind_speed_10m":12.3}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "测试"])
        XCTAssertTrue(result.contains("温度：25.5°C"), "浮点温度应保留一位小数，实际：\(result)")
        XCTAssertTrue(result.contains("湿度：65.5%"), "浮点湿度应保留一位小数")
        XCTAssertTrue(result.contains("风速：12.3 km/h"), "浮点风速应保留一位小数")
    }

    /// execute 输出零值应正确格式化（0 → "0"）
    func testExecuteFormatZeroValues() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                let json = """
                {"results":[{"name":"零度城市","latitude":0.0,"longitude":0.0}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":0,"relative_humidity_2m":0,"weather_code":0,"wind_speed_10m":0}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "零度城市"])
        XCTAssertTrue(result.contains("温度：0°C"), "零温度应显示为 0，实际：\(result)")
        XCTAssertTrue(result.contains("湿度：0%"), "零湿度应显示为 0")
        XCTAssertTrue(result.contains("风速：0 km/h"), "零风速应显示为 0")
    }

    // MARK: - Geocoding 返回多个结果

    /// Geocoding 返回多个结果时应使用第一个结果
    func testGeocodingMultipleResultsUsesFirst() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if url.absoluteString.contains("geocoding-api") {
                // 返回多个结果，应使用第一个
                let json = """
                {"results":[{"name":"第一个城市","latitude":10.0,"longitude":20.0},{"name":"第二个城市","latitude":30.0,"longitude":40.0}]}
                """
                return (json.data(using: .utf8)!, response)
            } else {
                let json = """
                {"current":{"temperature_2m":22,"relative_humidity_2m":50,"weather_code":0,"wind_speed_10m":5}}
                """
                return (json.data(using: .utf8)!, response)
            }
        }

        let result = try await tool.execute(arguments: ["city": "测试"])
        XCTAssertTrue(result.contains("城市：第一个城市"), "应使用第一个结果的城市名，实际：\(result)")
    }

    // MARK: - Geocoding 非 200 状态码

    /// Geocoding 返回 301 重定向应返回天气查询失败
    func testGeocodingRedirectReturnsFailure() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 301, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }

        let result = try await tool.execute(arguments: ["city": "任何城市"])
        XCTAssertTrue(result.contains("天气查询失败"), "301 应返回天气查询失败，实际：\(result)")
    }

    // MARK: - Forecast 返回 results 为非数组类型

    /// Geocoding 返回 results 为非数组类型（字符串）应返回未找到城市
    func testGeocodingResultsNonArrayReturnsNotFound() async throws {
        URLProtocol.registerClass(MockURLProtocol.self)
        defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

        MockURLProtocol.requestHandler = { url in
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            // results 为字符串而非数组
            let json = """
            {"results":"invalid"}
            """
            return (json.data(using: .utf8)!, response)
        }

        let result = try await tool.execute(arguments: ["city": "测试"])
        XCTAssertTrue(result.contains("未找到城市"), "results 为非数组应返回未找到城市，实际：\(result)")
    }
}
