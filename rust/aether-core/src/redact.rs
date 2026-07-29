//! 遥测日志脱敏：移除用户敏感上下文（UUID/邮箱/URL/Token/密码字段/路径）。
//!
//! 将 Swift `TelemetrySanitizer` 的 7 个 NSRegularExpression 模式迁移至 Rust `regex` crate。
//! Rust regex 基于 RE2 语法（线性时间 NFA + SIMD），不支持反向断言（lookbehind），
//! 故路径模式用捕获组替代 `(?<![:\w])`：`(?:^|[^:\w])` 保留前缀字符。
//!
//! 模式顺序与 Swift 一致：URL 先于路径处理，避免路径规则误伤 URL 的 path 部分。

use regex::Regex;
use std::sync::OnceLock;

/// 脱敏规则：预编译的正则与替换模板。
struct Rule {
    regex: Regex,
    replacement: &'static str,
}

/// 预编译的脱敏规则集（线程安全，首次访问时编译一次）。
fn rules() -> &'static [Rule] {
    static RULES: OnceLock<Vec<Rule>> = OnceLock::new();
    RULES.get_or_init(|| {
        // 编译期保证语法正确：编译失败会 panic（仅在 bug 时发生）
        vec![
            // 1. UUID，如 550e8400-e29b-41d4-a716-446655440000
            Rule {
                regex: Regex::new(
                    r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b",
                )
                .unwrap(),
                replacement: "[REDACTED_UUID]",
            },
            // 2. 邮箱地址
            Rule {
                regex: Regex::new(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}").unwrap(),
                replacement: "[REDACTED_EMAIL]",
            },
            // 3. URL（http / https）
            Rule {
                regex: Regex::new(r"https?://[^\s]+").unwrap(),
                replacement: "[REDACTED_URL]",
            },
            // 4. API Token：OpenAI 风格 sk-...
            Rule {
                regex: Regex::new(r"\bsk-[A-Za-z0-9_-]+\b").unwrap(),
                replacement: "[REDACTED_TOKEN]",
            },
            // 5. Bearer Token
            Rule {
                regex: Regex::new(r"\bBearer\s+[A-Za-z0-9_\-\.]+\b").unwrap(),
                replacement: "[REDACTED_TOKEN]",
            },
            // 6. 密码 / 密钥 / Token 字段：password=...、token: ...、api_key=... 等
            //    支持 JSON 格式："password": "value"（v1.6 修复：原正则不匹配键值被引号包围的场景）
            // (?i) 大小写不敏感（Rust regex 用 inline flag (?i:...)）
            // Rust regex 不支持反向引用，故键值前后引号独立匹配（["']?）
            Rule {
                regex: Regex::new(
                    r#"(?i)["']?(password|token|secret|api[_-]?key|access[_-]?token)["']?\s*[:=]\s*["']?[^\s&"']*["']?"#,
                )
                .unwrap(),
                replacement: "[REDACTED_CREDENTIAL]",
            },
            // 7. Unix/macOS 绝对路径，如 /Users/xxx/.ssh/id_rsa、/var/xxx
            // Swift 原用 `(?<![:\w])` 反向断言避免匹配 URL scheme 后的 // 与单词内部；
            // Rust regex 不支持 lookbehind，用 `(^|[^:\w])` 捕获前缀并保留（替换时回填 ${1}）。
            // 路径段不含空格（避免贪婪吞掉后续文本），仅中间段允许 . -，末段允许 . -。
            Rule {
                regex: Regex::new(r"(^|[^:\w])/(?:[\w\-\.]+/)+[\w\-\.]+").unwrap(),
                replacement: "${1}[REDACTED_PATH]",
            },
        ]
    })
}

