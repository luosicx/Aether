import Foundation

extension String {
    /// 粗略估算字符串的 token 数。
    ///
    /// 算法：按空格分词后乘以 1.3 系数（英文经验值）。
    ///
    /// 局限性：中文/日文等非空格分词语言估算偏低，仅用于 tokenLimit 截断场景的粗略判断。
    var estimatedTokens: Int {
        let words = self.split(separator: " ").count
        return Int(Double(words) * 1.3)
    }
}
