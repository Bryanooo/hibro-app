import Foundation

actor CoreAPI {
    static let clientID = "hibro-ios"
    static let redirectURI = "hibro://oauth/callback"

    private var baseURL: URL?
    private var tokenSet: OAuthTokenSet?
    private var configurationGeneration = 0
    private var refreshTask: (
        generation: Int,
        task: Task<OAuthTokenSet, Error>
    )?
    private let session: URLSession
    private let saveSession: @Sendable (OAuthTokenSet) throws -> Void
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        session: URLSession? = nil,
        saveSession: @escaping @Sendable (OAuthTokenSet) throws -> Void = {
            try KeychainStore.saveSession($0)
        }
    ) {
        self.saveSession = saveSession
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 300
            configuration.httpMaximumConnectionsPerHost = 6
            self.session = URLSession(configuration: configuration)
        }
    }

    func configure(baseURL: URL, tokens: OAuthTokenSet?) {
        configurationGeneration += 1
        refreshTask?.task.cancel()
        refreshTask = nil
        self.baseURL = baseURL
        self.tokenSet = tokens
    }

    func currentBaseURL() -> URL? { baseURL }

    func health(at url: URL) async throws {
        let endpoint = url.appending(path: "health")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "accept")
        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
    }

    func bootstrap() async throws -> BootstrapResponse {
        try await request(path: "/v1/app/bootstrap")
    }

    func runs() async throws -> [CoreRun] {
        let response: APIListResponse<CoreRun> = try await request(path: "/v1/runs")
        return response.values
    }

    func inbox() async throws -> [CoreInboxItem] {
        let response: CoreInboxResponse = try await request(path: "/v1/app/inbox")
        return response.items
    }

    func artifacts() async throws -> [CoreArtifact] {
        let response: APIListResponse<CoreArtifact> = try await request(path: "/v1/artifacts")
        return response.values
    }

    func updateUserDisplayName(userID: String, displayName: String) async throws -> CoreUser {
        struct Input: Encodable { let displayName: String }
        return try await request(
            path: "/v1/security/users/\(userID.urlPathSegment)",
            method: "PUT",
            body: Input(displayName: displayName)
        )
    }

    func artifact(id: String) async throws -> CoreArtifact {
        let response: ArtifactResponse = try await request(
            path: "/v1/artifacts/\(id.urlPathSegment)"
        )
        return response.artifact
    }

    func artifactContent(id: String) async throws -> ArtifactPayload {
        try await dataRequest(
            path: "/v1/artifacts/\(id.urlPathSegment)/content"
        )
    }

    func artifactDownload(id: String) async throws -> ArtifactPayload {
        try await dataRequest(
            path: "/v1/artifacts/\(id.urlPathSegment)/download"
        )
    }

    func conversation(id: String) async throws -> ConversationDetail {
        try await request(path: "/v1/conversations/\(id)")
    }

    func createConversation(agentID: String, title: String?) async throws -> ConversationDetail {
        struct Input: Encodable { let agentId: String; let title: String? }
        return try await request(
            path: "/v1/conversations",
            method: "POST",
            body: Input(agentId: agentID, title: title?.nilIfBlank)
        )
    }

    func sendMessage(conversationID: String, content: String) async throws -> ConversationDetail {
        struct Input: Encodable { let content: String }
        return try await request(
            path: "/v1/conversations/\(conversationID)/messages",
            method: "POST",
            body: Input(content: content)
        )
    }

    func cancelConversation(id: String) async throws -> ConversationDetail {
        try await request(
            path: "/v1/conversations/\(id)/cancel",
            method: "POST",
            body: EmptyBody()
        )
    }

    func decideConversationApproval(
        conversationID: String,
        activityID: String,
        decision: ApprovalDecision
    ) async throws -> ConversationDetail {
        struct Input: Encodable { let decision: String }
        return try await request(
            path: "/v1/conversations/\(conversationID)/approval/\(activityID)",
            method: "POST",
            body: Input(decision: decision.rawValue)
        )
    }

    func createRun(
        agentID: String,
        prompt: String,
        sessionKey: String?,
        freshSession: Bool
    ) async throws -> CoreRun {
        struct Input: Encodable {
            let agentId: String
            let prompt: String
            let sessionKey: String?
            let freshSession: Bool
        }
        return try await request(
            path: "/v1/runs",
            method: "POST",
            body: Input(
                agentId: agentID,
                prompt: prompt,
                sessionKey: sessionKey?.nilIfBlank,
                freshSession: freshSession
            )
        )
    }

    func cancelRun(id: String) async throws -> CoreRun {
        try await request(
            path: "/v1/runs/\(id.urlPathSegment)/cancel",
            method: "POST",
            body: EmptyBody()
        )
    }

    func runEvents(id: String) async throws -> [CoreRunEvent] {
        let response: RunEventsResponse = try await request(
            path: "/v1/runs/\(id.urlPathSegment)/events"
        )
        return response.events
    }

    func decideRunApproval(
        runID: String,
        externalID: String,
        decision: ApprovalDecision
    ) async throws -> CoreRun {
        struct Input: Encodable { let decision: String }
        return try await request(
            path: "/v1/runs/\(runID.urlPathSegment)/approval/\(externalID.urlPathSegment)",
            method: "POST",
            body: Input(decision: decision.rawValue)
        )
    }

    func conversationEventRequest(id: String, after: Int) async throws -> URLRequest {
        try await authorizedRequest(
            path: "/v1/conversations/\(id)/events?after=\(after)"
        )
    }

    func globalEventRequest() async throws -> URLRequest {
        try await authorizedRequest(path: "/v1/events")
    }

    func refreshAuthorization() async throws {
        guard try await refreshTokens() else {
            throw APIError.unauthorized
        }
    }

    func clearSession() {
        configurationGeneration += 1
        refreshTask?.task.cancel()
        refreshTask = nil
        tokenSet = nil
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        let request = try await authorizedRequest(path: path, method: method)
        return try await perform(request)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        var request = try await authorizedRequest(path: path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, _) = try await performData(request)
        return try decoder.decode(Response.self, from: data)
    }

    private func dataRequest(path: String) async throws -> ArtifactPayload {
        let request = try await authorizedRequest(path: path)
        let (data, response) = try await performData(request)
        return ArtifactPayload(
            data: data,
            suggestedFilename: response.suggestedFilename,
            contentType: response.value(forHTTPHeaderField: "content-type")
        )
    }

    private func performData(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        do {
            try Self.validate(response, data: data)
        } catch APIError.unauthorized {
            guard try await refreshTokens() else { throw APIError.unauthorized }
            var retry = request
            retry.setValue(
                "Bearer \(tokenSet?.accessToken ?? "")",
                forHTTPHeaderField: "authorization"
            )
            let (retryData, retryResponse) = try await session.data(for: retry)
            try Self.validate(retryResponse, data: retryData)
            guard let httpResponse = retryResponse as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            return (retryData, httpResponse)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func authorizedRequest(
        path: String,
        method: String = "GET"
    ) async throws -> URLRequest {
        guard let baseURL else { throw APIError.notConfigured }
        if tokenSet?.expiresAt.timeIntervalSinceNow ?? 0 < 60 {
            _ = try await refreshTokens()
        }
        guard let accessToken = tokenSet?.accessToken else {
            throw APIError.unauthorized
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        return request
    }

    private func refreshTokens() async throws -> Bool {
        guard let baseURL, let current = tokenSet else { return false }
        let generation = configurationGeneration
        if let refreshTask, refreshTask.generation == generation {
            let refreshed = try await refreshTask.task.value
            guard configurationGeneration == generation else {
                throw CancellationError()
            }
            try applyRefreshedTokens(refreshed)
            return true
        }

        let session = self.session
        let task = Task {
            let endpoint = baseURL.appending(path: "oauth/token")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "content-type"
            )
            request.httpBody = FormEncoding.data([
                "grant_type": "refresh_token",
                "client_id": Self.clientID,
                "refresh_token": current.refreshToken
            ])
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               http.statusCode == 400,
               (try? JSONDecoder().decode(ServerError.self, from: data).error)
                    == "invalid_grant" {
                throw APIError.unauthorized
            }
            try Self.validate(response, data: data)
            return try JSONDecoder()
                .decode(OAuthTokenResponse.self, from: data)
                .tokenSet
        }
        refreshTask = (generation, task)
        defer {
            if configurationGeneration == generation {
                refreshTask = nil
            }
        }
        let refreshed = try await task.value
        guard configurationGeneration == generation else {
            throw CancellationError()
        }
        try applyRefreshedTokens(refreshed)
        return true
    }

    private func applyRefreshedTokens(_ refreshed: OAuthTokenSet) throws {
        guard tokenSet?.refreshToken != refreshed.refreshToken else { return }
        try saveSession(refreshed)
        tokenSet = refreshed
    }

    static func validate(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            let detail = (try? JSONDecoder().decode(ServerError.self, from: data))
            throw APIError.server(status: http.statusCode, message: detail?.message)
        }
    }
}

private struct EmptyBody: Encodable {}

private struct ServerError: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    var message: String? { errorDescription ?? error }
}

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case unauthorized
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "尚未配置 Hibro Core"
        case .invalidURL: "请求地址无效"
        case .invalidResponse: "Core 返回了无效响应"
        case .unauthorized: "登录已过期，请重新登录"
        case .server(let status, let message):
            message.map { "Core \(status)：\($0)" } ?? "Core 请求失败（\(status)）"
        }
    }
}

enum FormEncoding {
    static func data(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let text = values
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(text.utf8)
    }
}

extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var urlPathSegment: String {
        addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "-._~")
            )
        ) ?? self
    }
}