/// 对输入字符串进行脱敏处理，返回替换后的字符串。
/// 普通错误信息（如 "Network timeout"）不会被修改。
pub fn redact(input: &str) -> String {
    let mut result = input.to_string();
    for rule in rules() {
        result = rule
            .regex
            .replace_all(&result, rule.replacement)
            .to_string();
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_uuid() {
        let input = "请求 ID: 550e8400-e29b-41d4-a716-446655440000 失败";
        assert_eq!(redact(input), "请求 ID: [REDACTED_UUID] 失败");
    }

    #[test]
    fn redacts_email() {
        let input = "联系 user@example.com 获取详情";
        assert_eq!(redact(input), "联系 [REDACTED_EMAIL] 获取详情");
    }

    #[test]
    fn redacts_url() {
        let input = "访问 https://api.example.com/v1/chat 获取数据";
        assert_eq!(redact(input), "访问 [REDACTED_URL] 获取数据");
    }

    #[test]
    fn redacts_openai_token() {
        let input = "使用 sk-abc123xyz456 调用 API";
        assert_eq!(redact(input), "使用 [REDACTED_TOKEN] 调用 API");
    }

    #[test]
    fn redacts_bearer_token() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.token";
        assert_eq!(redact(input), "Authorization: [REDACTED_TOKEN]");
    }

    #[test]
    fn redacts_credential_field() {
        let input = "配置 password=secret123 后启动";
        assert_eq!(redact(input), "配置 [REDACTED_CREDENTIAL] 后启动");
    }

    #[test]
    fn redacts_credential_field_case_insensitive() {
        let input = "API_KEY=mykey456";
        assert_eq!(redact(input), "[REDACTED_CREDENTIAL]");
    }

    #[test]
    fn redacts_credential_field_json_format() {
        // v1.6 修复：JSON 格式 "password": "value" 应被脱敏
        let input = r#"{"password": "mySecret123"}"#;
        assert_eq!(redact(input), r#"{[REDACTED_CREDENTIAL]}"#);
    }

    #[test]
    fn redacts_credential_field_json_no_spaces() {
        let input = r#"{"token":"abc.def.ghi"}"#;
        assert_eq!(redact(input), r#"{[REDACTED_CREDENTIAL]}"#);
    }

    #[test]
    fn redacts_credential_field_json_api_key() {
        let input = r#"{"api_key": "sk-xxx"}"#;
        assert_eq!(redact(input), r#"{[REDACTED_CREDENTIAL]}"#);
    }

    #[test]
    fn redacts_path() {
        let input = "读取 /Users/alice/.ssh/id_rsa 失败";
        assert_eq!(redact(input), "读取 [REDACTED_PATH] 失败");
    }

    #[test]
    fn does_not_redact_plain_message() {
        let input = "Network timeout: 连接超时";
        assert_eq!(redact(input), "Network timeout: 连接超时");
    }

    #[test]
    fn redacts_multiple_patterns() {
        let input = "用户 user@test.com 访问 https://example.com，token: sk-abc123";
        let result = redact(input);
        assert!(result.contains("[REDACTED_EMAIL]"));
        assert!(result.contains("[REDACTED_URL]"));
        assert!(result.contains("[REDACTED_TOKEN]"));
        assert!(!result.contains("user@test.com"));
        assert!(!result.contains("example.com"));
        assert!(!result.contains("sk-abc123"));
    }

    #[test]
    fn empty_string_unchanged() {
        assert_eq!(redact(""), "");
    }

    #[test]
    fn url_not_mistaken_as_path() {
        // URL 先于路径处理，URL 被整体替换为 [REDACTED_URL]，路径规则不再命中
        let input = "访问 https://example.com/path/to/resource";
        let result = redact(input);
        assert_eq!(result, "访问 [REDACTED_URL]");
    }

    #[test]
    fn preserves_prefix_char_for_path() {
        // 路径前的字符（如空格、冒号）应被保留
        let input = "路径 /var/log/system.log 出错";
        let result = redact(input);
        assert_eq!(result, "路径 [REDACTED_PATH] 出错");
    }
}
