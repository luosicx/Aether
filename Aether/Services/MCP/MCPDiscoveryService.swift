import Foundation

// MARK: - DiscoveredService

/// 发现的 Bonjour 服务信息。
struct DiscoveredService: Sendable, Equatable {
    /// 服务名（Bonjour name）
    let name: String
    /// 主机名（如 192.168.1.100 或 server.local）
    let hostName: String
    /// 端口
    let port: Int
    /// TXT record 字典
    let txtRecord: [String: String]
}

// MARK: - MCPServiceBrowsing 协议

/// MCP 服务浏览协议，抽象 Bonjour/NetService 浏览能力，便于测试注入。
protocol MCPServiceBrowsing: AnyObject {
    /// 启动服务浏览
    /// - Parameters:
    ///   - type: Bonjour 服务类型（如 `_aether_mcp._tcp.`）
    ///   - handler: 发现服务时的回调（在主线程调用）
    func startDiscovery(type: String, handler: @escaping (DiscoveredService) -> Void)
    /// 停止服务浏览
    func stopDiscovery()
}

// MARK: - MCPDiscoveryService

/// MCP 动态发现服务，基于 Zeroconf（Bonjour/DNS-SD）扫描局域网内声明 `_aether_mcp._tcp` 的 Server。
///
/// 职责：
/// - 启动时扫描局域网，60s 周期增量扫描
/// - 发现的 Server 通过 `MCPClientManager.addDiscoveredCandidate` 注册为候选
/// - iOS 后台不可用时降级为前台扫描 + 配置文件兜底
///
/// 使用 @MainActor 隔离，与 MCPClientManager 一致。
@MainActor
final class MCPDiscoveryService {
    /// 关联的 MCPClientManager（用于注册发现的 Server）
    private let manager: MCPClientManager
    /// Browser 工厂（默认创建 BonjourServiceBrowser，测试可注入 Mock）
    private let browserFactory: () -> any MCPServiceBrowsing
    /// 扫描间隔（秒，缺省 60）
    private let scanIntervalSec: Int
    /// Bonjour 服务类型
    private let serviceType: String

    /// 当前 browser 实例
    private var browser: (any MCPServiceBrowsing)?
    /// 周期扫描 Timer
    private var scanTimer: Timer?
    /// 是否在前台活跃（iOS 后台时暂停扫描）
    private var isForegroundActive: Bool = true
    /// 是否正在扫描
    private(set) var isScanning: Bool = false

    /// 构造发现服务
    /// - Parameters:
    ///   - manager: MCPClientManager
    ///   - browserFactory: Browser 工厂（默认 BonjourServiceBrowser）
    ///   - scanIntervalSec: 扫描间隔（秒，缺省 60）
    ///   - serviceType: Bonjour 服务类型（缺省 `_aether_mcp._tcp.`）
    init(
        manager: MCPClientManager,
        browserFactory: @escaping () -> any MCPServiceBrowsing = { BonjourServiceBrowser() },
        scanIntervalSec: Int = 60,
        serviceType: String = "_aether_mcp._tcp."
    ) {
        self.manager = manager
        self.browserFactory = browserFactory
        self.scanIntervalSec = scanIntervalSec
        self.serviceType = serviceType
    }

    // MARK: - 扫描控制

    /// 启动扫描：立即执行一次搜索 + 周期 Timer
    func startScanning() {
        guard !isScanning else { return }
        guard isForegroundActive else {
            // iOS 后台不启动扫描，等待前台激活后再启动
            return
        }
        isScanning = true
        startBrowserSearch()
        startPeriodicTimer()
    }

    /// 停止扫描：取消 Timer + 停止 browser
    func stopScanning() {
        isScanning = false
        scanTimer?.invalidate()
        scanTimer = nil
        browser?.stopDiscovery()
        browser = nil
    }

    /// 设置前台活跃状态（iOS 后台切换时调用）
    /// - Parameter active: true 表示回到前台，false 表示进入后台
    func setForegroundActive(_ active: Bool) {
        isForegroundActive = active
        if active {
            // 回到前台：恢复扫描
            if !isScanning {
                startScanning()
            }
        } else {
            // 进入后台：暂停扫描（保留 isScanning 状态以便恢复）
            scanTimer?.invalidate()
            scanTimer = nil
            browser?.stopDiscovery()
            browser = nil
        }
    }

    // MARK: - 内部方法

    /// 启动一次 browser 搜索
    private func startBrowserSearch() {
        // 停止上一次搜索（增量扫描）
        browser?.stopDiscovery()
        // 创建新 browser 并启动
        let newBrowser = browserFactory()
        newBrowser.startDiscovery(type: serviceType) { [weak self] service in
            self?.handleDiscoveredService(service)
        }
        browser = newBrowser
    }

