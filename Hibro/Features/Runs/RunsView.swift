import SwiftUI

struct RunsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter = "all"
    @State private var showingComposer = false

    var body: some View {
        Group {
            if filteredRuns.isEmpty {
                EmptyStateView(
                    symbol: "play.circle",
                    title: "没有运行记录",
                    message: "向 Agent 发起任务后，状态和结果会显示在这里。"
                )
            } else {
                List(filteredRuns) { run in
                    NavigationLink {
                        RunDetailView(runID: run.id)
                    } label: {
                        RunRow(run: run)
                            .padding(.vertical, 6)
                    }
                    .listRowBackground(
                        model.highlightedRunID == run.id
                            ? HibroTheme.accent.opacity(0.07)
                            : Color.clear
                    )
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("运行")
        .searchable(text: $search, prompt: "搜索任务、Agent 或 Run ID")
        .safeAreaInset(edge: .top) {
            Picker("状态", selection: $filter) {
                Text("全部").tag("all")
                Text("进行中").tag("active")
                Text("已完成").tag("completed")
                Text("失败").tag("failed")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingComposer = true
                } label: {
                    Label("发起运行", systemImage: "play.fill")
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            RunComposerSheet()
        }
    }

    private var filteredRuns: [CoreRun] {
        model.runs.filter { run in
            let stateMatch: Bool = switch filter {
            case "active": ["requested", "accepted", "queued", "running", "cancelling"].contains(run.status)
            case "completed": run.status == "completed"
            case "failed": ["failed", "timed_out"].contains(run.status)
            default: true
            }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatch = query.isEmpty
                || run.prompt.localizedCaseInsensitiveContains(query)
                || run.id.localizedCaseInsensitiveContains(query)
                || model.agentName(run.agentId).localizedCaseInsensitiveContains(query)
            return stateMatch && searchMatch
        }
    }
}

private struct RunRow: View {
    @Environment(AppModel.self) private var model
    let run: CoreRun

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: run.status == "running" ? "waveform" : "play.fill")
                .foregroundStyle(HibroTheme.statusColor(run.status))
                .frame(width: 40, height: 40)
                .background(
                    HibroTheme.statusColor(run.status).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            VStack(alignment: .leading, spacing: 5) {
                Text(run.prompt)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text("\(model.agentName(run.agentId)) · \(DateText.relative(run.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(status: run.status)
        }
    }
}

struct RunDetailView: View {
    @Environment(AppModel.self) private var model
    let runID: String
    @State private var confirmingCancel = false

    private var run: CoreRun? {
        model.runs.first(where: { $0.id == runID })
    }

    private var runArtifacts: [CoreArtifact] {
        model.artifacts.filter { $0.coreRunId == runID }
    }

    private var relatedConversation: CoreConversation? {
        model.conversations.first { $0.activeRunId == runID }
            ?? model.conversationDetailsByID.values.first {
                detail in
                detail.messages.contains { $0.runId == runID }
                    || detail.activities.contains { $0.runId == runID }
            }?.conversation
    }

    private var decisions: [InboxItem] {
        model.inboxItems.filter {
            $0.runID == runID && $0.requiresAttention
        }
    }

    private var runEvents: [CoreRunEvent] {
        (model.runEventsByID[runID] ?? [])
            .sorted { $0.sequence < $1.sequence }
    }

    var body: some View {
        ScrollView {
            if let run {
                VStack(alignment: .leading, spacing: 22) {
                    goalHeader(run)
                    if !decisions.isEmpty {
                        decisionBanner
                    }
                    lifecycle(run)
                    eventTimeline
                    collaborators(run)
                    outcome(run)
                    artifacts
                    technicalDetails(run)
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "找不到运行",
                    message: "它可能已被清理，请刷新后重试。"
                )
            }
        }
        .navigationTitle("运行详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let run, run.isActive {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        confirmingCancel = true
                    } label: {
                        Label("取消", systemImage: "stop.fill")
                    }
                }
            }
        }
        .task(id: runID) {
            await model.openRun(runID)
        }
        .confirmationDialog(
            "确认停止这次运行？",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("停止运行", role: .destructive) {
                Task { await model.cancelRun(runID) }
            }
            Button("继续运行", role: .cancel) {}
        } message: {
            Text("Agent 当前正在执行的工作会被取消。")
        }
    }

    private func goalHeader(_ run: CoreRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("目标", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HibroTheme.cyan)
                Spacer()
                StatusPill(status: run.status)
            }
            Text(run.prompt)
                .font(.title2.bold())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Label(model.agentName(run.agentId), systemImage: "cpu")
                Text("·")
                Text(DateText.relative(run.updatedAt))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .hibroPanel()
    }

    private var decisionBanner: some View {
        NavigationLink {
            InboxItemDetailView(itemID: decisions[0].id)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(HibroTheme.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(decisions.count) 项决定等待处理")
                        .font(.headline)
                    Text(decisions[0].title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                HibroTheme.orange.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(HibroTheme.orange.opacity(0.24))
            }
        }
        .buttonStyle(.plain)
    }

    private func lifecycle(_ run: CoreRun) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "执行流程",
                caption: "基于现有 Run 状态还原目标的生命周期"
            )
            VStack(spacing: 0) {
                ForEach(Array(run.lifecycle.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 13) {
                        VStack(spacing: 0) {
                            Image(systemName: step.state.symbol)
                                .foregroundStyle(step.state.color)
                                .frame(width: 28, height: 28)
                                .background(
                                    step.state.color.opacity(0.12),
                                    in: Circle()
                                )
                            if index < run.lifecycle.count - 1 {
                                Rectangle()
                                    .fill(HibroTheme.border)
                                    .frame(width: 2, height: 30)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                            Text(step.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                        Spacer()
                    }
                }
            }
            .padding(18)
            .hibroPanel()
        }
    }

    @ViewBuilder
    private var eventTimeline: some View {
        if !runEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "实时事件",
                    caption: "Core 记录的运行、工具调用和审批轨迹"
                )
                VStack(spacing: 0) {
                    ForEach(runEvents) { event in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: event.symbol)
                                .foregroundStyle(event.color)
                                .frame(width: 30, height: 30)
                                .background(
                                    event.color.opacity(0.12),
                                    in: Circle()
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.displayTitle)
                                    .font(.subheadline.weight(.semibold))
                                if let detail = event.displayDetail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Text(DateText.full(event.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        if event.id != runEvents.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .hibroPanel()
            }
        }
    }

    private func collaborators(_ run: CoreRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "协作",
                caption: "执行资源和沟通上下文"
            )
            HStack(spacing: 13) {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundStyle(HibroTheme.engineColor(
                        model.agents.first(where: { $0.id == run.agentId })?.engine ?? ""
                    ))
                    .frame(width: 46, height: 46)
                    .background(HibroTheme.panelStrong, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.agentName(run.agentId))
                        .font(.headline)
                    Text("\(model.nodeName(run.nodeId)) · 主要执行者")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let relatedConversation {
                    NavigationLink {
                        ConversationDetailView(conversationID: relatedConversation.id)
                    } label: {
                        Label("对话", systemImage: "bubble.left")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .hibroPanel()
        }
    }

    @ViewBuilder
    private func outcome(_ run: CoreRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "结果",
                caption: run.isActive ? "执行中的状态会实时更新" : "本次目标的最终交付"
            )
            if let result = run.result?.nilIfBlank {
                Text(result)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .hibroPanel()
            } else if run.isActive {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Agent 正在推进目标")
                            .font(.headline)
                        Text("有结果或需要决定时，Hibro 会更新收件箱。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hibroPanel()
            } else {
                Text(runErrorMessage(run) ?? "这次运行没有返回可展示的文本结果。")
                    .foregroundStyle(run.status == "completed" ? .secondary : HibroTheme.danger)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hibroPanel()
            }
        }
    }

    @ViewBuilder
    private var artifacts: some View {
        if !runArtifacts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "产出",
                    caption: "\(runArtifacts.count) 项文件或报告"
                )
                VStack(spacing: 0) {
                    ForEach(runArtifacts) { artifact in
                        NavigationLink {
                            ArtifactDetailView(artifact: artifact)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.richtext")
                                    .foregroundStyle(HibroTheme.orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(artifact.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(ByteCountFormatter.string(
                                        fromByteCount: Int64(artifact.sizeBytes),
                                        countStyle: .file
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                        }
                        .buttonStyle(.plain)
                        if artifact.id != runArtifacts.last?.id {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
                .hibroPanel()
            }
        }
    }

    private func technicalDetails(_ run: CoreRun) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Run ID", value: run.id)
                LabeledContent("Node", value: model.nodeName(run.nodeId))
                LabeledContent("创建时间", value: DateText.full(run.createdAt))
                LabeledContent("开始时间", value: DateText.full(run.startedAt))
                LabeledContent("结束时间", value: DateText.full(run.finishedAt))
                if let key = run.sessionKey {
                    LabeledContent("会话键", value: key)
                }
            }
            .font(.caption)
            .padding(.top, 12)
            .textSelection(.enabled)
        } label: {
            Label("技术信息", systemImage: "info.circle")
                .font(.headline)
        }
        .padding(18)
        .hibroPanel()
    }

    private func runErrorMessage(_ run: CoreRun) -> String? {
        guard let error = run.error else { return nil }
        if case .string(let message)? = error["message"] {
            return message
        }
        return nil
    }
}

private extension RunLifecycleState {
    var symbol: String {
        switch self {
        case .pending: "circle"
        case .active: "waveform"
        case .completed: "checkmark"
        case .failed: "xmark"
        }
    }

    var color: Color {
        switch self {
        case .pending: .secondary
        case .active: HibroTheme.cyan
        case .completed: HibroTheme.accent
        case .failed: HibroTheme.danger
        }
    }
}

private extension CoreRunEvent {
    var displayTitle: String {
        if let approvalRequest {
            return approvalRequest.title
        }
        switch type {
        case "run.accepted": return "Node 已接受运行"
        case "run.started", "engine.started": return "Agent 开始执行"
        case "run.completed", "engine.completed": return "运行完成"
        case "run.failed", "engine.failed": return "运行失败"
        case "engine.approval.resolved": return "审批已处理"
        case "artifact.created": return "生成产出"
        default:
            return type
                .replacingOccurrences(of: ".", with: " · ")
        }
    }

    var displayDetail: String? {
        if let approvalRequest {
            return approvalRequest.detail
        }
        for key in ["message", "detail", "status", "command", "externalId"] {
            if let value = payload[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    var symbol: String {
        if type.contains("approval") { return "hand.raised.fill" }
        if type.contains("failed") || type.contains("error") {
            return "exclamationmark.triangle.fill"
        }
        if type.contains("completed") { return "checkmark.circle.fill" }
        if type.contains("artifact") { return "doc.fill" }
        return "waveform.path.ecg"
    }

    var color: Color {
        if type.contains("approval") { return HibroTheme.orange }
        if type.contains("failed") || type.contains("error") {
            return HibroTheme.danger
        }
        if type.contains("completed") { return HibroTheme.accent }
        return HibroTheme.cyan
    }
}

struct RunComposerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var agentID: String
    @State private var prompt = ""
    @State private var sessionKey = ""
    @State private var freshSession = false

    init(defaultAgentID: String? = nil) {
        _agentID = State(initialValue: defaultAgentID ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("你想完成什么？") {
                    TextField("说明目标、约束和期望产出", text: $prompt, axis: .vertical)
                        .lineLimit(5...10)
                }
                Section("执行方式") {
                    Picker("执行 Agent", selection: $agentID) {
                        ForEach(model.agents.filter(\.enabled)) { agent in
                            Text(agent.name).tag(agent.id)
                        }
                    }
                    LabeledContent("策略", value: "立即执行")
                }
                Section {
                    DisclosureGroup("高级选项") {
                        TextField("会话键（可选）", text: $sessionKey)
                            .textInputAutocapitalization(.never)
                        Toggle("强制创建新会话", isOn: $freshSession)
                    }
                }
            }
            .navigationTitle("新任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") {
                        Task {
                            if await model.createRun(
                                agentID: agentID,
                                prompt: prompt,
                                sessionKey: sessionKey,
                                freshSession: freshSession
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(
                        agentID.isEmpty
                            || prompt.nilIfBlank == nil
                            || model.isWorking
                    )
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if agentID.isEmpty {
                agentID = model.agents.first {
                    $0.enabled && $0.status == "idle"
                }?.id ?? model.agents.first(where: \.enabled)?.id ?? ""
            }
        }
    }
}
