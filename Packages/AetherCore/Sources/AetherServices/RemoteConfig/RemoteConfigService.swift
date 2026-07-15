import Foundation
import AetherFoundation

/// Day 14: 远程配置拉取服务。负责从远程 endpoint 拉取 JSON 配置、本地缓存（UserDefaults + 24h TTL）、
/// 失败回退到缓存或内置默认值。actor 隔离保证并发安全，单例 shared 供 App 启动时调用。
public actor RemoteConfigService {
    /// 当前生效的远程配置，初值为内置默认值
    public private(set) var currentConfig: RemoteConfig = .default

    /// UserDefaults 缓存键
    private let cacheKey = "remote_config_cache"

    /// 缓存有效期，24 小时
    private let cacheTTL: TimeInterval = 24 * 3600

    /// 远程配置 endpoint，默认指向阿里云 OSS 公开读 URL（占位），可通过 init 注入用于测试
    private let endpointURL: URL

    /// 单例，供 App 启动时异步拉取
    public static let shared = RemoteConfigService()

    /// 允许测试注入 endpoint
    public init(endpointURL: URL? = nil) {
        guard let url = endpointURL ?? URL(string: "https://aether-config.oss-cn-hangzhou.aliyuncs.com/remote_config.json") else {
            fatalError("远程配置 URL 无效，无法初始化 RemoteConfigService")
        }
        self.endpointURL = url
    }

    /// 异步拉取远程配置：请求 endpoint → 解码 RemoteConfig → 写入 fetchedAt → 缓存到 UserDefaults → 更新 currentConfig。
    /// 失败时回退到 loadCachedConfig()，若也为 nil 则用 fallbackConfig()。方法不抛错，保证调用方安全 fire-and-forget。
    public func fetch() async {
        do {
            // 拉取远程 JSON
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: endpointURL))
            // 校验 HTTP 状态码
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // 非 2xx 视为失败，走回退逻辑
                applyFallback()
                return
            }
            // 解码为 RemoteConfig（自定义 init 处理缺失字段）
            var config = try JSONDecoder().decode(RemoteConfig.self, from: data)
            // 写入拉取时间戳，用于本地缓存 TTL 判断
            config.fetchedAt = Date()
            // 缓存到 UserDefaults：编码后写入
            let jsonData = try JSONEncoder().encode(config)
            UserDefaults.standard.set(jsonData, forKey: cacheKey)
            // 更新当前生效配置
            currentConfig = config
        } catch {
            // 网络错误或解码失败，走回退逻辑
            applyFallback()
        }
    }

    /// 回退逻辑：先尝试加载本地缓存，若为 nil（不存在或过期）则使用 fallbackConfig
    private func applyFallback() {
        if let cached = loadCachedConfig() {
            currentConfig = cached
        } else {
            currentConfig = fallbackConfig()
        }
    }

    /// 从 UserDefaults 读取缓存配置；检查 fetchedAt + cacheTTL 是否过期，过期返回 nil。
    private func loadCachedConfig() -> RemoteConfig? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        do {
            let config = try JSONDecoder().decode(RemoteConfig.self, from: data)
            // 校验 TTL：fetchedAt 为空或已过期则视为缓存失效
            guard let fetchedAt = config.fetchedAt else {
                return nil
            }
            if Date().timeIntervalSince(fetchedAt) > cacheTTL {
                // 缓存过期
                return nil
            }
            return config
        } catch {
            // 解码失败，缓存损坏
            return nil
        }
    }

    /// 兜底配置：返回 .default，但 fetchedAt 设为当前时间，避免每次 fetch 都因无缓存而反复尝试拉取。
    private func fallbackConfig() -> RemoteConfig {
        var config = RemoteConfig.default
        config.fetchedAt = Date()
        return config
    }
}
