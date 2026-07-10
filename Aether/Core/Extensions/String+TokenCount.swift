import Foundation

extension String {
    /// 粗略估算字符串的 token 数。
    ///
    /// 算法：英文按空格分词乘 1.3，非 ASCII 字符（中日韩等）每字约 1.5 token。
    /// 综合两者给出估算值，用于 tokenLimit 截断和文档分块。
    var estimatedTokens: Int {
        let asciiWords = self.split(separator: " ").count
        let nonASCIICount = self.filter { $0.isASCII == false }.count
        let asciiTokenEstimate = Double(asciiWords) * 1.3
        let nonASCIITokenEstimate = Double(nonASCIICount) * 1.5
        return Int(asciiTokenEstimate + nonASCIITokenEstimate)
    }
}
