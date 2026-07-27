import SwiftUI

struct RunsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter = "all"
    @State private var showingComposer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                taskSummary
                filters
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "任务列表",
                        caption: taskListCaption
                    )
                    if filteredRuns.isEmpty {
                        EmptyStateView(
                            symbol: search.isEmpty ? "checklist" : "magnifyingglass",
                            title: search.isEmpty ? "还没有任务" : "没有匹配的任务",
                            message: search.isEmpty
                                ? "向 Agent 提交目标后，进度和结果会显示在这里。"
                                : "尝试其他搜索词或状态筛选。"
                        )
                        .frame(maxWidth: .infinity, minHeight: 230)
                        .hibroPanel()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredRuns) { run in
                                NavigationLink {
                                    RunDetailView(runID: run.id)
                                } label: {
                                    RunRow(run: run)
                                        .padding(16)
                                        .background(
                                            model.highlightedRunID == run.id
                                                ? HibroTheme.accent.opacity(0.07)
                                                : Color.clear
                                        )
                                        .hibroPanel()
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
        .navigationTitle("任务")
        .searchable(text: $search, prompt: "搜索目标、Agent 或任务 ID")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingComposer = true
                } label: {
                    Label("新任务", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingComposer) {
            RunComposerSheet()
        }
    }

    private var taskSummary: some View {
        HStack(spacing: 0) {
            TaskMetric(
                value: model.runs.filter(\.isActive).count,
                title: "进行中",
                color: HibroTheme.cyan
            )
            Divider().frame(height: 42)
            TaskMetric(
                value: model.runs.filter { $0.status == "completed" }.count,
                title: "已完成",
                color: HibroTheme.accent
            )
            Divider().frame(height: 42)
            TaskMetric(
                value: model.runs.filter {
                    ["failed", "timed_out"].contains($0.status)
                }.count,
                title: "需关注",
                color: HibroTheme.danger
            )
        }
        .padding(.vertical, 16)
        .hibroPanel()
    }

    private var filters: some View {
        Picker("任务状态", selection: $filter) {
            Text("全部").tag("all")
            Text("进行中").tag("active")
            Text("已完成").tag("completed")
            Text("需关注").tag("failed")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 560)
        .accessibilityIdentifier("task-status-filter")
    }

    private var taskListCaption: String {
        if filter == "all" {
            return "\(filteredRuns.count) 个目标，按最近更新排序"
        }
        return "当前筛选下共 \(filteredRuns.count) 个目标"
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
        .sorted { $0.updatedAt > $1.updatedAt }
    }
}

private struct TaskMetric: View {
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

private struct RunRow: View {
    @Environment(AppModel.self) private var model
    let run: CoreRun

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: run.status == "running" ? "waveform" : "checkmark.square")
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
        .contentShape(Rectangle())
    }
}

struct RunDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let runID: String
    @State private var confirmingCancel = false
    @State private var confirmingRetry = false
    @State private var section = RunDetailSection.overview

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
                    sectionPicker
                    sectionContent(run)
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
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let run, run.isActive {
                    Button(role: .destructive) {
                        confirmingCancel = true
                    } label: {
                        Label("取消", systemImage: "stop.fill")
                    }
                } else if let run, run.canRetry {
                    Button {
                        confirmingRetry = true
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .task(id: runID) {
            await model.openRun(runID)
        }
        .confirmationDialog(
            "确认停止这个任务？",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("停止任务", role: .destructive) {
                Task { await model.cancelRun(runID) }
            }
            Button("继续任务", role: .cancel) {}
        } message: {
            Text("Agent 当前正在执行的工作会被取消。")
        }
        .confirmationDialog(
            "使用相同目标重新执行？",
            isPresented: $confirmingRetry,
            titleVisibility: .visible
        ) {
            Button("重新执行") {
                guard let run else { return }
                Task {
                    if await model.retryRun(run) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将沿用原来的 Agent、目标和会话设置，创建一个新任务。")
        }
    }

    private var sectionPicker: some View {
        Picker("运行详情内容", selection: $section) {
            ForEach(RunDetailSection.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("run-detail-sections")
    }

    @ViewBuilder
    private func sectionContent(_ run: CoreRun) -> some View {
        switch section {
        case .overview:
            if !decisions.isEmpty {
                decisionBanner
            }
            lifecycle(run)
            collaborators(run)
            outcome(run)
            technicalDetails(run)
        case .timeline:
            if runEvents.isEmpty {
                sectionEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: "还没有运行事件",
                    message: "Core 上报的执行、工具调用和审批轨迹会显示在这里。"
                )
            } else {
                eventTimeline
            }
        case .conversation:
            conversationSection
        case .artifacts:
            if runArtifacts.isEmpty {
                sectionEmptyState(
                    symbol: "doc",
                    title: "还没有产出",
                    message: "Agent 生成的文件、报告和补丁会集中显示在这里。"
                )
            } else {
                artifacts
            }
        }
    }

    private func sectionEmptyState(
        symbol: String,
        title: String,
        message: String
    ) -> some View {
        EmptyStateView(symbol: symbol, title: title, message: message)
            .frame(maxWidth: .infinity, minHeight: 260)
            .hibroPanel()
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
    private var conversationSection: some View {
        if let relatedConversation {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "关联对话",
                    caption: "查看目标执行期间的人与 Agent 沟通"
                )
                NavigationLink {
                    ConversationDetailView(conversationID: relatedConversation.id)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title2)
                            .foregroundStyle(HibroTheme.violet)
                            .frame(width: 46, height: 46)
                            .background(
                                HibroTheme.violet.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 13)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(relatedConversation.title)
                                .font(.headline)
                            Text(
                                "\(model.agentName(relatedConversation.agentId)) · \(DateText.relative(relatedConversation.updatedAt))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .hibroPanel()
                }
                .buttonStyle(.plain)
            }
        } else {
            sectionEmptyState(
                symbol: "bubble.left.and.bubble.right",
                title: "没有关联对话",
                message: "这个任务没有可展示的会话上下文。"
            )
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
            } else if let failure = run.failurePresentation {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        failure.title,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(HibroTheme.danger)
                    Text(failure.message)
                    Text(failure.suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        confirmingRetry = true
                    } label: {
                        Label("使用相同目标重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HibroTheme.accent)
                    .foregroundStyle(.black)
                    .disabled(model.isWorking)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hibroPanel()
            } else {
                Text("这个任务没有返回可展示的文本结果。")
                    .foregroundStyle(.secondary)
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
                if let failure = run.failurePresentation,
                   let detail = failure.technicalDetail {
                    LabeledContent("原始错误", value: detail)
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

}

private enum RunDetailSection: String, CaseIterable, Identifiable {
    case overview
    case timeline
    case conversation
    case artifacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .timeline: "时间线"
        case .conversation: "对话"
        case .artifacts: "产出"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .timeline: "clock.arrow.circlepath"
        case .conversation: "bubble.left.and.bubble.right"
        case .artifacts: "doc"
        }
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
        case "run.completed", "engine.completed": return "任务完成"
        case "run.failed", "engine.failed": return "任务失败"
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
