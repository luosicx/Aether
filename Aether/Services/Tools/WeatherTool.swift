/// 天气查询工具（跨平台：iOS + macOS）
///
/// 使用 Open-Meteo 免费 API（无需 API Key）查询天气信息。
/// 支持按城市名或当前定位查询：城市名经 Geocoding API 转坐标，
/// 不传城市则调用 LocationTool 获取当前位置，再调用 Forecast API 取当前天气。
/// 调用方式：execute(arguments: ["city": "..."])，city 可选，不传则用当前定位。
import Foundation

/// 天气查询工具，使用 Open-Meteo 免费 API（无需 API Key）。
/// 支持按城市名或当前定位查询：城市名经 Geocoding API 转坐标，
/// 不传城市则调用 LocationTool 获取当前位置，再调用 Forecast API 取当前天气。
final class WeatherTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name/description/parameters）
    var definition: ToolDefinition {
        ToolDefinition(
            name: "get_weather",
            description: "查询天气信息，可按城市名或当前定位查询，使用 Open-Meteo 免费 API（无需 API Key）",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string", "description": "城市名称，如上海、北京；不传则用当前定位"]
                ],
                "required": []
            ]
        )
    }

    /// 执行天气查询。流程：1) 城市名或定位获取坐标；
    /// 2) 调用 Forecast API 取当前天气；3) weather_code 映射为中文描述；
    /// 4) 拼装格式化字符串返回。网络/解析错误以字符串返回而非抛错。
    func execute(arguments: [String: Any]) async throws -> String {
        let city = arguments["city"] as? String
        let trimmedCity = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let cityName: String
        let latitude: Double
        let longitude: Double

        if !trimmedCity.isEmpty {
            // 按城市名查询坐标
            do {
                let (name, lat, lon) = try await geocode(city: trimmedCity)
                cityName = name
                latitude = lat
                longitude = lon
            } catch let error as GeocodeError {
                switch error {
                case .notFound:
                    return "未找到城市：\(trimmedCity)"
                case .network(let message):
                    return "天气查询失败：\(message)"
                }
            }
        } else {
            // 无城市名，用当前定位
            let locationResult: String
            do {
                locationResult = try await LocationTool().execute(arguments: [:])
            } catch {
                return "天气查询失败：定位失败 - \(error.localizedDescription)"
            }
            // LocationTool 失败时返回的字符串不含可解析坐标，直接作为错误透传
            guard let (lat, lon) = parseCoordinates(from: locationResult) else {
                return locationResult
            }
            latitude = lat
            longitude = lon
            cityName = parseCityName(from: locationResult) ?? "当前位置"
        }

        // 查询天气
        do {
            let weather = try await fetchWeather(latitude: latitude, longitude: longitude)
            return formatWeather(cityName: cityName, weather: weather)
        } catch {
            return "天气查询失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 天气码映射

    /// WMO weather_code 到中文描述映射
    private func weatherDescription(code: Int) -> String {
        switch code {
        case 0: return "晴天"
        case 1...3: return "多云"
        case 45...48: return "雾"
        case 51...57: return "毛毛雨"
        case 61...67: return "雨"
        case 71...77: return "雪"
        case 80...82: return "阵雨"
        case 85...86: return "阵雪"
        case 95...99: return "雷暴"
        default: return "未知"
        }
    }

    // MARK: - 网络

    /// Geocoding 错误
    private enum GeocodeError: Error {
        case notFound
        case network(String)
    }

    /// 调用 Open-Meteo Geocoding API，返回首个结果 (name, latitude, longitude)
    private func geocode(city: String) async throws -> (String, Double, Double) {
        guard let encoded = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=zh") else {
            throw GeocodeError.network("URL 构造失败")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GeocodeError.network("Geocoding HTTP 错误")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let name = first["name"] as? String,
                  let latNum = first["latitude"] as? NSNumber,
                  let lonNum = first["longitude"] as? NSNumber else {
                throw GeocodeError.notFound
            }
            return (name, latNum.doubleValue, lonNum.doubleValue)
        } catch let error as GeocodeError {
            throw error
        } catch {
            throw GeocodeError.network(error.localizedDescription)
        }
    }

    /// 天气数据
    private struct WeatherData {
        let temperature: Double
        let humidity: Double
        let weatherCode: Int
        let windSpeed: Double
    }

    /// 调用 Open-Meteo Forecast API 取当前天气
    private func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherData {
        let urlStr = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "WeatherTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "URL 构造失败"])
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "WeatherTool", code: 2, userInfo: [NSLocalizedDescriptionKey: "Forecast HTTP 错误"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temperature = (current["temperature_2m"] as? NSNumber)?.doubleValue,
              let humidity = (current["relative_humidity_2m"] as? NSNumber)?.doubleValue,
              let weatherCode = (current["weather_code"] as? NSNumber)?.intValue,
              let windSpeed = (current["wind_speed_10m"] as? NSNumber)?.doubleValue else {
            throw NSError(domain: "WeatherTool", code: 3, userInfo: [NSLocalizedDescriptionKey: "天气数据解析失败"])
        }
        return WeatherData(temperature: temperature, humidity: humidity, weatherCode: weatherCode, windSpeed: windSpeed)
    }

    // MARK: - 字符串解析与格式化

    /// 从 LocationTool 结果字符串解析经纬度。
    /// 格式："当前位置：xxx，经纬度 31.2304, 121.4737" 或 "当前位置：经纬度 31.2304, 121.4737（地址解析失败）"
    private func parseCoordinates(from result: String) -> (Double, Double)? {
        let pattern = "经纬度\\s*(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(result.startIndex..., in: result)
        guard let match = regex.firstMatch(in: result, range: range),
              let latRange = Range(match.range(at: 1), in: result),
              let lonRange = Range(match.range(at: 2), in: result),
              let lat = Double(result[latRange]),
              let lon = Double(result[lonRange]) else {
            return nil
        }
        return (lat, lon)
    }

    /// 从 LocationTool 结果字符串提取城市/地址名（冒号后到 "经纬度" 之前的部分）。
    /// 无地址时返回 nil，调用方回退到 "当前位置"。
    private func parseCityName(from result: String) -> String? {
        guard let colonRange = result.range(of: "：") else { return nil }
        let afterColon = String(result[colonRange.upperBound...])
        guard let landmark = afterColon.range(of: "经纬度") else { return nil }
        let beforeLandmark = String(afterColon[..<landmark.lowerBound])
        let trimmed = beforeLandmark.trimmingCharacters(in: CharacterSet(charactersIn: "， ,"))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 拼装最终天气信息字符串，使用 %g 去掉浮点尾零（25.5 / 65 / 12.3）
    private func formatWeather(cityName: String, weather: WeatherData) -> String {
        let temp = String(format: "%g", weather.temperature)
        let humidity = String(format: "%g", weather.humidity)
        let wind = String(format: "%g", weather.windSpeed)
        return [
            "城市：\(cityName)",
            "温度：\(temp)°C",
            "天气：\(weatherDescription(code: weather.weatherCode))",
            "湿度：\(humidity)%",
            "风速：\(wind) km/h"
        ].joined(separator: "\n")
    }
}
