import Foundation

enum DemoData {
    private static let now = ISO8601DateFormatter().string(from: Date())
    private static let earlier = ISO8601DateFormatter().string(
        from: Date().addingTimeInterval(-1_800)
    )

    static let agents: [CoreAgent] = [
        CoreAgent(
            id: "agent_codex_demo",
            nodeId: "node_studio_demo",
            localAgentId: "agt_codex",
            name: "Codex 开发助手",
            description: "实现功能、修复问题并验证代码",
            engine: "codex",
            enabled: true,
            status: "idle",
            registrationStatus: "registered",
            createdAt: earlier,
            updatedAt: now
        ),
        CoreAgent(
            id: "agent_claude_demo",
            nodeId: "node_studio_demo",
            localAgentId: "agt_claude",
            name: "Claude 分析助手",
            description: "阅读资料、梳理需求和生成方案",
            engine: "claude-code",
            enabled: true,
            status: "running",
            registrationStatus: "registered",
            createdAt: earlier,
            updatedAt: now
        ),
        CoreAgent(
            id: "agent_openclaw_demo",
            nodeId: "node_home_demo",
            localAgentId: "agt_openclaw",
            name: "OpenClaw 自动化",
            description: "处理日常自动化任务",
            engine: "openclaw",
            enabled: true,
            status: "idle",
            registrationStatus: "registered",
            createdAt: earlier,
            updatedAt: now
        )
    ]

    static let conversations: [CoreConversation] = [
        CoreConversation(
            id: "conv_demo_review",
            title: "检查 Core 部署状态",
            nodeId: "node_studio_demo",
            agentId: "agent_codex_demo",
            localAgentId: "agt_codex",
            engine: "codex",
            status: "idle",
            source: "core",
            createdBy: "usr_demo",
            engineSessionId: "session_demo",
            activeRunId: nil,
            lastMessageAt: now,
            createdAt: earlier,
            updatedAt: now
        ),
        CoreConversation(
            id: "conv_demo_plan",
            title: "整理 Hibro 产品计划",
            nodeId: "node_studio_demo",
            agentId: "agent_claude_demo",
            localAgentId: "agt_claude",
            engine: "claude-code",
            status: "responding",
            source: "core",
            createdBy: "usr_demo",
            engineSessionId: nil,
            activeRunId: "run_demo_active",
            lastMessageAt: now,
            createdAt: earlier,
            updatedAt: now
        )
    ]

    static let bootstrap = BootstrapResponse(
        apiVersion: "2026-07-25",
        user: CoreUser(
            id: "usr_demo",
            username: "bryan",
            displayName: "Bryan",
            roles: ["owner"],
            status: "active"
        ),
        permissions: ["core:read", "conversation:write", "agent:run"],
        scopes: ["hibro.read", "hibro.run"],
        overview: CoreOverview(
            nodes: .init(total: 2, online: 2, registered: nil),
            agents: .init(total: 3, online: nil, registered: 3),
            teams: 1,
            runs: .init(total: 24, active: 1, completed: 22, failed: 1),
            artifacts: 18
        ),
        nodes: [
            CoreNode(
                id: "node_studio_demo",
                name: "Studio Mac",
                status: "online",
                version: "0.1.0",
                platform: "darwin",
                arch: "arm64",
                lastSeenAt: now,
                connectedAt: earlier,
                capabilities: nil
            ),
            CoreNode(
                id: "node_home_demo",
                name: "Home Server",
                status: "online",
                version: "0.1.0",
                platform: "linux",
                arch: "arm64",
                lastSeenAt: now,
                connectedAt: earlier,
                capabilities: nil
            )
        ],
        agents: agents,
        teams: [
            CoreTeam(
                id: "team_demo",
                name: "产品研发",
                description: "规划、开发与自动化",
                agentIds: agents.map(\.id),
                createdAt: earlier,
                updatedAt: now
            )
        ],
        conversations: conversations,
        capabilities: ["realtime": .string("sse")],
        serverTime: now
    )

    static let runs: [CoreRun] = [
        CoreRun(
            id: "run_demo_active",
            commandId: "command_demo_active",
            nodeId: "node_studio_demo",
            agentId: "agent_claude_demo",
            localAgentId: "agt_claude",
            localRunId: "local_active",
            status: "running",
            prompt: "整理 Hibro App 第一版需要完成的功能与优先级",
            sessionKey: "hibro-product",
            result: nil,
            error: nil,
            requestedBy: "usr_demo",
            createdAt: now,
            updatedAt: now,
            startedAt: now,
            finishedAt: nil
        ),
        CoreRun(
            id: "run_demo_done",
            commandId: "command_demo_done",
            nodeId: "node_studio_demo",
            agentId: "agent_codex_demo",
            localAgentId: "agt_codex",
            localRunId: "local_done",
            status: "completed",
            prompt: "检查 Core 的 Docker 部署配置",
            sessionKey: nil,
            result: "部署配置检查完成，健康检查与数据卷均正常。",
            error: nil,
            requestedBy: "usr_demo",
            createdAt: earlier,
            updatedAt: now,
            startedAt: earlier,
            finishedAt: now
        )
    ]

