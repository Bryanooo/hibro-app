import SwiftUI

struct AgentsView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var engine = "all"
    @State private var conversationAgent: CoreAgent?
    @State private var runAgent: CoreAgent?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                filters
                if filteredAgents.isEmpty {
                    EmptyStateView(
                        symbol: "cpu",
                        title: "没有匹配的 Agent",
                        message: "调整搜索内容或引擎筛选。"
                    )
                    .frame(minHeight: 300)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 280), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(filteredAgents) { agent in
                            AgentCard(
                                agent: agent,
                                onConversation: { conversationAgent = agent },
                                onRun: { runAgent = agent }
                            )
                        }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 1_200, alignment: .leading)
        }
        .navigationTitle("Agents")
        .searchable(text: $search, prompt: "搜索 Agent")
        .sheet(item: $conversationAgent) { agent in
            NewConversationSheet(defaultAgentID: agent.id)
        }
        .sheet(item: $runAgent) { agent in
            RunComposerSheet(defaultAgentID: agent.id)
        }
    }

    private var filters: some View {
        Picker("引擎", selection: $engine) {
            Text("全部").tag("all")
            Text("Codex").tag("codex")
            Text("Claude").tag("claude-code")
            Text("OpenClaw").tag("openclaw")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 560)
    }

    private var filteredAgents: [CoreAgent] {
        model.agents.filter { agent in
            let matchesEngine = engine == "all" || agent.engine == engine
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || agent.name.localizedCaseInsensitiveContains(query)
                || agent.description?.localizedCaseInsensitiveContains(query) == true
            return matchesEngine && matchesSearch
        }
    }
}

private struct AgentCard: View {
    @Environment(AppModel.self) private var model
    let agent: CoreAgent
    let onConversation: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(HibroTheme.engineColor(agent.engine).opacity(0.13))
                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundStyle(HibroTheme.engineColor(agent.engine))
                }
                .frame(width: 48, height: 48)
                Spacer()
                StatusPill(status: agent.status)
            }
            VStack(alignment: .leading, spacing: 7) {
                EngineBadge(engine: agent.engine)
                Text(agent.name)
                    .font(.title3.bold())
                Text(agent.description ?? "未填写 Agent 说明")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 38, alignment: .topLeading)
            }
            Divider()
            HStack {
                Label(model.nodeName(agent.nodeId), systemImage: "server.rack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                StatusPill(status: agent.registrationStatus)
            }
            HStack {
                Button(action: onConversation) {
                    Label("对话", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HibroTheme.accent)
                .foregroundStyle(.black)
                Button(action: onRun) {
                    Label("运行", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
            }
            .disabled(!agent.enabled || agent.registrationStatus != "registered")
        }
        .padding(18)
        .hibroPanel()
    }
}

struct NewConversationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var agentID: String
    @State private var title = ""

    init(defaultAgentID: String? = nil) {
        _agentID = State(initialValue: defaultAgentID ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Agent") {
                    Picker("选择 Agent", selection: $agentID) {
                        Text("请选择").tag("")
                        ForEach(model.agents.filter(\.enabled)) { agent in
                            Text(agent.name).tag(agent.id)
                        }
                    }
                }
                Section("对话") {
                    TextField("标题（可选）", text: $title)
                }
                Section {
                    Label(
                        "对话会由 Core 路由到 Agent 所在的 Node。",
                        systemImage: "lock.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新建对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        Task {
                            if await model.createConversation(
                                agentID: agentID,
                                title: title
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(agentID.isEmpty || model.isWorking)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
