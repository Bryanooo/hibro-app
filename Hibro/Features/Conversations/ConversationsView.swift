import SwiftUI

struct ConversationsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var showingNewConversation = false

    var body: some View {
        Group {
            if filteredConversations.isEmpty {
                EmptyStateView(
                    symbol: "bubble.left.and.bubble.right",
                    title: search.isEmpty ? "还没有对话" : "没有匹配的对话",
                    message: search.isEmpty
                        ? "选择一个 Agent，开始第一段对话。"
                        : "尝试其他搜索词。"
                )
            } else {
                List(filteredConversations) { conversation in
                    NavigationLink {
                        ConversationDetailView(conversationID: conversation.id)
                    } label: {
                        ConversationRow(conversation: conversation)
                            .padding(.vertical, 6)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("对话")
        .searchable(text: $search, prompt: "搜索对话或 Agent")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewConversation = true
                } label: {
                    Label("新建对话", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingNewConversation) {
            NewConversationSheet()
        }
    }

    private var filteredConversations: [CoreConversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.conversations }
        return model.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || model.agentName($0.agentId).localizedCaseInsensitiveContains(query)
        }
    }
}

struct ConversationRow: View {
    @Environment(AppModel.self) private var model
    let conversation: CoreConversation

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(HibroTheme.engineColor(conversation.engine).opacity(0.14))
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(HibroTheme.engineColor(conversation.engine))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(
                    "\(model.agentName(conversation.agentId)) · \(DateText.relative(conversation.lastMessageAt ?? conversation.updatedAt))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            StatusPill(status: conversation.status)
        }
        .contentShape(Rectangle())
    }
}

struct ConversationDetailView: View {
    @Environment(AppModel.self) private var model
    let conversationID: String
    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let detail = model.conversationDetail,
               detail.conversation.id == conversationID {
                timeline(detail)
            } else {
                ProgressView("正在加载对话…")
            }
        }
        .navigationTitle(model.conversationDetail?.conversation.title ?? "对话")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let detail = model.conversationDetail,
               detail.conversation.id == conversationID {
                VStack(spacing: 0) {
                    if let activity = pendingApproval(in: detail) {
                        PinnedApprovalBanner(activity: activity)
                        Divider()
                    }
                    composer(detail)
                }
            }
        }
        .toolbar {
            if model.conversationDetail?.conversation.activeRunId != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        Task { await model.cancelConversation() }
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                }
            }
        }
        .task(id: conversationID) {
            await model.openConversation(conversationID)
        }
    }

    private func timeline(_ detail: ConversationDetail) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 13) {
                    ConversationIdentityCard(conversation: detail.conversation)
                    ForEach(detail.focusedTimeline) { item in
                        switch item {
                        case .message(let message):
                            MessageBubble(message: message)
                        case .activity(let activity):
                            ActivityCard(activity: activity)
                        case .technicalActivities(let activities):
                            TechnicalActivityGroup(activities: activities)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: detail.focusedTimeline.count) {
                if let last = detail.focusedTimeline.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                guard let last = detail.focusedTimeline.last else { return }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func composer(_ detail: ConversationDetail) -> some View {
        let responding = detail.conversation.status == "responding"
            || detail.conversation.activeRunId != nil
        return VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    responding ? "Agent 正在响应…" : "给 Agent 发送消息",
                    text: $draft,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    HibroTheme.panelStrong,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .disabled(responding)
                Button {
                    let content = draft
                    draft = ""
                    Task {
                        if !(await model.sendMessage(content)) {
                            draft = content
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.bold())
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(HibroTheme.accent)
                .foregroundStyle(.black)
                .disabled(responding || draft.nilIfBlank == nil)
            }
            Text("消息经 Core 安全路由，执行发生在 Agent 的独立工作空间。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    private func pendingApproval(
        in detail: ConversationDetail
    ) -> CoreActivity? {
        detail.activities
            .filter {
                $0.type == "approval"
                    && $0.status == "pending"
                    && $0.approval?.resolvable == true
                    && $0.approval?.decision == nil
                    && !model.handledActivityIDs.contains($0.id)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }
}

private struct PinnedApprovalBanner: View {
    @Environment(AppModel.self) private var model
    let activity: CoreActivity

    var body: some View {
        ApprovalDecisionPanel(
            title: activity.title,
            detail: activity.detail ?? activity.approval?.reason,
            decisions: supportedDecisions,
            style: .compact,
            onDecision: submit
        )
    }

    private var supportedDecisions: [ApprovalDecision] {
        guard let approval = activity.approval else { return [] }
        let supported = ApprovalDecision.allCases.filter {
            approval.decisions.contains($0.rawValue)
        }
        return supported.isEmpty ? ApprovalDecision.allCases : supported
    }

    private func submit(_ decision: ApprovalDecision) async -> Bool {
        await model.decideApproval(
            conversationID: activity.conversationId,
            activityID: activity.id,
            decision: decision
        )
    }
}

private struct ConversationIdentityCard: View {
    @Environment(AppModel.self) private var model
    let conversation: CoreConversation

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundStyle(HibroTheme.engineColor(conversation.engine))
                .frame(width: 44, height: 44)
                .background(
                    HibroTheme.engineColor(conversation.engine).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 13)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(model.agentName(conversation.agentId)).font(.headline)
                Text("\(model.nodeName(conversation.nodeId)) · \(conversation.engine)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(status: conversation.status)
        }
        .padding(14)
        .hibroPanel()
    }
}

private struct MessageBubble: View {
    let message: CoreMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 45) }
            VStack(alignment: .leading, spacing: 7) {
                Text(message.role == "user" ? "你" : message.role == "assistant" ? "Agent" : message.role)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.content.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(message.status == "queued" ? "等待 Agent…" : "正在生成…")
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                        .font(.body)
                }
                if let error = message.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(HibroTheme.danger)
                }
            }
            .padding(13)
            .background(
                message.role == "user"
                    ? HibroTheme.accent.opacity(0.14)
                    : HibroTheme.panelStrong,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(
                        message.role == "user"
                            ? HibroTheme.accent.opacity(0.2)
                            : HibroTheme.border
                    )
            }
            if message.role != "user" { Spacer(minLength: 45) }
        }
        .id("message:\(message.id)")
    }
}

