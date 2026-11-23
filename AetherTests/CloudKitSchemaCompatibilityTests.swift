import SwiftData
import XCTest
@testable import Aether

/// CloudKit 同步对 SwiftData schema 的硬性约束：
/// 1. 属性必须可选或带默认值；
/// 2. 不得使用 `@Attribute(.unique)`；
/// 3. 关系必须可选，且声明了 inverse。
///
/// 违反任一条，`ModelConfiguration(cloudKitDatabase: .automatic)` 创建容器时会抛
/// DetailedError 134060，App 静默回退本地存储、iCloud 同步不生效。
/// 这些断言把上述规则固化到 CI，改模型时立刻暴露问题。
final class CloudKitSchemaCompatibilityTests: XCTestCase {

    private func makeSchema() -> Schema {
        Schema([
            Conversation.self, ChatMessage.self, DocumentChunk.self,
            MessageFeedback.self, HealthInsight.self, UserPreference.self,
            AgentTask.self, Memory.self
        ])
    }

    /// 所有属性必须可选或带默认值（同步端可能收到字段缺失的记录）
    func testAllAttributesAreOptionalOrDefaulted() {
        for entity in makeSchema().entities {
            for attribute in entity.attributes {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) 必须可选或带默认值，否则不兼容 CloudKit"
                )
            }
        }
    }

    /// CloudKit 无法跨设备做原子唯一性校验，禁止唯一约束
    func testNoUniqueAttributes() {
        for entity in makeSchema().entities {
            for attribute in entity.attributes {
                XCTAssertFalse(
                    attribute.isUnique,
                    "\(entity.name).\(attribute.name) 使用了唯一约束，CloudKit 不支持"
                )
            }
        }
    }

    /// 所有关系必须为可选（含 to-many）
    func testAllRelationshipsAreOptional() {
        for entity in makeSchema().entities {
            for relationship in entity.relationships {
                XCTAssertTrue(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) 必须声明为可选关系，否则不兼容 CloudKit"
                )
            }
        }
    }
}
