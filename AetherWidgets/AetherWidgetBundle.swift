import WidgetKit
import SwiftUI

/// Task 5: Aether Widget Bundle 入口，注册三类 Widget。
@main
struct AetherWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickChatWidget()
        HealthInsightWidget()
        RecentConversationsWidget()
    }
}
