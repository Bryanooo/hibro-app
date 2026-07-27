import XCTest
@testable import Hibro

final class PKCETests: XCTestCase {
    func testLiveDockerCoreCompatibility() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["HIBRO_QA_CORE_URL"],
              let baseURL = URL(string: address),
              let accessToken = environment["HIBRO_QA_ACCESS_TOKEN"],
              let refreshToken = environment["HIBRO_QA_REFRESH_TOKEN"]
        else {
            throw XCTSkip(
                "设置 HIBRO_QA_CORE_URL 和临时 OAuth Token 后运行本地 Docker 集成测试"
            )
        }

        let api = CoreAPI()
        await api.configure(
            baseURL: baseURL,
            tokens: OAuthTokenSet(
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: "Bearer",
                expiresAt: Date().addingTimeInterval(600),
                scope: "hibro.read hibro.run"
            )
        )

        let bootstrap = try await api.bootstrap()
        let inbox = try await api.inbox()
        let runs = try await api.runs()

        XCTAssertEqual(bootstrap.apiVersion, "2026-07-25")
        XCTAssertEqual(bootstrap.user.username, "qa-owner")
        XCTAssertTrue(inbox.isEmpty)
        XCTAssertTrue(runs.isEmpty)
    }

    func testRFC7636Challenge() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            PKCE.challenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testVerifierUsesURLSafeCharacters() throws {
        let verifier = try PKCE.verifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertNil(verifier.range(of: #"[^A-Za-z0-9\-_]"#, options: .regularExpression))
    }

    func testFormEncoding() {
        let text = String(
            data: FormEncoding.data(["scope": "hibro.read hibro.run"]),
            encoding: .utf8
        )
        XCTAssertEqual(text, "scope=hibro.read%20hibro.run")
    }

    func testOAuthTokenResponseDecoding() throws {
        let data = Data(
            """
            {
              "access_token": "access",
              "refresh_token": "refresh",
              "token_type": "Bearer",
              "expires_in": 900,
              "scope": "hibro.read hibro.run"
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        XCTAssertEqual(response.accessToken, "access")
        XCTAssertEqual(response.refreshToken, "refresh")
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertTrue(response.tokenSet.expiresAt > Date())
    }

    func testConcurrentRequestsShareOneRefreshRotation() async throws {
        RefreshURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RefreshURLProtocol.self]
        let api = CoreAPI(
            session: URLSession(configuration: configuration),
            saveSession: { _ in }
        )
        await api.configure(
            baseURL: URL(string: "https://hibro.test")!,
            tokens: OAuthTokenSet(
                accessToken: "expired-access",
                refreshToken: "original-refresh",
                tokenType: "Bearer",
                expiresAt: .distantPast,
                scope: "hibro.read"
            )
        )

        let requests = try await withThrowingTaskGroup(
            of: URLRequest.self,
            returning: [URLRequest].self
        ) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await api.globalEventRequest()
                }
            }
            var values: [URLRequest] = []
            for try await request in group {
                values.append(request)
            }
            return values
        }

        XCTAssertEqual(RefreshURLProtocol.count, 1)
        XCTAssertEqual(requests.count, 8)
        XCTAssertTrue(
            requests.allSatisfy {
                $0.value(forHTTPHeaderField: "authorization")
                    == "Bearer refreshed-access"
            }
        )
    }

    func testBootstrapResponseMatchesCoreShape() throws {
        let data = Data(
            """
            {
              "apiVersion": "2026-07-25",
              "user": {
                "id": "usr_123",
                "username": "owner",
                "displayName": "Owner",
                "roles": ["owner"],
                "status": "active"
              },
              "permissions": ["core:read"],
              "scopes": ["hibro.read"],
              "overview": {
                "nodes": {"total": 1, "online": 1},
                "agents": {"total": 2, "registered": 2},
                "teams": 0,
                "runs": {"total": 3, "active": 1, "completed": 2, "failed": 0},
                "artifacts": 1
              },
              "nodes": [],
              "agents": [],
              "teams": [],
              "conversations": [],
              "capabilities": {"realtime": "sse"},
              "serverTime": "2026-07-25T16:00:00.000Z"
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(BootstrapResponse.self, from: data)
        XCTAssertEqual(response.overview.nodes.online, 1)
        XCTAssertEqual(response.overview.agents.registered, 2)
        XCTAssertEqual(response.user.roles, ["owner"])
    }

    func testServerURLDefaultsToHTTPSAndRemovesPaths() {
        XCTAssertEqual(
            AppModel.normalizedServerURL("core.example.com/path?debug=1")?.absoluteString,
            "https://core.example.com/"
        )
    }

    func testDefaultServerUsesProductionCore() {
        XCTAssertEqual(
            AppModel.defaultServerURL.absoluteString,
            "https://hibro.online"
        )
    }

    func testServerURLAcceptsPrivateNetworkHTTPForDeviceDevelopment() {
        XCTAssertEqual(
            AppModel.normalizedServerURL("http://192.168.1.220:17400")?.absoluteString,
            "http://192.168.1.220:17400/"
        )
        XCTAssertEqual(
            AppModel.normalizedServerURL("http://mac-mini.local:17400")?.absoluteString,
            "http://mac-mini.local:17400/"
        )
    }

    func testServerURLRejectsPublicHTTP() {
        XCTAssertNil(AppModel.normalizedServerURL("http://core.example.com"))
        XCTAssertNil(AppModel.normalizedServerURL("ftp://192.168.1.220"))
        XCTAssertNil(AppModel.normalizedServerURL("https://user:password@core.example.com"))
    }

    func testCoreTimestampSupportsFractionalSeconds() {
        XCTAssertNotNil(DateText.date(from: "2026-07-25T16:00:00.000Z"))
        XCTAssertNotNil(DateText.date(from: "2026-07-25T16:00:00Z"))
        XCTAssertNil(DateText.date(from: "not-a-date"))
    }

    func testOAuthEndpointsMustRemainOnSelectedCoreOrigin() throws {
        let core = try XCTUnwrap(URL(string: "https://core.example.com"))
        XCTAssertNoThrow(
            try OAuthCoordinator.validatedEndpoint(
                "https://core.example.com/oauth/authorize",
                baseURL: core
            )
        )
        XCTAssertThrowsError(
            try OAuthCoordinator.validatedEndpoint(
                "https://login.evil.example/oauth/authorize",
                baseURL: core
            )
        )
        XCTAssertThrowsError(
            try OAuthCoordinator.validatedEndpoint(
                "http://core.example.com/oauth/authorize",
                baseURL: core
            )
        )
    }

    func testArtifactMetadataMatchesCoreShape() throws {
        let data = Data(
            """
            {
              "id": "artifact_123",
              "coreRunId": "run_123",
              "nodeId": "node_123",
              "localArtifactId": "local_123",
              "title": "测试报告",
              "contentType": "application/pdf",
              "sizeBytes": 4096,
              "previewKind": "pdf",
              "fileName": "report.pdf",
              "encoding": "base64",
              "transferStatus": "available",
              "storage": {
                "driver": "oss",
                "objectKey": "artifacts/report.pdf",
                "etag": "etag"
              },
              "createdAt": "2026-07-25T16:00:00.000Z"
            }
            """.utf8
        )
        let artifact = try JSONDecoder().decode(CoreArtifact.self, from: data)
        XCTAssertEqual(artifact.previewKind, "pdf")
        XCTAssertEqual(artifact.fileName, "report.pdf")
        XCTAssertEqual(artifact.storage?.driver, "oss")
    }

    func testOnlyLegacySyntheticMarkdownIsHidden() throws {
        let legacy = try JSONDecoder().decode(
            CoreArtifact.self,
            from: Data(
                """
                {
                  "id": "artifact_legacy",
                  "coreRunId": "run_123",
                  "nodeId": "node_123",
                  "localArtifactId": "run_123",
                  "title": "Agent reply",
                  "contentType": "text/markdown",
                  "sizeBytes": 12,
                  "fileName": "agent-result.md",
                  "createdAt": "2026-07-25T16:00:00.000Z"
                }
                """.utf8
            )
        )
        let realFile = try JSONDecoder().decode(
            CoreArtifact.self,
            from: Data(
                """
                {
                  "id": "artifact_real",
                  "coreRunId": "run_123",
                  "nodeId": "node_123",
                  "localArtifactId": "artifact_real",
                  "title": "agent-result.md",
                  "contentType": "text/markdown",
                  "sizeBytes": 12,
                  "fileName": "agent-result.md",
                  "relativePath": "agent-result.md",
                  "createdAt": "2026-07-25T16:00:00.000Z"
                }
                """.utf8
            )
        )

        XCTAssertTrue(legacy.isLegacyAgentResult)
        XCTAssertFalse(realFile.isLegacyAgentResult)
    }
}

private final class RefreshURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requestCount = 0

    static var count: Int {
        lock.withLock { requestCount }
    }

    static func reset() {
        lock.withLock { requestCount = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/oauth/token"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock { Self.requestCount += 1 }
        Thread.sleep(forTimeInterval: 0.1)
        let data = Data(
            """
            {
              "access_token": "refreshed-access",
              "refresh_token": "refreshed-refresh",
              "token_type": "Bearer",
              "expires_in": 900,
              "scope": "hibro.read"
            }
            """.utf8
        )
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