private struct TechnicalActivityGroup: View {
    let activities: [CoreActivity]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 8) {
                ForEach(activities) { activity in
                    ActivityCard(activity: activity)
                }
            }
            .padding(.top, 9)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(HibroTheme.cyan)
                Text("技术细节 · \(activities.count) 项")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(isExpanded ? "收起" : "展开")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .tint(HibroTheme.cyan)
        .padding(12)
        .background(
            HibroTheme.cyan.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 13)
        )
        .frame(maxWidth: 690)
        .id(
            "technical:\(activities.first?.id ?? "empty"):"
                + "\(activities.last?.id ?? "empty")"
        )
        .accessibilityIdentifier("conversation.technicalDetails")
    }
}

private struct ActivityCard: View {
    @Environment(AppModel.self) private var model
    let activity: CoreActivity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(activity.title)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(activity.type.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let detail = activity.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if activity.type == "approval",
                   activity.approval?.resolvable == false {
                    Label(
                        activity.approval?.reason ?? "此审批项当前为只读",
                        systemImage: "eye"
                    )
                    .font(.caption2)
                    .foregroundStyle(HibroTheme.orange)
                }
                if pendingApproval {
                    Label(
                        "等待你的决定（操作区已固定在底部）",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HibroTheme.orange)
                } else if activity.type == "approval",
                          let decision = activity.approval?.decision {
                    Label(
                        ApprovalDecision(rawValue: decision)?.title ?? decision,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HibroTheme.accent)
                } else if activity.type == "approval",
                          model.handledActivityIDs.contains(activity.id) {
                    Label(
                        "决定已提交",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HibroTheme.accent)
                }
            }
        }
        .padding(11)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        .frame(maxWidth: 690)
        .id("activity:\(activity.id)")
    }

    private var pendingApproval: Bool {
        guard activity.type == "approval",
              activity.status == "pending",
              let approval = activity.approval,
              approval.resolvable,
              approval.decision == nil,
              !model.handledActivityIDs.contains(activity.id) else {
            return false
        }
        return true
    }

    private var symbol: String {
        switch activity.type {
        case "thinking": "brain"
        case "tool_call": "wrench.and.screwdriver"
        case "tool_result": "checkmark.rectangle"
        case "approval": "hand.raised"
        case "error": "exclamationmark.triangle"
        default: "waveform"
        }
    }

    private var color: Color {
        switch activity.type {
        case "thinking": HibroTheme.violet
        case "approval": HibroTheme.orange
        case "error": HibroTheme.danger
        default: HibroTheme.cyan
        }
    }
}