    static let artifacts: [CoreArtifact] = [
        CoreArtifact(
            id: "artifact_demo",
            coreRunId: "run_demo_done",
            nodeId: "node_studio_demo",
            localArtifactId: "local_artifact",
            title: "Core 部署检查报告",
            contentType: "text/markdown",
            sizeBytes: 2_480,
            content: """
            # Core 部署检查

            - 健康检查正常
            - SQLite 数据卷已持久化
            - WebSocket Endpoint 可用
            - 建议正式环境启用 HTTPS 与安全 Cookie
            """,
            sha256: nil,
            createdAt: now
        ),
        CoreArtifact(
            id: "artifact_demo_image",
            coreRunId: "run_demo_done",
            nodeId: "node_studio_demo",
            localArtifactId: "local_artifact_image",
            title: "Hibro 状态图",
            contentType: "image/png",
            sizeBytes: 70,
            content: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLqkwAAAABJRU5ErkJggg==",
            previewKind: "image",
            fileName: "hibro-status.png",
            encoding: "base64",
            transferStatus: "available",
            sha256: nil,
            createdAt: now
        )
    ]

    static let conversationDetails: [String: ConversationDetail] = {
        Dictionary(
            uniqueKeysWithValues: conversations.map { conversation in
                let isPlanning = conversation.id == "conv_demo_plan"
                let focalActivity = isPlanning
                    ? CoreActivity(
                        id: "activity_demo_question",
                        conversationId: conversation.id,
                        messageId: nil,
                        runId: "run_demo_active",
                        type: "question",
                        status: "pending",
                        title: "是否保留 v1 API 兼容性？",
                        detail: "迁移方案需要确认是否继续兼容旧客户端。",
                        payload: nil,
                        approval: nil,
                        createdAt: now,
                        updatedAt: now
                    )
                    : CoreActivity(
                        id: "activity_demo_approval",
                        conversationId: conversation.id,
                        messageId: nil,
                        runId: "run_demo_done",
                        type: "approval",
                        status: "pending",
                        title: "部署 Core 更新",
                        detail: "变更已通过检查，准备部署到生产环境。",
                        payload: nil,
                        approval: CoreApproval(
                            provider: "codex",
                            externalId: "approval_demo",
                            decisions: ["allow_once", "allow_always", "deny"],
                            decision: nil,
                            resolvable: true,
                            expiresAt: nil,
                            reason: "部署操作需要人工确认"
                        ),
                        createdAt: now,
                        updatedAt: now
                    )
                let technicalActivities = [
                    CoreActivity(
                        id: "activity_demo_thinking_\(conversation.id)",
                        conversationId: conversation.id,
                        messageId: nil,
                        runId: isPlanning ? "run_demo_active" : "run_demo_done",
                        type: "thinking",
                        status: "completed",
                        title: "分析任务上下文",
                        detail: "读取当前项目状态并梳理下一步计划。",
                        payload: nil,
                        approval: nil,
                        createdAt: earlier,
                        updatedAt: earlier
                    ),
                    CoreActivity(
                        id: "activity_demo_tool_call_\(conversation.id)",
                        conversationId: conversation.id,
                        messageId: nil,
                        runId: isPlanning ? "run_demo_active" : "run_demo_done",
                        type: "tool_call",
                        status: "completed",
                        title: "读取项目文件",
                        detail: "检查配置、实现和测试状态。",
                        payload: nil,
                        approval: nil,
                        createdAt: earlier,
                        updatedAt: earlier
                    ),
                    CoreActivity(
                        id: "activity_demo_tool_result_\(conversation.id)",
                        conversationId: conversation.id,
                        messageId: nil,
                        runId: isPlanning ? "run_demo_active" : "run_demo_done",
                        type: "tool_result",
                        status: "completed",
                        title: "项目文件读取完成",
                        detail: "已获得生成结论所需的上下文。",
                        payload: nil,
                        approval: nil,
                        createdAt: earlier,
                        updatedAt: earlier
                    ),
                ]
                let detail = ConversationDetail(
                    conversation: conversation,
                    messages: [
                        CoreMessage(
                            id: "msg_demo_user_\(conversation.id)",
                            conversationId: conversation.id,
                            role: "user",
                            content: isPlanning
                                ? "整理 App 下一阶段计划，遇到需要决定的地方告诉我。"
                                : "检查一下 Core 当前的部署状态和安全配置。",
                            status: "completed",
                            runId: isPlanning
                                ? "run_demo_active"
                                : "run_demo_done",
                            error: nil,
                            createdAt: earlier,
                            updatedAt: earlier
                        ),
                        CoreMessage(
                            id: "msg_demo_assistant_\(conversation.id)",
                            conversationId: conversation.id,
                            role: "assistant",
                            content: isPlanning
                                ? "计划已经梳理到 API 迁移阶段，有一项兼容策略需要确认。"
                                : "检查已经完成。服务运行正常，部署更新前需要你的批准。",
                            status: "completed",
                            runId: isPlanning
                                ? "run_demo_active"
                                : "run_demo_done",
                            error: nil,
                            createdAt: now,
                            updatedAt: now
                        )
                    ],
                    activities: technicalActivities + [focalActivity]
                )
                return (conversation.id, detail)
            }
        )
    }()

    static func conversationDetail(id: String) -> ConversationDetail? {
        conversationDetails[id]
    }
}
