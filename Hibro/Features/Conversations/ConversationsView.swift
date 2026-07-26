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
                composer(detail)
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
                    ForEach(detail.timeline) { item in
                        switch item {
                        case .message(let message):
                            MessageBubble(message: message)
                        case .activity(let activity):
                            ActivityCard(activity: activity)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: detail.timeline.count) {
                if let last = detail.timeline.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                guard let last = detail.timeline.last else { return }
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

private struct ActivityCard: View {
    @Environment(AppModel.self) private var model
    let activity: CoreActivity
    @State private var authorizationError: String?

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
                if let approval = pendingApproval {
                    Divider()
                    Text("需要你的决定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(HibroTheme.orange)
                    ForEach(supportedDecisions(approval), id: \.self) { decision in
                        Button {
                            Task { await submit(decision) }
                        } label: {
                            Label(
                                decision.title,
                                systemImage: decision == .deny
                                    ? "xmark.circle"
                                    : "checkmark.shield"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(
                            decision == .deny
                                ? HibroTheme.danger
                                : HibroTheme.accent
                        )
                        .foregroundStyle(
                            decision == .deny ? Color.white : Color.black
                        )
                        .disabled(model.isWorking)
                    }
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
        .alert(
            "无法确认审批",
            isPresented: Binding(
                get: { authorizationError != nil },
                set: { if !$0 { authorizationError = nil } }
            )
        ) {
            Button("好") { authorizationError = nil }
        } message: {
            Text(authorizationError ?? "")
        }
    }

    private var pendingApproval: CoreApproval? {
        guard activity.type == "approval",
              activity.status == "pending",
              let approval = activity.approval,
              approval.resolvable,
              approval.decision == nil,
              !model.handledActivityIDs.contains(activity.id) else {
            return nil
        }
        return approval
    }

    private func supportedDecisions(
        _ approval: CoreApproval
    ) -> [ApprovalDecision] {
        ApprovalDecision.allCases.filter {
            approval.decisions.contains($0.rawValue)
        }
    }

    private func submit(_ decision: ApprovalDecision) async {
        if !model.isDemoMode {
            do {
                try await ApprovalAuthorizer.authorize()
            } catch {
                authorizationError = error.localizedDescription
                return
            }
        }
        _ = await model.decideApproval(
            conversationID: activity.conversationId,
            activityID: activity.id,
            decision: decision
        )
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
