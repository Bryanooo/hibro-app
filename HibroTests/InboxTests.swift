import XCTest
@testable import Hibro

final class InboxTests: XCTestCase {
    func testConnectivityRequiresThreeAvailabilityFailuresBeforeOffline() {
        var connectivity = CoreConnectivity()
        connectivity.recordAPISuccess()

        connectivity.recordAPIFailure(message: "第一次失败")
        XCTAssertEqual(connectivity.apiState, .degraded)
        XCTAssertEqual(connectivity.presentationState, .degraded)

        connectivity.recordAPIFailure(message: "第二次失败")
        XCTAssertEqual(connectivity.apiState, .degraded)

        connectivity.recordAPIFailure(message: "第三次失败")
        XCTAssertEqual(connectivity.apiState, .offline)
        XCTAssertEqual(connectivity.presentationState, .offline)
    }

    func testConnectivitySuccessClearsFailureHistory() {
        var connectivity = CoreConnectivity()
        connectivity.recordAPIFailure(message: "第一次失败")
        connectivity.recordAPIFailure(message: "第二次失败")
        connectivity.recordAPISuccess()

        XCTAssertEqual(connectivity.apiState, .connected)
        XCTAssertEqual(connectivity.consecutiveAPIFailures, 0)
        XCTAssertNil(connectivity.presentationMessage)
    }

    func testRealtimeStateCannotOverrideAnOfflineAPI() {
        var connectivity = CoreConnectivity()
        connectivity.recordAPIFailure(
            message: "Core 不可达",
            immediatelyOffline: true
        )
        connectivity.recordRealtimeConnected()

        XCTAssertEqual(connectivity.apiState, .offline)
        XCTAssertEqual(connectivity.realtimeState, .connected)
        XCTAssertEqual(connectivity.presentationState, .offline)
    }

    func testRealtimeReconnectDoesNotReportTheAPIAsOffline() {
        var connectivity = CoreConnectivity()
        connectivity.recordAPISuccess()
        connectivity.recordRealtimeReconnecting(message: "实时通道恢复中")

        XCTAssertEqual(connectivity.apiState, .connected)
        XCTAssertEqual(connectivity.presentationState, .reconnecting)
        XCTAssertEqual(
            connectivity.presentationMessage,
            "实时通道恢复中"
        )
    }

    func testGreetingUsesRealDisplayNameAndAvoidsGenericOwnerLabel() {
        let namedUser = CoreUser(
            id: "usr_named",
            username: "bryan",
            displayName: "Bryan",
            roles: ["owner"],
            status: "active"
        )
        let defaultOwner = CoreUser(
            id: "usr_owner",
            username: "bryan",
            displayName: "Hibro Owner",
            roles: ["owner"],
            status: "active"
        )

        XCTAssertEqual(namedUser.greetingName, "Bryan")
        XCTAssertEqual(defaultOwner.greetingName, "Bryan")
    }

    func testConversationGroupsTechnicalActivitiesWithoutHidingDecisions() throws {
        let detail = try XCTUnwrap(
            DemoData.conversationDetail(id: "conv_demo_plan")
        )
        let groups = detail.focusedTimeline.compactMap { item -> [CoreActivity]? in
            guard case .technicalActivities(let activities) = item else {
                return nil
            }
            return activities
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.map(\.type), [
            "thinking",
            "tool_call",
            "tool_result",
        ])
        XCTAssertTrue(
            detail.focusedTimeline.contains {
                guard case .activity(let activity) = $0 else { return false }
                return activity.type == "question"
            }
        )
    }

    func testInboxPrioritizesAttentionOverCompletedRuns() {
        let items = InboxBuilder.build(
            runs: DemoData.runs,
            conversationDetails: Array(DemoData.conversationDetails.values)
        )

        XCTAssertEqual(items.filter(\.requiresAttention).count, 2)
        XCTAssertTrue(items.prefix(2).allSatisfy(\.requiresAttention))
        XCTAssertTrue(items.contains { $0.kind == .approval })
        XCTAssertTrue(items.contains { $0.kind == .question })
        XCTAssertTrue(items.contains { $0.kind == .completed })
    }

    func testHandledActivityIsExcluded() {
        let items = InboxBuilder.build(
            runs: DemoData.runs,
            conversationDetails: Array(DemoData.conversationDetails.values),
            excludingActivityIDs: ["activity_demo_approval"]
        )

        XCTAssertFalse(items.contains { $0.id == "activity:activity_demo_approval" })
        XCTAssertTrue(items.contains { $0.id == "activity:activity_demo_question" })
    }

