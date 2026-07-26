import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

struct CoreUser: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let username: String
    let displayName: String
    let roles: [String]
    let status: String?
}

struct CoreOverview: Codable, Hashable, Sendable {
    struct CountPair: Codable, Hashable, Sendable {
        let total: Int
        let online: Int?
        let registered: Int?
    }

    struct RunCounts: Codable, Hashable, Sendable {
        let total: Int
        let active: Int
        let completed: Int
        let failed: Int
    }

    let nodes: CountPair
    let agents: CountPair
    let teams: Int
    let runs: RunCounts
    let artifacts: Int
}

struct CoreNode: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let status: String
    let version: String?
    let platform: String?
    let arch: String?
    let lastSeenAt: String?
    let connectedAt: String?
    let capabilities: [String: JSONValue]?
}

struct CoreAgent: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let nodeId: String
    let localAgentId: String
    let name: String
    let description: String?
    let engine: String
    let enabled: Bool
    let status: String
    let registrationStatus: String
    let createdAt: String
    let updatedAt: String
}

struct CoreTeam: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let agentIds: [String]
    let createdAt: String
    let updatedAt: String
}

struct CoreConversation: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let nodeId: String
    let agentId: String
    let localAgentId: String
    let engine: String
    let status: String
    let source: String
    let createdBy: String
    let engineSessionId: String?
    let activeRunId: String?
    let lastMessageAt: String?
    let createdAt: String
    let updatedAt: String
}

struct CoreMessage: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let conversationId: String
    let role: String
    let content: String
    let status: String
    let runId: String?
    let error: String?
    let createdAt: String
    let updatedAt: String
}

struct CoreApproval: Codable, Hashable, Sendable {
    let provider: String
    let externalId: String?
    let decisions: [String]
    let decision: String?
    let resolvable: Bool
    let expiresAt: String?
    let reason: String?
}

struct CoreActivity: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let conversationId: String
    let messageId: String?
    let runId: String?
    let type: String
    let status: String
    let title: String
    let detail: String?
    let payload: [String: JSONValue]?
    let approval: CoreApproval?
    let createdAt: String
    let updatedAt: String
}

struct ConversationDetail: Codable, Hashable, Sendable {
    let conversation: CoreConversation
    let messages: [CoreMessage]
    let activities: [CoreActivity]
}

struct ConversationEvent: Codable, Hashable, Sendable {
    let conversationId: String
    let sequence: Int
    let type: String
    let payload: [String: JSONValue]
    let createdAt: String
}

struct CoreEvent: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let type: String
    let timestamp: String
    let payload: JSONValue
}

struct CoreRun: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let commandId: String
    let nodeId: String
    let agentId: String
    let localAgentId: String
    let localRunId: String?
    let status: String
    let prompt: String
    let sessionKey: String?
    let result: String?
    let error: [String: JSONValue]?
    let requestedBy: String
    let createdAt: String
    let updatedAt: String
    let startedAt: String?
    let finishedAt: String?
}

struct CoreRunEvent: Codable, Hashable, Sendable, Identifiable {
    let coreRunId: String
    let localRunId: String?
    let sequence: Int
    let type: String
    let timestamp: String
    let payload: [String: JSONValue]

    var id: String { "\(coreRunId):\(sequence)" }
}

struct RunApprovalRequest: Hashable, Sendable {
    let runID: String
    let externalID: String
    let title: String
    let detail: String?
    let decisions: [ApprovalDecision]
    let timestamp: String
}

extension CoreRunEvent {
    var approvalExternalID: String? {
        approvalPayload["externalId"]?.stringValue
    }

    var approvalRequest: RunApprovalRequest? {
        guard type == "engine.approval.requested",
              let externalID = approvalExternalID,
              !externalID.isEmpty
        else {
            return nil
        }
        let rawDecisions = approvalPayload["decisions"]?.arrayValue?
            .compactMap(\.stringValue)
        let decisions = ApprovalDecision.allCases.filter {
            rawDecisions?.contains($0.rawValue) ?? true
        }
        return RunApprovalRequest(
            runID: coreRunId,
            externalID: externalID,
            title: approvalPayload["title"]?.stringValue ?? "Agent 请求审批",
            detail: approvalPayload["detail"]?.stringValue
                ?? approvalPayload["command"]?.stringValue
                ?? approvalPayload["reason"]?.stringValue,
            decisions: decisions.isEmpty ? ApprovalDecision.allCases : decisions,
            timestamp: timestamp
        )
    }

    private var approvalPayload: [String: JSONValue] {
        payload["request"]?.objectValue ?? payload
    }
}

struct CoreArtifact: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let coreRunId: String
    let nodeId: String
    let localArtifactId: String
    let title: String
    let contentType: String
    let sizeBytes: Int
    let content: String?
    var previewKind: String? = nil
    var fileName: String? = nil
    var relativePath: String? = nil
    var encoding: String? = nil
    var transferStatus: String? = nil
    var storage: ArtifactStorage? = nil
    var uploadError: String? = nil
    let sha256: String?
    let createdAt: String
}

struct ArtifactStorage: Codable, Hashable, Sendable {
    let driver: String
    let objectKey: String?
    let etag: String?
}

struct ArtifactResponse: Codable, Sendable {
    let artifact: CoreArtifact
}

struct RunEventsResponse: Codable, Sendable {
    let events: [CoreRunEvent]
}

struct CoreInboxResponse: Codable, Hashable, Sendable {
    let items: [CoreInboxItem]
    let serverTime: String
}

struct CoreInboxItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let summary: String
    let createdAt: String
    let requiresAttention: Bool
    let runId: String?
    let conversationId: String?
    let approval: CoreInboxApproval?
}

struct CoreInboxApproval: Codable, Hashable, Sendable {
    let source: String
    let activityId: String?
    let externalId: String?
    let decisions: [String]
    let resolvable: Bool
    let reason: String?
}

struct ArtifactPayload: Sendable {
    let data: Data
    let suggestedFilename: String?
    let contentType: String?
}

struct BootstrapResponse: Codable, Hashable, Sendable {
    let apiVersion: String
    let user: CoreUser
    let permissions: [String]
    let scopes: [String]
    let overview: CoreOverview
    let nodes: [CoreNode]
    let agents: [CoreAgent]
    let teams: [CoreTeam]
    let conversations: [CoreConversation]
    let capabilities: [String: JSONValue]
    let serverTime: String
}

struct OAuthMetadata: Codable, Sendable {
    let issuer: String
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let scopesSupported: [String]

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case scopesSupported = "scopes_supported"
    }
}

struct OAuthTokenSet: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresAt: Date
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case tokenType
        case expiresAt
        case scope
    }
}

struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }

    var tokenSet: OAuthTokenSet {
        OAuthTokenSet(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            scope: scope
        )
    }
}

struct APIListResponse<Element: Decodable & Sendable>: Decodable, Sendable {
    let values: [Element]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: [Element]].self)
        values = object.values.first ?? []
    }
}

enum TimelineItem: Identifiable, Hashable {
    case message(CoreMessage)
    case activity(CoreActivity)

    var id: String {
        switch self {
        case .message(let value): "message:\(value.id)"
        case .activity(let value): "activity:\(value.id)"
        }
    }

    var createdAt: String {
        switch self {
        case .message(let value): value.createdAt
        case .activity(let value): value.createdAt
        }
    }
}

extension ConversationDetail {
    var timeline: [TimelineItem] {
        (
            messages.map(TimelineItem.message) +
            activities.map(TimelineItem.activity)
        )
        .sorted { $0.createdAt < $1.createdAt }
    }
}
