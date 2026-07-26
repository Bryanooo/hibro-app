import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showingComposer = false

    private var attentionItems: [InboxItem] {
        model.inboxItems.filter(\.requiresAttention)
    }

    private var activeRuns: [CoreRun] {
        model.runs.filter(\.isActive)
    }

    private var recentOutcomes: [InboxItem] {
        model.inboxItems.filter { $0.kind == .completed }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                attention
                activeWork
                recentOutcomesSection
                systemHealth
            }
            .padding(22)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingComposer = true
                } label: {
                    Label("新任务", systemImage: "plus")
                }
                Button {
                    Task { await model.refreshFromUser() }
                } label: {
                    if model.isWorking {
                        ProgressView()
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isWorking)
            }
        }
        .sheet(isPresented: $showingComposer) {
            RunComposerSheet()
        }
        .refreshable { await model.refreshFromUser() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(greeting)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                    .accessibilityIdentifier("home.greeting")
                Text(summary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.section = .inbox
            } label: {
                VStack(spacing: 3) {
                    Text("\(attentionItems.count)")
                        .font(.title2.bold())
                    Text("待处理")
                        .font(.caption2)
                }
                .foregroundStyle(attentionItems.isEmpty ? .secondary : HibroTheme.orange)
                .frame(width: 66, height: 58)
                .background(
                    (attentionItems.isEmpty ? Color.secondary : HibroTheme.orange)
                        .opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 15)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var attention: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                SectionHeader(
                    title: "需要你的决定",
                    caption: "审批、问题和失败任务集中在这里"
                )
                if !attentionItems.isEmpty {
                    Button("查看全部") { model.section = .inbox }
                        .font(.subheadline.weight(.semibold))
                }
            }

            if attentionItems.isEmpty {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(HibroTheme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("现在没有待处理事项")
                            .font(.headline)
                        Text("Agent 会继续工作，有需要时再来找你。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hibroPanel()
            } else {
                VStack(spacing: 0) {
                    ForEach(attentionItems.prefix(3)) { item in
                        NavigationLink {
                            InboxItemDetailView(itemID: item.id)
                        } label: {
                            InboxItemRow(item: item)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if item.id != attentionItems.prefix(3).last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .hibroPanel()
            }
        }
    }

    @ViewBuilder
    private var activeWork: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "正在进行",
                caption: "围绕目标查看执行进度，而不是盯着 Agent 状态"
            )
            if activeRuns.isEmpty {
                VStack(spacing: 14) {
                    EmptyStateView(
                        symbol: "moon.zzz",
                        title: "当前没有运行中的任务",
                        message: "创建一个目标，Hibro 会安排 Agent 执行。"
                    )
                    Button {
                        showingComposer = true
                    } label: {
                        Label("开始新任务", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HibroTheme.accent)
                    .foregroundStyle(.black)
                }
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, minHeight: 180)
                .hibroPanel()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(activeRuns) { run in
                        NavigationLink {
                            RunDetailView(runID: run.id)
                        } label: {
                            ActiveRunCard(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentOutcomesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "最近完成",
                caption: "Agent 已交付的结果"
            )
            if recentOutcomes.isEmpty {
                Text("完成的任务会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hibroPanel()
            } else {
                VStack(spacing: 0) {
                    ForEach(recentOutcomes.prefix(4)) { item in
                        NavigationLink {
                            InboxItemDetailView(itemID: item.id)
                        } label: {
                            InboxItemRow(item: item)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        if item.id != recentOutcomes.prefix(4).last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .hibroPanel()
            }
        }
    }

    private var systemHealth: some View {
        let online = model.nodes.filter { $0.status == "online" }.count
        return HStack(spacing: 13) {
            Image(systemName: online == model.nodes.count ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .foregroundStyle(online == model.nodes.count ? HibroTheme.accent : HibroTheme.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("系统状态")
                    .font(.subheadline.weight(.semibold))
                Text("\(online)/\(model.nodes.count) Nodes 在线 · \(model.agents.count) Agents 可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let lastRefreshAt = model.lastRefreshAt {
                Text(lastRefreshAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        if let first = attentionItems.first {
            return "有 \(attentionItems.count) 件事需要处理，首先是“\(first.title)”。"
        }
        if !activeRuns.isEmpty {
            return "\(activeRuns.count) 个目标正在推进，目前无需你介入。"
        }
        return "所有事项都已处理，可以开始一个新目标。"
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let prefix = hour < 6 ? "夜深了" : hour < 12 ? "早上好" : hour < 18 ? "下午好" : "晚上好"
        return "\(prefix)，\(model.greetingName)"
    }
}

private struct ActiveRunCard: View {
    @Environment(AppModel.self) private var model
    let run: CoreRun

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("正在执行", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HibroTheme.cyan)
                Spacer()
                StatusPill(status: run.status)
            }
            Text(run.prompt)
                .font(.headline)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                ProgressView()
                    .tint(HibroTheme.cyan)
                Text("等待 Core 上报下一事件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label(model.agentName(run.agentId), systemImage: "cpu")
                Spacer()
                Text(DateText.relative(run.updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .hibroPanel()
    }
}