    func testRunLifecycleReflectsActiveExecution() throws {
        let run = try XCTUnwrap(
            DemoData.runs.first { $0.id == "run_demo_active" }
        )

        XCTAssertTrue(run.isActive)
        XCTAssertEqual(run.lifecycle.count, 4)
        XCTAssertEqual(run.lifecycle[2].state, .active)
        XCTAssertEqual(run.lifecycle[3].state, .pending)
    }

    func testApprovalDecisionMatchesCorePayload() {
        XCTAssertEqual(ApprovalDecision.allowOnce.rawValue, "allow_once")
        XCTAssertEqual(ApprovalDecision.allowAlways.rawValue, "allow_always")
        XCTAssertEqual(ApprovalDecision.deny.rawValue, "deny")
    }

    func testRunApprovalAppearsAndResolvedEventRemovesIt() throws {
        let run = try XCTUnwrap(
            DemoData.runs.first { $0.id == "run_demo_active" }
        )
        let requested = CoreRunEvent(
            coreRunId: run.id,
            localRunId: run.localRunId,
            sequence: 1,
            type: "engine.approval.requested",
            timestamp: "2026-07-25T16:00:00.000Z",
            payload: [
                "request": .object([
                    "externalId": .string("approval_external"),
                    "title": .string("允许执行部署命令"),
                    "command": .string("deploy production")
                ])
            ]
        )
        var items = InboxBuilder.build(
            runs: [run],
            conversationDetails: [],
            runEvents: [run.id: [requested]]
        )
        XCTAssertTrue(
            items.contains {
                $0.id == "run-approval:\(run.id):approval_external"
                    && $0.kind == .approval
            }
        )

        let resolved = CoreRunEvent(
            coreRunId: run.id,
            localRunId: run.localRunId,
            sequence: 2,
            type: "engine.approval.resolved",
            timestamp: "2026-07-25T16:01:00.000Z",
            payload: ["externalId": .string("approval_external")]
        )
        items = InboxBuilder.build(
            runs: [run],
            conversationDetails: [],
            runEvents: [run.id: [requested, resolved]]
        )
        XCTAssertFalse(
            items.contains {
                $0.id == "run-approval:\(run.id):approval_external"
            }
        )
    }

