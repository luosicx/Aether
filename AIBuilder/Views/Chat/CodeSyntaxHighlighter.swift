import SwiftUI

/// 轻量级代码语法高亮器：基于正则匹配关键字/字符串/注释/数字
enum CodeSyntaxHighlighter {
    // MARK: - 深色主题配色（类似 Xcode 深色）

    /// 关键字：粉紫色
    static let keywordColor = Color(red: 0.85, green: 0.45, blue: 0.85)
    /// 字符串：绿色
    static let stringColor = Color(red: 0.55, green: 0.80, blue: 0.50)
    /// 注释：灰色斜体
    static let commentColor = Color(red: 0.50, green: 0.55, blue: 0.60)
    /// 数字：橙色
    static let numberColor = Color(red: 0.90, green: 0.65, blue: 0.40)
    /// 类型名：黄色
    static let typeColor = Color(red: 0.85, green: 0.80, blue: 0.50)
    /// 函数名：蓝色
    static let functionColor = Color(red: 0.50, green: 0.70, blue: 0.95)
    /// 普通文本：浅灰白
    static let plainColor = Color(red: 0.88, green: 0.88, blue: 0.88)

    // MARK: - 语言关键字

    private static let keywords: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "for", "while", "switch", "case", "default", "struct", "class", "enum", "protocol", "extension", "import", "init", "deinit", "self", "super", "nil", "true", "false", "throws", "rethrows", "try", "catch", "do", "defer", "in", "where", "as", "is", "private", "public", "internal", "fileprivate", "static", "final", "open", "lazy", "weak", "unowned", "inout", "mutating", "nonmutating", "override", "required", "optional", "associatedtype", "typealias", "subscript", "operator", "precedencegroup", "convenience"],
        "python": ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "finally", "with", "lambda", "yield", "global", "nonlocal", "pass", "break", "continue", "raise", "assert", "del", "in", "is", "not", "and", "or", "None", "True", "False", "async", "await", "self", "cls", "print", "len", "range", "int", "str", "float", "list", "dict", "set", "tuple", "bool"],
        "javascript": ["var", "let", "const", "function", "return", "if", "else", "for", "while", "switch", "case", "break", "continue", "new", "this", "class", "extends", "super", "import", "export", "default", "try", "catch", "finally", "throw", "typeof", "instanceof", "in", "of", "async", "await", "yield", "true", "false", "null", "undefined", "void", "delete", "void", "console"],
        "json": ["true", "false", "null"],
        "java": ["public", "private", "protected", "class", "interface", "extends", "implements", "static", "final", "void", "int", "long", "double", "float", "boolean", "char", "String", "if", "else", "for", "while", "switch", "case", "break", "continue", "return", "new", "this", "super", "try", "catch", "finally", "throw", "throws", "import", "package", "null", "true", "false", "instanceof"],
        "kotlin": ["fun", "val", "var", "class", "object", "interface", "if", "else", "for", "while", "when", "return", "override", "private", "public", "protected", "internal", "companion", "import", "package", "null", "true", "false", "is", "as", "in", "by", "data", "sealed", "enum", "annotation", "open", "abstract", "final", "lateinit", "suspend", "async", "await"],
        "go": ["func", "var", "const", "type", "struct", "interface", "package", "import", "if", "else", "for", "switch", "case", "default", "return", "break", "continue", "defer", "go", "chan", "range", "map", "make", "new", "nil", "true", "false", "select", "type"],
        "rust": ["fn", "let", "mut", "if", "else", "match", "for", "while", "loop", "return", "break", "continue", "struct", "enum", "trait", "impl", "pub", "use", "mod", "crate", "self", "Self", "super", "as", "in", "ref", "move", "static", "const", "unsafe", "async", "await", "dyn", "where", "type", "true", "false"],
        "c": ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "struct", "union", "enum", "typedef", "const", "static", "extern", "register", "volatile", "auto", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "goto", "sizeof", "include", "define", "ifdef", "ifndef", "endif", "pragma", "NULL"],
        "cpp": ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed", "struct", "class", "union", "enum", "typedef", "const", "static", "extern", "register", "volatile", "auto", "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return", "goto", "sizeof", "include", "define", "ifdef", "ifndef", "endif", "namespace", "using", "template", "typename", "new", "delete", "public", "private", "protected", "virtual", "override", "final", "nullptr", "true", "false", "std"],
        "sql": ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "INDEX", "VIEW", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND", "OR", "NOT", "NULL", "IS", "IN", "EXISTS", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "OFFSET", "DISTINCT", "AS", "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "COUNT", "SUM", "AVG", "MIN", "MAX"]
    ]

    // MARK: - 高亮入口

    /// 将代码转换为带语法高亮的 AttributedString
    static func highlight(_ code: String, language: String?) -> AttributedString {
        let lang = (language ?? "").lowercased()
        var attributed = AttributedString(code)
        attributed.foregroundColor = plainColor

        // 通用高亮：字符串、注释、数字（所有语言适用）
        applyStringHighlights(&attributed, code: code)
        applyCommentHighlights(&attributed, code: code)
        applyNumberHighlights(&attributed, code: code)

        // 语言特定关键字高亮
        if let keywordSet = keywords[lang] ?? keywords[lang.replacingOccurrences(of: " ", with: "")] {
            applyKeywordHighlights(&attributed, code: code, keywords: keywordSet, caseSensitive: lang != "sql")
        } else {
            // 未知语言：尝试大小写不敏感匹配通用关键字
            let allKeywords = Set(keywords.values.flatMap { $0 })
            applyKeywordHighlights(&attributed, code: code, keywords: allKeywords, caseSensitive: true)
        }

        return attributed
    }

    // MARK: - 字符串高亮

    private static func applyStringHighlights(_ attributed: inout AttributedString, code: String) {
        // 双引号字符串
        let pattern = #""(?:[^"\\]|\\.)*""#
        highlightPattern(&attributed, code: code, pattern: pattern, color: stringColor)
        // 单引号字符串
        let singlePattern = #"'(?:[^'\\]|\\.)*'"#
        highlightPattern(&attributed, code: code, pattern: singlePattern, color: stringColor)
    }

    // MARK: - 注释高亮

    private static func applyCommentHighlights(_ attributed: inout AttributedString, code: String) {
        // 单行注释 //
        let singleLinePattern = #"//[^\n]*"#
        highlightPattern(&attributed, code: code, pattern: singleLinePattern, color: commentColor, italic: true)
        // 单行注释 #
        let hashPattern = #"#[^\n]*"#
        highlightPattern(&attributed, code: code, pattern: hashPattern, color: commentColor, italic: true)
        // 多行注释 /* ... */
        let multiPattern = #"/\*[\s\S]*?\*/"#
        highlightPattern(&attributed, code: code, pattern: multiPattern, color: commentColor, italic: true)
    }

    // MARK: - 数字高亮

    private static func applyNumberHighlights(_ attributed: inout AttributedString, code: String) {
        let pattern = #"\b\d+\.?\d*[eE]?[+-]?\d*\b"#
        highlightPattern(&attributed, code: code, pattern: pattern, color: numberColor)
    }

    // MARK: - 关键字高亮

    private static func applyKeywordHighlights(_ attributed: inout AttributedString, code: String, keywords: Set<String>, caseSensitive: Bool) {
        for keyword in keywords {
            let pattern = caseSensitive ? "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b" : "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            highlightPattern(&attributed, code: code, pattern: pattern, color: keywordColor, options: caseSensitive ? [] : .caseInsensitive)
        }
    }

    // MARK: - 通用正则高亮

    private static func highlightPattern(_ attributed: inout AttributedString, code: String, pattern: String, color: Color, italic: Bool = false, options: NSRegularExpression.Options = []) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        let matches = regex.matches(in: code, range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: code) else { continue }
            if let attrRange = attributed.range(of: String(code[swiftRange])) {
                attributed[attrRange].foregroundColor = color
                if italic {
                    attributed[attrRange].font = .system(.callout, design: .monospaced).italic()
                }
            }
        }
    }
}
