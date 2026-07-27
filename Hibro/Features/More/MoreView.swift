import SwiftUI

struct MoreView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("执行资源") {
                NavigationLink {
                    NodesView()
                } label: {
                    ResourceRow(
                        title: "节点",
                        caption: "查看设备连接、版本和承载的 Agent",
                        symbol: "server.rack",
                        color: HibroTheme.cyan,
                        count: model.nodes.count
                    )
                }
                .accessibilityIdentifier("more.nodes")
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
            }
            Section("协作内容") {
                NavigationLink {
                    InboxView()
                } label: {
                    ResourceRow(
                        title: "收件箱",
                        caption: "查看待处理事项和最近完成记录",
                        symbol: "tray",
                        color: HibroTheme.orange,
                        count: model.inboxItems.filter(\.requiresAttention).count
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

struct NodesView: View {
    @Environment(AppModel.self) private var model

    private var onlineNodes: [CoreNode] {
        model.nodes.filter { $0.status == "online" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 0) {
                    NodeMetric(
                        value: onlineNodes.count,
                        title: "在线",
                        color: HibroTheme.accent
                    )
                    Divider().frame(height: 42)
                    NodeMetric(
                        value: model.nodes.count - onlineNodes.count,
                        title: "离线",
                        color: .secondary
                    )
                    Divider().frame(height: 42)
                    NodeMetric(
                        value: model.agents.count,
                        title: "Agents",
                        color: HibroTheme.violet
                    )
                }
                .padding(.vertical, 16)
                .hibroPanel()

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "执行节点",
                        caption: "Agent 实际运行的设备和服务器"
                    )
                    if model.nodes.isEmpty {
                        EmptyStateView(
                            symbol: "server.rack",
                            title: "还没有节点",
                            message: "Node 连接到 Core 后会显示在这里。"
                        )
                        .frame(maxWidth: .infinity, minHeight: 230)
                        .hibroPanel()
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 280), spacing: 14)
                            ],
                            spacing: 14
                        ) {
                            ForEach(model.nodes) { node in
                                NavigationLink {
                                    NodeDetailView(nodeID: node.id)
                                } label: {
                                    NodeCard(node: node)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 1_000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("节点")
        .refreshable { await model.refreshFromUser() }
    }
}

private struct NodeMetric: View {
    let value: Int
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct NodeCard: View {
    @Environment(AppModel.self) private var model
    let node: CoreNode

    private var agents: [CoreAgent] {
        model.agents.filter { $0.nodeId == node.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(HibroTheme.statusColor(node.status))
                    .frame(width: 46, height: 46)
                    .background(
                        HibroTheme.statusColor(node.status).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(node.platformDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: node.status)
            }
            Divider()
            HStack {
                Label("\(agents.count) Agents", systemImage: "cpu")
                Spacer()
                Text("心跳 \(DateText.relative(node.lastSeenAt))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(17)
        .hibroPanel()
        .contentShape(Rectangle())
    }
}

private struct NodeDetailView: View {
    @Environment(AppModel.self) private var model
    let nodeID: String

    private var node: CoreNode? {
        model.nodes.first { $0.id == nodeID }
    }

    private var agents: [CoreAgent] {
        model.agents.filter { $0.nodeId == nodeID }
    }

    var body: some View {
        ScrollView {
            if let node {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 15) {
                        Image(systemName: "server.rack")
                            .font(.title)
                            .foregroundStyle(HibroTheme.statusColor(node.status))
                            .frame(width: 58, height: 58)
                            .background(
                                HibroTheme.statusColor(node.status).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(node.name)
                                .font(.title2.bold())
                            Text(node.platformDescription)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(status: node.status)
                    }
                    .padding(18)
                    .hibroPanel()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "连接信息",
                            caption: "由 Core 最近一次同步"
                        )
                        VStack(spacing: 12) {
                            LabeledContent("版本", value: node.version ?? "—")
                            Divider()
                            LabeledContent(
                                "连接时间",
                                value: DateText.full(node.connectedAt)
                            )
                            Divider()
                            LabeledContent(
                                "最近心跳",
                                value: DateText.full(node.lastSeenAt)
                            )
                            Divider()
                            LabeledContent("Node ID", value: node.id)
                        }
                        .font(.subheadline)
                        .padding(17)
                        .hibroPanel()
                        .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "承载的 Agents",
                            caption: "\(agents.count) 个 Agent 使用这个节点执行"
                        )
                        if agents.isEmpty {
                            Text("这个节点暂时没有注册 Agent。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(17)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .hibroPanel()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(agents) { agent in
                                    HStack(spacing: 12) {
                                        Image(systemName: "cpu")
                                            .foregroundStyle(
                                                HibroTheme.engineColor(agent.engine)
                                            )
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(agent.name)
                                                .font(.subheadline.weight(.semibold))
                                            Text(agent.engine)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        StatusPill(status: agent.status)
                                    }
                                    .padding(14)
                                    if agent.id != agents.last?.id {
                                        Divider().padding(.leading, 42)
                                    }
                                }
                            }
                            .hibroPanel()
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: 850, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "找不到节点",
                    message: "它可能已断开或被移除，请刷新后重试。"
                )
            }
        }
        .navigationTitle(node?.name ?? "节点详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension CoreNode {
    var platformDescription: String {
        let platformName = switch platform?.lowercased() {
        case "darwin": "macOS"
        case "linux": "Linux"
        case "windows": "Windows"
        case .some(let value): value.capitalized
        case .none: "未知平台"
        }
        if let arch, !arch.isEmpty {
            return "\(platformName) · \(arch)"
        }
        return platformName
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