    func testCoreInboxResponseMapsRunApproval() throws {
        let data = Data(
            """
            {
              "items": [{
                "id": "run-approval:run_1:approval_1",
                "kind": "approval",
                "title": "允许执行命令",
                "summary": "npm test",
                "createdAt": "2026-07-26T12:00:00.000Z",
                "requiresAttention": true,
                "runId": "run_1",
                "conversationId": null,
                "approval": {
                  "source": "run",
                  "activityId": null,
                  "externalId": "approval_1",
                  "decisions": ["allow_once", "deny"],
                  "resolvable": true,
                  "reason": null
                }
              }],
              "serverTime": "2026-07-26T12:00:01.000Z"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            CoreInboxResponse.self,
            from: data
        )
        let item = try XCTUnwrap(
            response.items.first.flatMap(InboxItem.init(coreItem:))
        )

        XCTAssertEqual(item.kind, .approval)
        XCTAssertEqual(item.runID, "run_1")
        XCTAssertEqual(
            item.approvalSource,
            .run(externalID: "approval_1")
        )
        XCTAssertEqual(item.approvalExternalID, "approval_1")
    }

    func testCoreInboxPreservesConversationApprovalExternalIdentity() throws {
        let data = Data(
            """
            {
              "items": [{
                "id": "activity:activity_1",
                "kind": "approval",
                "title": "允许执行命令",
                "summary": "生成图片",
                "createdAt": "2026-07-26T12:00:00.000Z",
                "requiresAttention": true,
                "runId": "run_1",
                "conversationId": "conversation_1",
                "approval": {
                  "source": "conversation",
                  "activityId": "activity_1",
                  "externalId": "approval_1",
                  "decisions": ["allow_once", "deny"],
                  "resolvable": true,
                  "reason": null
                }
              }],
              "serverTime": "2026-07-26T12:00:01.000Z"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            CoreInboxResponse.self,
            from: data
        )
        let item = try XCTUnwrap(
            response.items.first.flatMap(InboxItem.init(coreItem:))
        )

        XCTAssertEqual(
            item.approvalSource,
            .conversation(activityID: "activity_1")
        )
        XCTAssertEqual(item.approvalExternalID, "approval_1")
        XCTAssertEqual(item.runID, "run_1")
    }

    @MainActor
    func testConversationDecisionImmediatelyClearsEveryApprovalSurface() async {
        let model = AppModel()
        model.loadDemo()
        model.serverInboxItems = [
            InboxItem(
                id: "activity:activity_demo_approval",
                kind: .approval,
                title: "部署 Core 更新",
                summary: "等待审批",
                createdAt: "2026-07-26T12:00:00.000Z",
                runID: "run_demo_done",
                conversationID: "conv_demo_review",
                approvalSource: .conversation(
                    activityID: "activity_demo_approval"
                ),
                approvalExternalID: "approval_demo"
            ),
            InboxItem(
                id: "run-approval:run_demo_done:approval_demo",
                kind: .approval,
                title: "部署 Core 更新",
                summary: "同一审批的 Run 入口",
                createdAt: "2026-07-26T12:00:00.000Z",
                runID: "run_demo_done",
                conversationID: "conv_demo_review",
                approvalSource: .run(externalID: "approval_demo"),
                approvalExternalID: "approval_demo"
            ),
        ]

        XCTAssertEqual(model.inboxItems.count, 2)
        let succeeded = await model.decideApproval(
            conversationID: "conv_demo_review",
            activityID: "activity_demo_approval",
            decision: .allowOnce
        )

        XCTAssertTrue(succeeded)
        XCTAssertTrue(model.inboxItems.isEmpty)
        XCTAssertTrue(
            model.handledActivityIDs.contains("activity_demo_approval")
        )
        XCTAssertTrue(
            model.handledRunApprovalIDs.contains(
                "run_demo_done:approval_demo"
            )
        )
    }

    func testTimedOutRunHasFriendlyRetryPresentation() {
        let run = CoreRun(
            id: "run_timeout",
            commandId: "command_timeout",
            nodeId: "node_1",
            agentId: "agent_1",
            localAgentId: "local_1",
            localRunId: "local_run_1",
            status: "timed_out",
            prompt: "执行耗时任务",
            sessionKey: nil,
            result: nil,
            error: [
                "code": .string("execution_timeout"),
                "message": .string("Execution timed out after 60 seconds")
            ],
            requestedBy: "user_1",
            createdAt: "2026-07-26T12:00:00.000Z",
            updatedAt: "2026-07-26T12:01:00.000Z",
            startedAt: "2026-07-26T12:00:01.000Z",
            finishedAt: "2026-07-26T12:01:00.000Z"
        )

        XCTAssertTrue(run.canRetry)
        XCTAssertEqual(run.failurePresentation?.title, "执行超时")
        XCTAssertTrue(
            run.failurePresentation?.suggestion.contains("重试") == true
        )
    }

    func testOfflineCacheRoundTripPreservesControlPlaneState() throws {
        let inbox = InboxBuilder.build(
            runs: DemoData.runs,
            conversationDetails: Array(DemoData.conversationDetails.values)
        )
        let state = CachedAppState(
            serverURL: "https://hibro.online/",
            bootstrap: DemoData.bootstrap,
            runs: DemoData.runs,
            artifacts: DemoData.artifacts,
            runEventsByID: [:],
            conversationDetailsByID: DemoData.conversationDetails,
            inboxItems: inbox,
            handledActivityIDs: ["activity_demo_question"],
            handledRunApprovalIDs: ["run_demo_active:approval_demo"],
            savedAt: Date(timeIntervalSince1970: 1_785_000_000)
        )

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(
            CachedAppState.self,
            from: data
        )

        XCTAssertEqual(restored.serverURL, state.serverURL)
        XCTAssertEqual(restored.bootstrap, state.bootstrap)
        XCTAssertEqual(restored.runs, state.runs)
        XCTAssertEqual(restored.artifacts, state.artifacts)
        XCTAssertEqual(restored.inboxItems, state.inboxItems)
        XCTAssertEqual(restored.handledActivityIDs, state.handledActivityIDs)
        XCTAssertEqual(
            restored.handledRunApprovalIDs,
            state.handledRunApprovalIDs
        )
    }
}