    /// 启动周期扫描 Timer
    private func startPeriodicTimer() {
        let interval = TimeInterval(scanIntervalSec)
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            // Timer 在主线程回调，但需要确保 MainActor 上下文
            Task { @MainActor [weak self] in
                self?.startBrowserSearch()
            }
        }
    }

    /// 处理发现的服务：转换为 MCPConfigFile.Server 并注册到 manager
    private func handleDiscoveredService(_ service: DiscoveredService) {
        let boundary = resolveTrustBoundary(service)
        let server = MCPConfigFile.Server(
            id: service.name,
            name: service.name,
            transport: .sse(url: makeSSEURL(host: service.hostName, port: service.port), headers: nil),
            trust: boundary,
            autoConnect: false,
            toolWhitelist: nil,
            toolBlacklist: nil,
            publicKeyPin: nil
        )
        manager.addDiscoveredCandidate(server, boundary: boundary)
    }

    /// 解析信任边界：优先 TXT record 的 trust 字段，缺省根据 host 判定
    private func resolveTrustBoundary(_ service: DiscoveredService) -> TrustBoundary {
        if let trustRaw = service.txtRecord["trust"]?.lowercased(),
           let trust = TrustBoundary(rawValue: trustRaw) {
            return trust
        }
        // 根据 host 判定：私有 IP → lan，公网 → public
        if isPrivateHost(service.hostName) {
            return .lan
        }
        return .public
    }

    /// 构造 SSE URL
    private func makeSSEURL(host: String, port: Int) -> String {
        // 使用 http 协议（HTTPS 由 Server 自身决定，配置中可后续覆盖）
        "http://\(host):\(port)/sse"
    }

    /// 判断是否为私有网络主机
    private func isPrivateHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" { return true }
        if lower.hasSuffix(".local") { return true }
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 127 { return true }
        if parts[0] == 10 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        return false
    }
}

// MARK: - BonjourServiceBrowser（生产实现）

/// 基于 NetService 的 Bonjour 服务浏览实现。
///
/// 使用 NetServiceBrowser + NetServiceDelegate 扫描 `_aether_mcp._tcp` 服务。
/// 发现服务后通过 TXT record 解析信任档位等信息。
final class BonjourServiceBrowser: NSObject, MCPServiceBrowsing, @unchecked Sendable {
    /// NetService 浏览器
    private var browser: NetServiceBrowser?
    /// 发现回调
    private var discoveryHandler: ((DiscoveredService) -> Void)?
    /// 已解析的服务缓存（避免重复解析）
    private var resolvingServices: Set<String> = []
    /// 线程安全锁
    private let lock = NSLock()

    /// 启动 Bonjour 服务浏览
    /// - Parameters:
    ///   - type: Bonjour 服务类型
    ///   - handler: 发现回调
    func startDiscovery(type: String, handler: @escaping (DiscoveredService) -> Void) {
        stopDiscovery()
        lock.lock()
        discoveryHandler = handler
        resolvingServices.removeAll()
        let newBrowser = NetServiceBrowser()
        newBrowser.delegate = self
        newBrowser.searchForServices(ofType: type, inDomain: "")
        browser = newBrowser
        lock.unlock()
    }

    /// 停止浏览
    func stopDiscovery() {
        lock.lock()
        browser?.stop()
        browser = nil
        discoveryHandler = nil
        resolvingServices.removeAll()
        lock.unlock()
    }
}

// MARK: - NetServiceBrowserDelegate

extension BonjourServiceBrowser: NetServiceBrowserDelegate {
    /// 发现新服务时触发：解析 hostName 与 TXT record
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        lock.lock()
        let alreadyResolving = resolvingServices.contains(service.name)
        if !alreadyResolving {
            resolvingServices.insert(service.name)
        }
        lock.unlock()
        guard !alreadyResolving else { return }

        // 设置 delegate 并解析 hostName + TXT record
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    /// 服务消失
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        lock.lock()
        resolvingServices.remove(service.name)
        lock.unlock()
    }
}

// MARK: - NetServiceDelegate

extension BonjourServiceBrowser: NetServiceDelegate {
    /// 服务解析成功：提取 hostName、port、TXT record
    func netServiceDidResolveAddress(_ sender: NetService) {
        let txtRecord = parseTXTRecord(sender.txtRecordData())
        let service = DiscoveredService(
            name: sender.name,
            hostName: sender.hostName ?? sender.name,
            port: sender.port,
            txtRecord: txtRecord
        )

        lock.lock()
        let handler = discoveryHandler
        lock.unlock()

        // 在主线程回调（MCPDiscoveryService 是 @MainActor）
        DispatchQueue.main.async {
            handler?(service)
        }
    }

    /// 解析失败：从 resolving 集合移除（允许后续重试）
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        lock.lock()
        resolvingServices.remove(sender.name)
        lock.unlock()
    }

    /// 解析 TXT record 数据为字典
    private func parseTXTRecord(_ data: Data?) -> [String: String] {
        guard let data = data else { return [:] }
        var result: [String: String] = [:]
        // NetService.txtRecordData() 返回 DNS TXT record 格式
        // 使用 NetService.dictionary(fromTXTRecord:) 解析
        let dict = NetService.dictionary(fromTXTRecord: data)
        for (key, value) in dict {
            result[key] = String(data: value, encoding: .utf8) ?? ""
        }
        return result
    }
}
