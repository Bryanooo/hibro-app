import Foundation
import Observation

enum AppPhase: Equatable {
    case launching
    case signedOut
    case authenticating
    case signedIn
}

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case inbox
    case runs
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .inbox: "收件箱"
        case .runs: "运行"
        case .more: "更多"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .inbox: "tray"
        case .runs: "play.circle"
        case .more: "ellipsis.circle"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var phase: AppPhase = .launching
    var section: AppSection = .home
    var bootstrap: BootstrapResponse?
    var runs: [CoreRun] = []
    var artifacts: [CoreArtifact] = []
    var artifactDetailsByID: [String: CoreArtifact] = [:]
    var runEventsByID: [String: [CoreRunEvent]] = [:]
    var conversationDetail: ConversationDetail?
    var conversationDetailsByID: [String: ConversationDetail] = [:]
    var selectedConversationID: String?
    var highlightedRunID: String?
    var selectedInboxItemID: String?
    var handledActivityIDs: Set<String> = []
    var handledRunApprovalIDs: Set<String> = []
    var errorMessage: String?
    var isWorking = false
    var isDemoMode = false
    var lastRefreshAt: Date?

    let api = CoreAPI()
    private let oauth = OAuthCoordinator()
    private var conversationStreamTask: Task<Void, Never>?
    private var globalStreamTask: Task<Void, Never>?
    private var globalRefreshTask: Task<Void, Never>?
    private var conversationSequences: [String: Int] = [:]
    private var pendingDeepLink: URL?
    private static let serverDefaultsKey = "hibro.core.baseURL"
    nonisolated static let defaultServerURL = URL(
        string: "https://hibro.online"
    )!

    init() {
        Task { await restore() }
    }

    var serverURL: URL? {
        if let value = UserDefaults.standard.string(forKey: Self.serverDefaultsKey) {
            return URL(string: value)
        }
        return nil
    }

    var serverURLText: String {
        serverURL?.absoluteString ?? Self.defaultServerURL.absoluteString
    }

    var currentUser: CoreUser? { bootstrap?.user }
    var agents: [CoreAgent] { bootstrap?.agents ?? [] }
    var nodes: [CoreNode] { bootstrap?.nodes ?? [] }
    var teams: [CoreTeam] { bootstrap?.teams ?? [] }
    var conversations: [CoreConversation] { bootstrap?.conversations ?? [] }
    var inboxItems: [InboxItem] {
        InboxBuilder.build(
            runs: runs,
            conversationDetails: Array(conversationDetailsByID.values),
            runEvents: runEventsByID,
            excludingRunApprovalIDs: handledRunApprovalIDs,
            excludingActivityIDs: handledActivityIDs
        )
    }

    func restore() async {
        if ProcessInfo.processInfo.arguments.contains("-hibro-demo") {
            loadDemo()
            return
        }
        guard
            let serverURL,
            let session = try? KeychainStore.loadSession()
        else {
            phase = .signedOut
            return
        }
        await api.configure(baseURL: serverURL, tokens: session)
        do {
            try await refresh()
            phase = .signedIn
            startGlobalEvents()
            processPendingDeepLink()
        } catch {
            if case APIError.unauthorized = error {
                KeychainStore.deleteSession()
                await api.clearSession()
            }
            handle(error)
            phase = .signedOut
        }
    }

    func login(serverAddress: String) async {
        guard let url = Self.normalizedServerURL(serverAddress) else {
            errorMessage = Self.invalidServerMessage(for: serverAddress)
            return
        }
        phase = .authenticating
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.health(at: url)
            let tokens = try await oauth.authenticate(baseURL: url)
            try KeychainStore.saveSession(tokens)
            UserDefaults.standard.set(
                url.absoluteString,
                forKey: Self.serverDefaultsKey
            )
            await api.configure(baseURL: url, tokens: tokens)
            try await refresh()
            phase = .signedIn
            startGlobalEvents()
            processPendingDeepLink()
        } catch {
            handle(error)
            phase = .signedOut
        }
    }

    func testServerConnection(serverAddress: String) async -> Bool {
        guard let url = Self.normalizedServerURL(serverAddress) else {
            errorMessage = Self.invalidServerMessage(for: serverAddress)
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.health(at: url)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func refresh() async throws {
        if isDemoMode {
            lastRefreshAt = Date()
            return
        }
        async let bootstrapRequest = api.bootstrap()
        async let runRequest = api.runs()
        async let artifactRequest = api.artifacts()
        let (newBootstrap, newRuns, newArtifacts) = try await (
            bootstrapRequest,
            runRequest,
            artifactRequest
        )
        bootstrap = newBootstrap
        runs = newRuns.sorted { $0.updatedAt > $1.updatedAt }
        artifacts = newArtifacts.sorted { $0.createdAt > $1.createdAt }
        // Approval requests are authoritative Run events. Some engines can
        // finish or fail the Run record while an approval remains unresolved,
        // so Inbox discovery must not be limited to top-level active statuses.
        await refreshRunEvents(for: newRuns)
        await refreshInboxContext(conversations: newBootstrap.conversations)
        #if DEBUG
        let statuses = Dictionary(grouping: newRuns, by: \.status)
            .mapValues(\.count)
        print("[Hibro Inbox] Run statuses: \(statuses)")
        #endif
        lastRefreshAt = Date()
    }

    func refreshFromUser() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await refresh()
        } catch {
            handle(error)
        }
    }

    func openConversation(_ id: String) async {
        selectedConversationID = id
        conversationStreamTask?.cancel()
        if isDemoMode {
            conversationDetail = DemoData.conversationDetail(id: id)
            if let conversationDetail {
                conversationDetailsByID[id] = conversationDetail
            }
            return
        }
        do {
            conversationDetail = try await api.conversation(id: id)
            if let conversationDetail {
                conversationDetailsByID[id] = conversationDetail
            }
            watchConversation(id)
        } catch {
            handle(error)
        }
    }

    func createConversation(agentID: String, title: String?) async -> Bool {
        if isDemoMode {
            errorMessage = "演示模式不会向 Core 创建数据"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let detail = try await api.createConversation(
                agentID: agentID,
                title: title
            )
            conversationDetail = detail
            conversationDetailsByID[detail.conversation.id] = detail
            selectedConversationID = detail.conversation.id
            try await refresh()
            section = .more
            watchConversation(detail.conversation.id)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func sendMessage(_ content: String) async -> Bool {
        guard let conversationID = conversationDetail?.conversation.id else {
            return false
        }
        if isDemoMode {
            errorMessage = "演示模式不会发送消息"
            return false
        }
        do {
            conversationDetail = try await api.sendMessage(
                conversationID: conversationID,
                content: content
            )
            if let conversationDetail {
                conversationDetailsByID[conversationID] = conversationDetail
            }
            watchConversation(conversationID)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func cancelConversation() async {
        guard let id = conversationDetail?.conversation.id, !isDemoMode else {
            return
        }
        do {
            conversationDetail = try await api.cancelConversation(id: id)
        } catch {
            handle(error)
        }
    }

    func decideApproval(
        conversationID: String,
        activityID: String,
        decision: ApprovalDecision
    ) async -> Bool {
        if isDemoMode {
            handledActivityIDs.insert(activityID)
            return true
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let detail = try await api.decideConversationApproval(
                conversationID: conversationID,
                activityID: activityID,
                decision: decision
            )
            conversationDetail = detail
            conversationDetailsByID[conversationID] = detail
            handledActivityIDs.insert(activityID)
            watchConversation(conversationID)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func createRun(
        agentID: String,
        prompt: String,
        sessionKey: String?,
        freshSession: Bool
    ) async -> Bool {
        if isDemoMode {
            errorMessage = "演示模式不会发起运行"
            return false
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let run = try await api.createRun(
                agentID: agentID,
                prompt: prompt,
                sessionKey: sessionKey,
                freshSession: freshSession
            )
            runs.insert(run, at: 0)
            highlightedRunID = run.id
            section = .runs
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func cancelRun(_ id: String) async {
        guard !isDemoMode else { return }
        do {
            let updated = try await api.cancelRun(id: id)
            if let index = runs.firstIndex(where: { $0.id == id }) {
                runs[index] = updated
            }
        } catch {
            handle(error)
        }
    }

    func openRun(_ id: String) async {
        guard !isDemoMode else { return }
        do {
            runEventsByID[id] = try await api.runEvents(id: id)
        } catch {
            handle(error)
        }
    }

    func decideRunApproval(
        runID: String,
        externalID: String,
        decision: ApprovalDecision
    ) async -> Bool {
        guard !isDemoMode else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated = try await api.decideRunApproval(
                runID: runID,
                externalID: externalID,
                decision: decision
            )
            if let index = runs.firstIndex(where: { $0.id == runID }) {
                runs[index] = updated
            }
            handledRunApprovalIDs.insert("\(runID):\(externalID)")
            if let events = try? await api.runEvents(id: runID) {
                runEventsByID[runID] = events
            }
            return true
        } catch {
            handle(error)
            return false
        }
    }

    func loadArtifact(id: String) async -> (CoreArtifact, ArtifactPayload)? {
        if isDemoMode,
           let artifact = artifacts.first(where: { $0.id == id }),
           let content = artifact.content {
            return (
                artifact,
                ArtifactPayload(
                    data: Data(content.utf8),
                    suggestedFilename: artifact.fileName,
                    contentType: artifact.contentType
                )
            )
        }
        do {
            let artifact = try await api.artifact(id: id)
            artifactDetailsByID[id] = artifact
            let payload = try await api.artifactContent(id: id)
            return (artifact, payload)
        } catch {
            handle(error)
            return nil
        }
    }

    func downloadArtifact(id: String) async -> URL? {
        do {
            let artifact = artifactDetailsByID[id]
                ?? artifacts.first(where: { $0.id == id })
            let payload: ArtifactPayload
            if isDemoMode, let content = artifact?.content {
                payload = ArtifactPayload(
                    data: Data(content.utf8),
                    suggestedFilename: artifact?.fileName,
                    contentType: artifact?.contentType
                )
            } else {
                payload = try await api.artifactDownload(id: id)
            }
            let name = Self.safeFileName(
                payload.suggestedFilename
                    ?? artifact?.fileName
                    ?? artifact?.title
                    ?? id
            )
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "HibroArtifacts", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appending(path: name)
            try payload.data.write(to: url, options: .atomic)
            return url
        } catch {
            handle(error)
            return nil
        }
    }

    func resumeRealtimeSync() {
        guard phase == .signedIn, !isDemoMode else { return }
        startGlobalEvents()
        scheduleGlobalRefresh(delay: .zero)
    }

    func suspendRealtimeSync() {
        globalStreamTask?.cancel()
        globalStreamTask = nil
        globalRefreshTask?.cancel()
        globalRefreshTask = nil
    }

    func logout() {
        conversationStreamTask?.cancel()
        conversationStreamTask = nil
        suspendRealtimeSync()
        KeychainStore.deleteSession()
        Task { await api.clearSession() }
        bootstrap = nil
        runs = []
        artifacts = []
        artifactDetailsByID = [:]
        runEventsByID = [:]
        conversationDetail = nil
        conversationDetailsByID = [:]
        handledActivityIDs = []
        handledRunApprovalIDs = []
        conversationSequences = [:]
        selectedConversationID = nil
        isDemoMode = false
        phase = .signedOut
    }

    func loadDemo() {
        conversationStreamTask?.cancel()
        suspendRealtimeSync()
        isDemoMode = true
        bootstrap = DemoData.bootstrap
        runs = DemoData.runs
        artifacts = DemoData.artifacts
        artifactDetailsByID = Dictionary(
            uniqueKeysWithValues: DemoData.artifacts.map { ($0.id, $0) }
        )
        runEventsByID = [:]
        conversationDetailsByID = DemoData.conversationDetails
        handledActivityIDs = []
        handledRunApprovalIDs = []
        lastRefreshAt = Date()
        phase = .signedIn
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "hibro", url.host != "oauth" else { return }
        guard phase == .signedIn else {
            pendingDeepLink = url
            return
        }
        routeDeepLink(url)
    }

    private func routeDeepLink(_ url: URL) {
        let resource = url.host ?? ""
        let id = url.pathComponents.dropFirst().first
        let query = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems
        switch resource {
        case "conversations":
            if let activityID = query?.first(where: { $0.name == "activity" })?.value,
               let id {
                Task {
                    await openConversation(id)
                    section = .inbox
                    selectedInboxItemID = "activity:\(activityID)"
                }
            } else {
                section = .more
                if let id { Task { await openConversation(id) } }
            }
        case "runs":
            if let approvalID = query?.first(where: { $0.name == "approval" })?.value,
               let id {
                Task {
                    await openRun(id)
                    section = .inbox
                    selectedInboxItemID = "run-approval:\(id):\(approvalID)"
                }
            } else {
                section = .runs
                highlightedRunID = id
            }
        case "artifacts":
            section = .more
        case "inbox":
            section = .inbox
            selectedInboxItemID = id
        case "team-runs", "nodes":
            section = .more
        default:
            section = .home
        }
    }

    private func processPendingDeepLink() {
        guard let pendingDeepLink else { return }
        self.pendingDeepLink = nil
        routeDeepLink(pendingDeepLink)
    }

    func agentName(_ id: String) -> String {
        agents.first(where: { $0.id == id })?.name ?? id.shortIdentifier
    }

    func nodeName(_ id: String) -> String {
        nodes.first(where: { $0.id == id })?.name ?? id.shortIdentifier
    }

    private func watchConversation(_ id: String) {
        conversationStreamTask?.cancel()
        conversationStreamTask = Task { [weak self] in
            guard let self else { return }
            var sequence = conversationSequences[id] ?? 0
            while !Task.isCancelled {
                do {
                    let request = try await api.conversationEventRequest(
                        id: id,
                        after: sequence
                    )
                    for try await event in SSEClient.conversationEvents(
                        request: request
                    ) {
                        if Task.isCancelled { return }
                        sequence = max(sequence, event.sequence)
                        conversationSequences[id] = sequence
                        conversationDetail = try await api.conversation(id: id)
                        if let conversationDetail {
                            conversationDetailsByID[id] = conversationDetail
                        }
                    }
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func startGlobalEvents() {
        globalStreamTask?.cancel()
        globalStreamTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let request = try await api.globalEventRequest()
                    for try await _ in SSEClient.coreEvents(request: request) {
                        if Task.isCancelled { return }
                        scheduleGlobalRefresh()
                    }
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                    }
                } catch is CancellationError {
                    return
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }

    private func scheduleGlobalRefresh(
        delay: Duration = .milliseconds(500)
    ) {
        globalRefreshTask?.cancel()
        globalRefreshTask = Task { [weak self] in
            if delay != .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let self else { return }
            do {
                try await refresh()
            } catch {
                handle(error)
            }
        }
    }

    private func refreshRunEvents(for runs: [CoreRun]) async {
        let api = self.api
        let values = await withTaskGroup(
            of: (String, [CoreRunEvent]?).self,
            returning: [(String, [CoreRunEvent])].self
        ) { group in
            for run in runs.prefix(20) {
                group.addTask {
                    (run.id, try? await api.runEvents(id: run.id))
                }
            }
            var results: [(String, [CoreRunEvent])] = []
            for await (id, events) in group {
                if let events { results.append((id, events)) }
            }
            return results
        }
        for (id, events) in values {
            runEventsByID[id] = events
        }
        #if DEBUG
        let approvals = values.flatMap(\.1).filter {
            $0.type.localizedCaseInsensitiveContains("approval")
        }
        print(
            "[Hibro Inbox] Loaded events for \(values.count)/\(runs.count) "
                + "runs; approval events: "
                + approvals.map(\.type).description
        )
        #endif
    }

    private func refreshInboxContext(
        conversations: [CoreConversation]
    ) async {
        let candidates = conversations
            .sorted { $0.updatedAt > $1.updatedAt }
        let api = self.api
        let details = await withTaskGroup(
            of: ConversationDetail?.self,
            returning: [ConversationDetail].self
        ) { group in
            let load: @Sendable (CoreConversation) async -> ConversationDetail? = {
                conversation in
                do {
                    return try await api.conversation(id: conversation.id)
                } catch {
                    #if DEBUG
                    print(
                        "[Hibro Inbox] Failed to load \(conversation.id): "
                            + error.localizedDescription
                    )
                    #endif
                    return nil
                }
            }
            var iterator = candidates.makeIterator()
            for _ in 0..<min(8, candidates.count) {
                guard let conversation = iterator.next() else { break }
                group.addTask {
                    await load(conversation)
                }
            }
            var values: [ConversationDetail] = []
            for await detail in group {
                if let detail { values.append(detail) }
                if let conversation = iterator.next() {
                    group.addTask {
                        await load(conversation)
                    }
                }
            }
            return values
        }
        for detail in details {
            conversationDetailsByID[detail.conversation.id] = detail
            if selectedConversationID == detail.conversation.id {
                conversationDetail = detail
            }
        }
        #if DEBUG
        let pendingApprovals = details
            .flatMap(\.activities)
            .filter {
                $0.type == "approval"
                    && $0.status == "pending"
                    && $0.approval?.decision == nil
            }
            .count
        print(
            "[Hibro Inbox] Loaded \(details.count)/\(candidates.count) "
                + "conversations; pending approvals: \(pendingApprovals)"
        )
        #endif
    }

    private func handle(_ error: Error) {
        if let urlError = error as? URLError {
            errorMessage = switch urlError.code {
            case .cannotFindHost:
                "找不到 Hibro Core。请检查地址、DNS 或局域网连接。"
            case .cannotConnectToHost, .networkConnectionLost:
                "无法连接 Hibro Core。请确认服务已启动，并允许 Hibro 访问本地网络。"
            case .notConnectedToInternet:
                "设备当前没有可用网络。"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                "Core 的 HTTPS 证书无法验证。请使用系统信任的有效证书。"
            case .timedOut:
                "连接 Hibro Core 超时。请检查地址、防火墙和网络。"
            default:
                urlError.localizedDescription
            }
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    nonisolated static func normalizedServerURL(_ value: String) -> URL? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://\(text)" }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              components.user == nil,
              components.password == nil
        else {
            return nil
        }
        if scheme == "http", !isPrivateNetworkHost(host) {
            return nil
        }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    nonisolated private static func invalidServerMessage(for value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("http://") {
            return "公网 Core 必须使用 HTTPS；HTTP 仅允许 localhost、.local 或私有局域网地址。"
        }
        return OAuthError.invalidServerURL.localizedDescription
    }

    nonisolated private static func isPrivateNetworkHost(_ host: String) -> Bool {
        let value = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        if value == "localhost" || value == "::1" || value.hasPrefix("127.") {
            return true
        }
        if value.hasSuffix(".local") ||
            value.hasPrefix("fc") ||
            value.hasPrefix("fd") ||
            ["fe8", "fe9", "fea", "feb"].contains(where: value.hasPrefix) {
            return true
        }
        let octets = value.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }
        return octets[0] == 10 ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254)
    }

    nonisolated private static func safeFileName(_ value: String) -> String {
        let name = value
            .replacingOccurrences(
                of: #"[^A-Za-z0-9._\-\u{4e00}-\u{9fff}]"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return name.isEmpty ? "artifact" : name
    }
}

extension String {
    var shortIdentifier: String {
        count > 12 ? "\(prefix(8))…" : self
    }
}
