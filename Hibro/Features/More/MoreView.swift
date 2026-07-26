import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("协作资源") {
                NavigationLink {
                    ConversationsView()
                } label: {
                    ResourceRow(
                        title: "对话",
                        caption: "在任务上下文中继续与 Agent 沟通",
                        symbol: "bubble.left.and.bubble.right",
                        color: HibroTheme.cyan,
                        count: model.conversations.count
                    )
                }
                NavigationLink {
                    AgentsView()
                } label: {
                    ResourceRow(
                        title: "Agents",
                        caption: "查看可用能力与执行位置",
                        symbol: "cpu",
                        color: HibroTheme.violet,
                        count: model.agents.count
                    )
                }
                NavigationLink {
                    ArtifactsView()
                } label: {
                    ResourceRow(
                        title: "产出",
                        caption: "浏览任务交付的文件和报告",
                        symbol: "doc.text",
                        color: HibroTheme.orange,
                        count: model.artifacts.count
                    )
                }
            }
            Section("系统") {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("更多")
    }
}

private struct ResourceRow: View {
    let title: String
    let caption: String
    let symbol: String
    let color: Color
    let count: Int

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(
                    color.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
