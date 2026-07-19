import XCTest
@testable import Aether

/// `MCPDiscoveryService` Zeroconf 扫描的单元测试。
///
/// 覆盖范围：
/// 1. 启动扫描后通过 mock browser 触发发现回调
/// 2. 发现的 Server 经由 MCPClientManager 注册为候选
/// 3. 60s 周期增量扫描触发
/// 4. iOS 后台不可用兜底（前台扫描 + 配置文件兜底）
/// 5. 停止扫描后不再触发回调
final class MCPDiscoveryServiceTests: XCTestCase {

    // MARK: - 1. 启动扫描与发现回调

    /// 启动扫描后，mock browser 报告服务发现应触发 manager.addDiscoveredCandidate
    @MainActor
    func testStartScanningDiscoversService() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()

        // 模拟发现一个 _aether_mcp._tcp 服务
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "discovered-server",
                hostName: "discovered-server.local",
                port: 3000,
                txtRecord: ["trust": "lan"]
            )
        )

        // 等待异步处理
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(manager.candidateServers.count, 1, "应将发现的服务加入候选列表")
        XCTAssertEqual(manager.candidateServers[0].id, "discovered-server")
        XCTAssertEqual(manager.candidateServers[0].name, "discovered-server")

        service.stopScanning()
    }

    /// 发现的 Server 应包含正确的 SSE URL（基于 hostName + port）
    @MainActor
    func testDiscoveredServerHasCorrectSSEURL() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "srv1",
                hostName: "192.168.1.100",
                port: 8080,
                txtRecord: ["trust": "lan"]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        let server = manager.candidateServers.first
        XCTAssertEqual(server?.id, "srv1")

        if case .sse(let url, _) = server?.transport {
            XCTAssertTrue(url.contains("192.168.1.100"), "SSE URL 应包含 host")
            XCTAssertTrue(url.contains("8080"), "SSE URL 应包含 port")
        } else {
            XCTFail("应为 SSE 传输")
        }

        service.stopScanning()
    }

    // MARK: - 2. 增量扫描

    /// 周期扫描触发后应再次启动 browser 搜索
    @MainActor
    func testPeriodicScanTriggersNewSearch() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        // 使用 1 秒间隔加速测试
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 1
        )

        service.startScanning()
        let initialSearchCount = mockBrowser.searchStartedCount

        // 等待至少一次周期扫描
        try await Task.sleep(nanoseconds: 1_500_000_000)

        XCTAssertGreaterThan(mockBrowser.searchStartedCount, initialSearchCount, "周期扫描应触发新的 search")

        service.stopScanning()
    }

    // MARK: - 3. 停止扫描

    /// 停止扫描后 browser 应停止
    @MainActor
    func testStopScanningStopsBrowser() {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        XCTAssertTrue(mockBrowser.isSearching, "启动后 browser 应在搜索")

        service.stopScanning()
        XCTAssertFalse(mockBrowser.isSearching, "停止后 browser 不应再搜索")
    }

    // MARK: - 4. TXT Record 解析

    /// TXT record 中的 trust 字段应映射到信任边界
    @MainActor
    func testTXTRecordTrustParsing() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "public-srv",
                hostName: "public.example.com",
                port: 443,
                txtRecord: ["trust": "public"]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        let boundary = manager.getCandidateTrustBoundary(serverID: "public-srv")
        XCTAssertEqual(boundary, .internet, "trust=public 应映射到 internet 信任档位")

        service.stopScanning()
    }

    /// 缺省 TXT record 的 trust 应根据 host 判定（私有 IP → lan）
    @MainActor
    func testDefaultTrustFromHost() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "lan-srv",
                hostName: "192.168.1.50",
                port: 3000,
                txtRecord: [:]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        let boundary = manager.getCandidateTrustBoundary(serverID: "lan-srv")
        XCTAssertEqual(boundary, .lan, "私有 IP 应判定为 lan")

        service.stopScanning()
    }

    // MARK: - 5. 重复发现去重

    /// 同一 Server 重复发现不应重复添加
    @MainActor
    func testDuplicateDiscoveryDeduplicated() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(name: "dup", hostName: "192.168.1.50", port: 3000, txtRecord: [:])
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        mockBrowser.simulateDiscovery(
            DiscoveredService(name: "dup", hostName: "192.168.1.50", port: 3000, txtRecord: [:])
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(manager.candidateServers.count, 1, "重复发现应去重")

        service.stopScanning()
    }

    // MARK: - 6. iOS 后台兜底

    /// iOS 后台时扫描应暂停（通过 isForegroundActive 控制）
    @MainActor
    func testBackgroundScanPaused() {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        XCTAssertTrue(mockBrowser.isSearching)

        // 模拟进入后台
        service.setForegroundActive(false)
        XCTAssertFalse(mockBrowser.isSearching, "后台时应停止搜索")

        // 模拟回到前台
        service.setForegroundActive(true)
        XCTAssertTrue(mockBrowser.isSearching, "回前台应恢复搜索")

        service.stopScanning()
    }

    // MARK: - 7. TXT Record trust 字段解析（local / lan）

    /// TXT record trust=local 应解析为 .local 信任档位，触发 .allow 自动连接（不进入候选列表）。
    @MainActor
    func testTXTRecordTrustLocalParsed() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "local-trust-srv",
                hostName: "192.168.1.200",
                port: 3000,
                txtRecord: ["trust": "local"]
            )
        )
        // 等待自动连接 Task 完成（.local → .allow → connect）
        try await Task.sleep(nanoseconds: 300_000_000)

        // trust=local → resolveTrustBoundary 返回 .local → decision=.allow → 自动连接
        // 不进入候选列表，candidateTrustBoundaries 不存储
        XCTAssertEqual(manager.candidateServers.count, 0, "trust=local 应自动连接，不进入候选列表")
        XCTAssertNil(manager.getCandidateTrustBoundary(serverID: "local-trust-srv"),
                     "local 信任档位不存储在 candidateTrustBoundaries")
        // 自动连接应成功（MockMCPClient 默认连接成功）
        XCTAssertEqual(manager.serverInfos["local-trust-srv"]?.status, .connected,
                       "trust=local 应触发自动连接并连接成功")

        service.stopScanning()
    }

    /// TXT record trust=lan 应解析为 .lan 信任档位，进入候选列表待用户确认。
    @MainActor
    func testTXTRecordTrustLanParsed() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "lan-trust-srv",
                hostName: "203.0.113.5",
                port: 3000,
                txtRecord: ["trust": "lan"]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        // trust=lan → resolveTrustBoundary 返回 .lan → decision=requireConfirmation → 进入候选列表
        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "lan-trust-srv"), .lan,
                       "trust=lan 应映射到 lan 信任档位")

        service.stopScanning()
    }

    // MARK: - 8. isPrivateHost 缺省信任判定（无 TXT trust 字段）

    /// hostName="localhost" 应判定为私有网络 → .lan。
    @MainActor
    func testDefaultTrustFromLocalhost() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "localhost-srv",
                hostName: "localhost",
                port: 3000,
                txtRecord: [:]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "localhost-srv"), .lan,
                       "localhost 应判定为私有网络 → lan")

        service.stopScanning()
    }

    /// hostName="127.0.0.1"（127.x.x.x 回环 subnet）应判定为 .lan。
    @MainActor
    func testDefaultTrustFrom127Subnet() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "loopback-srv",
                hostName: "127.0.0.1",
                port: 3000,
                txtRecord: [:]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "loopback-srv"), .lan,
                       "127.x.x.x 回环地址应判定为 lan")

        service.stopScanning()
    }

    /// hostName="10.0.0.5"（10.x.x.x 私有 subnet）应判定为 .lan。
    @MainActor
    func testDefaultTrustFrom10Subnet() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "ten-subnet-srv",
                hostName: "10.0.0.5",
                port: 3000,
                txtRecord: [:]
            )
        )
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "ten-subnet-srv"), .lan,
                       "10.x.x.x 私有地址应判定为 lan")

        service.stopScanning()
    }

    /// hostName 为 172.16-31.x.x 应判定为 .lan；172.32.x.x 不在私有范围 → .internet。
    @MainActor
    func testDefaultTrustFrom172Subnet() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        // 172.16.0.1 — 私有范围下界
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "172-16-srv",
                hostName: "172.16.0.1",
                port: 3000,
                txtRecord: [:]
            )
        )
        // 172.31.255.255 — 私有范围上界
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "172-31-srv",
                hostName: "172.31.255.255",
                port: 3000,
                txtRecord: [:]
            )
        )
        // 172.32.0.1 — 私有范围之外
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "172-32-srv",
                hostName: "172.32.0.1",
                port: 3000,
                txtRecord: [:]
            )
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "172-16-srv"), .lan,
                       "172.16.x.x 应判定为 lan（私有范围下界）")
        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "172-31-srv"), .lan,
                       "172.31.x.x 应判定为 lan（私有范围上界）")
        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "172-32-srv"), .internet,
                       "172.32.x.x 不在私有范围，应判定为 internet")

        service.stopScanning()
    }

    /// hostName 为非 IPv4 格式（abc / 1.2.3）应判定为 .internet。
    @MainActor
    func testDefaultTrustFromNonIPv4Host() async throws {
        let mockBrowser = MockServiceBrowser()
        let manager = MCPClientManager(clientFactory: { config in
            MockMCPClient(config: config)
        })
        let service = MCPDiscoveryService(
            manager: manager,
            browserFactory: { mockBrowser },
            scanIntervalSec: 60
        )

        service.startScanning()
        // 非法主机名（无 IPv4 段）
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "non-ip-srv",
                hostName: "abc",
                port: 3000,
                txtRecord: [:]
            )
        )
        // 段数不足 4 的地址
        mockBrowser.simulateDiscovery(
            DiscoveredService(
                name: "short-ip-srv",
                hostName: "1.2.3",
                port: 3000,
                txtRecord: [:]
            )
        )
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "non-ip-srv"), .internet,
                       "非 IPv4 主机名应判定为 internet")
        XCTAssertEqual(manager.getCandidateTrustBoundary(serverID: "short-ip-srv"), .internet,
                       "段数不足 4 的地址应判定为 internet")

        service.stopScanning()
    }
}

// MARK: - Mock ServiceBrowser

/// 测试用的 ServiceBrowser mock，模拟 Bonjour 服务发现。
/// 遵循 MCPServiceBrowsing 协议，可注入 MCPDiscoveryService。
final class MockServiceBrowser: MCPServiceBrowsing, @unchecked Sendable {
    /// searchForServices 调用次数
    private(set) var searchStartedCount: Int = 0
    /// 是否正在搜索
    private(set) var isSearching: Bool = false
    /// 发现回调（由 MCPDiscoveryService 设置）
    private(set) var discoveryHandler: ((DiscoveredService) -> Void)?

    private let lock = NSLock()

    /// 启动搜索
    func startDiscovery(type: String, handler: @escaping (DiscoveredService) -> Void) {
        lock.lock()
        searchStartedCount += 1
        isSearching = true
        discoveryHandler = handler
        lock.unlock()
    }

    /// 停止搜索
    func stopDiscovery() {
        lock.lock()
        isSearching = false
        discoveryHandler = nil
        lock.unlock()
    }

    /// 模拟发现一个服务，触发 handler 回调
    func simulateDiscovery(_ service: DiscoveredService) {
        lock.lock()
        let handler = discoveryHandler
        lock.unlock()
        handler?(service)
    }
}
