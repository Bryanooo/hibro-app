import Foundation

enum SSEClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        return URLSession(configuration: configuration)
    }()

    static func conversationEvents(
        request: URLRequest
    ) -> AsyncThrowingStream<ConversationEvent, Error> {
        events(request: request, as: ConversationEvent.self)
    }

    static func coreEvents(
        request: URLRequest
    ) -> AsyncThrowingStream<CoreEvent, Error> {
        events(request: request, as: CoreEvent.self)
    }

    private static func events<Event: Decodable & Sendable>(
        request: URLRequest,
        as type: Event.Type
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try CoreAPI.validate(response)
                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let payload = dataLines.joined(separator: "\n")
                                dataLines.removeAll(keepingCapacity: true)
                                let data = Data(payload.utf8)
                                do {
                                    let event = try JSONDecoder().decode(
                                        type,
                                        from: data
                                    )
                                    continuation.yield(event)
                                } catch {
                                    #if DEBUG
                                    print(
                                        "[Hibro SSE] Ignored malformed event: "
                                            + error.localizedDescription
                                    )
                                    #endif
                                }
                            }
                        } else if line.hasPrefix("data:") {
                            dataLines.append(
                                String(line.dropFirst(5)).trimmingCharacters(
                                    in: .whitespaces
                                )
                            )
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
