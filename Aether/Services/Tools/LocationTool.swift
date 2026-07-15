/// 地理位置获取工具（跨平台：iOS + macOS）
///
/// 通过 CLLocationManager 获取设备当前位置（10 秒超时），再用 CLGeocoder 反查地址，
/// 返回经纬度与可读地址。
/// 调用方式：execute(arguments: [:])，无入参。
/// 定位权限被拒或超时会以字符串形式返回提示而非抛异常。
import Foundation
import CoreLocation
import AetherFoundation

/// 定位相关错误
private enum LocationError: Error {
    /// 未授权
    case notAuthorized
    /// 定位超时
    case timeout
}

/// 获取设备地理位置与逆地理编码结果的工具。
/// 通过 CLLocationManager 获取当前位置（10 秒超时），再用 CLGeocoder 反查地址，
/// 跨平台支持 iOS + macOS。
final class LocationTool: ToolProtocol, @unchecked Sendable {
    /// 工具定义（name/description/parameters）。无入参。
    var definition: ToolDefinition {
        ToolDefinition(
            name: "get_location",
            description: "获取当前设备地理位置与逆地理编码结果",
            parameters: [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        )
    }

    /// 执行定位。流程：1) 请求定位权限并获取当前位置（10s 超时）；
    /// 2) 未授权返回提示；3) 成功后用 CLGeocoder 反查地址；
    /// 4) 拼装格式化字符串返回。用户可见错误以字符串返回而非抛错。
    @MainActor
    func execute(arguments: [String: Any]) async throws -> String {
        let fetcher = LocationFetcher()
        let location: CLLocation
        do {
            location = try await fetcher.requestLocation()
        } catch LocationError.notAuthorized {
            return "定位权限未授权，请在设置中开启定位权限"
        } catch LocationError.timeout {
            return "定位超时，请重试"
        } catch {
            return "定位失败：\(error.localizedDescription)"
        }

        // 逆地理编码
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await reverseGeocode(location)
        } catch {
            return "当前位置：经纬度 \(format(location.coordinate.latitude)), \(format(location.coordinate.longitude))（地址解析失败）"
        }

        if let placemark = placemarks.first, let address = formatAddress(from: placemark) {
            return "当前位置：\(address)，经纬度 \(format(location.coordinate.latitude)), \(format(location.coordinate.longitude))"
        } else {
            return "当前位置：经纬度 \(format(location.coordinate.latitude)), \(format(location.coordinate.longitude))（地址解析失败）"
        }
    }

    /// 用 CLGeocoder 反查地址，包装为 async
    private func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        try await withCheckedThrowingContinuation { cont in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: placemarks ?? [])
                }
            }
        }
    }

    /// 经纬度格式化为 4 位小数
    private func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    /// 拼装可读地址：省/市/区，去重并去 nil；全空返回 nil
    private func formatAddress(from placemark: CLPlacemark) -> String? {
        var parts: [String] = []
        if let area = placemark.administrativeArea, !area.isEmpty {
            parts.append(area)
        }
        if let locality = placemark.locality, !locality.isEmpty, !parts.contains(locality) {
            parts.append(locality)
        }
        if let subLocality = placemark.subLocality, !subLocality.isEmpty, !parts.contains(subLocality) {
            parts.append(subLocality)
        }
        if parts.isEmpty {
            if let name = placemark.name, !name.isEmpty {
                return name
            }
            return nil
        }
        return parts.joined()
    }
}

// MARK: - LocationFetcher

/// CLLocationManager 的 async 封装。通过 CheckedContinuation 把基于 delegate 的定位
/// 转为 async 调用，并附带 10 秒超时。所有对 continuation 与 manager 的访问均在主线程进行，
/// 与 CLLocationManagerDelegate 回调线程一致，避免数据竞争。
private final class LocationFetcher: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 请求定位权限并获取当前位置。10 秒未返回则抛 timeout；权限被拒抛 notAuthorized。
    func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            // 在主线程设置 continuation 并发起请求，确保与 delegate 回调同线程
            DispatchQueue.main.async {
                self.continuation = cont
                self.manager.requestWhenInUseAuthorization()
                self.manager.requestLocation()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.resume(throwing: LocationError.timeout)
            }
        }
    }

    /// 安全地 resume returning（防重复 resume 导致崩溃）
    /// 统一在 DispatchQueue.main 上执行，与 continuation 的设置线程一致，避免数据竞争
    private func resume(returning location: CLLocation) {
        DispatchQueue.main.async {
            guard let continuation = self.continuation else { return }
            self.continuation = nil
            continuation.resume(returning: location)
        }
    }

    /// 安全地 resume throwing（防重复 resume 导致崩溃）
    /// 统一在 DispatchQueue.main 上执行，与 continuation 的设置线程一致，避免数据竞争
    private func resume(throwing error: Error) {
        DispatchQueue.main.async {
            guard let continuation = self.continuation else { return }
            self.continuation = nil
            continuation.resume(throwing: error)
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            resume(returning: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 权限被拒时 CLError.code == .denied
        if let clError = error as? CLError, clError.code == .denied {
            resume(throwing: LocationError.notAuthorized)
        } else {
            resume(throwing: error)
        }
    }
}
