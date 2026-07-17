import Foundation

/// Task 24 阶段 4: Aether SDK 鉴权配置。
///
/// 四种鉴权方案：
/// - `.apiKey`：Header `X-API-Key`（个人开发者默认）
/// - `.oauth`：OAuth 2.0 Authorization Code Flow（企业/团队）
/// - `.jwt`：RS256 签名的 JWT（服务间）
/// - `.deviceBound`：DeviceID + API Key 绑定（防滥用）
public enum AuthConfig: Sendable, Equatable {
    /// API Key 方案：通过 Header `X-API-Key` 传递
    case apiKey
    /// OAuth 2.0 Authorization Code Flow，携带 access_token
    case oauth(OAuthCredential)
    /// JWT（RS256 签名），携带完整 JWT 字符串
    case jwt(JWTCredential)
    /// 设备绑定方案：DeviceID + API Key 组合
    case deviceBound(deviceID: String, apiKey: String)

    /// 默认方案：API Key
    public static let `default`: AuthConfig = .apiKey

    /// 应注入到 HTTP 请求的鉴权 headers
    public var headers: [String: String] {
        switch self {
        case .apiKey:
            // 实际 key 由 AetherClient.config.apiKey 提供，此处仅声明 header 名
            // AetherClient 在构造请求时填充
            return [:]
        case .oauth(let cred):
            return ["Authorization": "Bearer \(cred.accessToken)"]
        case .jwt(let cred):
            return ["Authorization": "Bearer \(cred.token)"]
        case .deviceBound(let deviceID, let apiKey):
            return [
                "X-API-Key": apiKey,
                "X-Device-ID": deviceID
            ]
        }
    }

    /// 鉴权方案标识（用于日志与审计）
    public var schemeName: String {
        switch self {
        case .apiKey: return "api_key"
        case .oauth: return "oauth2"
        case .jwt: return "jwt"
        case .deviceBound: return "device_bound"
        }
    }
}

/// OAuth 2.0 凭证
public struct OAuthCredential: Sendable, Equatable {
    /// Access Token
    public var accessToken: String
    /// Refresh Token（可选，用于刷新 access_token）
    public var refreshToken: String?
    /// Token 过期时间戳（Unix epoch 秒）
    public var expiresAt: Date?
    /// Token 类型，默认 "Bearer"
    public var tokenType: String

    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: String = "Bearer"
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
    }

    /// Token 是否已过期（无 expiresAt 视为未过期，留给服务端校验）
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }
}

/// JWT 凭证（RS256 签名）
public struct JWTCredential: Sendable, Equatable {
    /// 完整的 JWT 字符串（header.payload.signature）
    public var token: String
    /// 签发者（issuer，可选）
    public var issuer: String?
    /// 受众（audience，可选）
    public var audience: String?
    /// 过期时间戳
    public var expiresAt: Date?

    public init(
        token: String,
        issuer: String? = nil,
        audience: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.token = token
        self.issuer = issuer
        self.audience = audience
        self.expiresAt = expiresAt
    }

    /// Token 是否已过期
    public var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// 从 JWT 字符串解析 payload（不验证签名，仅 base64 解码）
    /// - Returns: payload 字典；解析失败返回 nil
    public func decodePayload() -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
        // base64url → base64 padding
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = payload.count % 4
        if pad > 0 {
            payload.append(String(repeating: "=", count: 4 - pad))
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
