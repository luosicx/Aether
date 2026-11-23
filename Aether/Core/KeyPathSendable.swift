import Foundation

/// SwiftData 的 `#Predicate` / `SortDescriptor` 要求 key path 满足 Sendable，
/// 但标准库的 `KeyPath` 并未声明 Sendable，严格并发下每个
/// `#Predicate { $0.xxx == y }` 都会报
/// "type 'KeyPath<Model, T>' does not conform to the 'Sendable' protocol"。
///
/// `KeyPath` 只保存属性路径的类型元数据，本身不持有 Root/Value 实例，跨隔离传递不会
/// 共享可变状态，因此补一个 @unchecked Sendable 遵循；@retroactive 表明这是对标准库
/// 类型的后补遵循。若未来标准库正式声明该遵循，会以冗余告警提示移除此扩展。
extension KeyPath: @retroactive @unchecked Sendable {}
