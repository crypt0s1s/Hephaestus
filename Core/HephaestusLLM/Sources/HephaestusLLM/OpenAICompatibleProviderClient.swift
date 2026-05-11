import Foundation
import HephaestusKernel

public struct OpenAICompatibleClientConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let apiKey: String
    public let model: String

    public init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

public struct OpenAICompatibleTransportRequest: Sendable, Equatable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    public init(url: URL, method: String, headers: [String: String], body: Data) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public enum OpenAICompatibleTransportEvent: Sendable, Equatable {
    case response(statusCode: Int)
    case data(Data)
}

public protocol OpenAICompatibleTransport: Sendable {
    func stream(
        request: OpenAICompatibleTransportRequest
    ) -> AsyncThrowingStream<OpenAICompatibleTransportEvent, Error>
}

public struct OpenAICompatibleProviderHTTPError: Error, Sendable, Equatable, CustomStringConvertible {
    public let statusCode: Int
    public let body: String

    public var description: String {
        if body.isEmpty {
            return "OpenAI-compatible provider returned HTTP \(statusCode)."
        }
        return "OpenAI-compatible provider returned HTTP \(statusCode): \(body)"
    }

    public init(statusCode: Int, body: String = "") {
        self.statusCode = statusCode
        self.body = body
    }
}

public struct OpenAICompatibleProviderClient: ProviderClient {
    private let configuration: OpenAICompatibleClientConfiguration
    private let transport: OpenAICompatibleTransport

    public init(
        configuration: OpenAICompatibleClientConfiguration,
        transport: OpenAICompatibleTransport = URLSessionOpenAICompatibleTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderResponseChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await streamChunks(for: request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func streamChunks(
        for request: ProviderRequest,
        into continuation: AsyncThrowingStream<ProviderResponseChunk, Error>.Continuation
    ) async throws {
        let transportRequest = try makeTransportRequest(for: request)
        var parser = OpenAICompatibleSSEParser(providerRequestID: request.id)
        var response = OpenAICompatibleResponseAccumulator()

        for try await event in transport.stream(request: transportRequest) {
            for chunk in try response.consume(event, request: request, parser: &parser) {
                continuation.yield(chunk)
            }
        }

        let finalChunks = try response.finish(request: request, parser: &parser)
        for chunk in finalChunks {
            continuation.yield(chunk)
        }
    }

    public func makeTransportRequest(for request: ProviderRequest) throws
        -> OpenAICompatibleTransportRequest {
        let body = ChatCompletionsRequest(
            model: request.model,
            stream: request.stream,
            messages: request.messages.map { message in
                ChatCompletionsMessage(role: message.role.rawValue, content: message.text)
            }
        )
        return OpenAICompatibleTransportRequest(
            url: Self.chatCompletionsURL(baseURL: configuration.baseURL),
            method: "POST",
            headers: [
                "Authorization": "Bearer \(configuration.apiKey)",
                "Accept": request.stream ? "text/event-stream" : "application/json",
                "Content-Type": "application/json",
            ],
            body: try JSONEncoder().encode(body)
        )
    }

    public static func chatCompletionsURL(baseURL: URL) -> URL {
        var components =
            URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path =
            "/" + ([path, "chat/completions"].filter { !$0.isEmpty }.joined(separator: "/"))
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL.appendingPathComponent("chat/completions")
    }

    fileprivate static func parseChatCompletionsResponse(
        _ data: Data,
        providerRequestID: UUID
    ) throws -> [ProviderResponseChunk] {
        guard !data.isEmpty else {
            return []
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        return decoded.choices.compactMap { choice in
            guard let content = choice.message.content, !content.isEmpty else {
                return nil
            }
            return ProviderResponseChunk(
                providerRequestID: providerRequestID,
                delta: .text(content),
                finishReason: choice.finishReason.providerFinishReason
            )
        }
    }
}

private struct OpenAICompatibleResponseAccumulator {
    private var statusCode: Int?
    private var responseBody = Data()

    mutating func consume(
        _ event: OpenAICompatibleTransportEvent,
        request: ProviderRequest,
        parser: inout OpenAICompatibleSSEParser
    ) throws -> [ProviderResponseChunk] {
        switch event {
        case .response(let statusCode):
            self.statusCode = statusCode
            return []
        case .data(let data):
            if request.stream, isSuccessfulResponse {
                return try parser.parse(data)
            }
            responseBody.append(data)
            return []
        }
    }

    mutating func finish(
        request: ProviderRequest,
        parser: inout OpenAICompatibleSSEParser
    ) throws -> [ProviderResponseChunk] {
        guard let statusCode, (200..<300).contains(statusCode) else {
            throw OpenAICompatibleProviderHTTPError(
                statusCode: statusCode ?? 0,
                body: String(data: responseBody, encoding: .utf8) ?? ""
            )
        }

        if request.stream {
            return try parser.finish()
        }

        return try OpenAICompatibleProviderClient.parseChatCompletionsResponse(
            responseBody,
            providerRequestID: request.id
        )
    }

    private var isSuccessfulResponse: Bool {
        guard let statusCode else { return false }
        return (200..<300).contains(statusCode)
    }
}

public final class URLSessionOpenAICompatibleTransport: OpenAICompatibleTransport,
    @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(
        request: OpenAICompatibleTransportRequest
    ) -> AsyncThrowingStream<OpenAICompatibleTransportEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var urlRequest = URLRequest(url: request.url)
                    urlRequest.httpMethod = request.method
                    urlRequest.httpBody = request.body
                    for (key, value) in request.headers {
                        urlRequest.setValue(value, forHTTPHeaderField: key)
                    }

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    continuation.yield(.response(statusCode: statusCode))

                    for try await byte in bytes {
                        continuation.yield(.data(Data([byte])))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

public struct OpenAICompatibleSSEParser: Sendable {
    private var buffer = Data()
    private let providerRequestID: UUID

    public init(providerRequestID: UUID) {
        self.providerRequestID = providerRequestID
    }

    public mutating func parse(_ data: Data) throws -> [ProviderResponseChunk] {
        buffer.append(data)
        var chunks: [ProviderResponseChunk] = []

        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(...newlineIndex)
            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }
            chunks.append(contentsOf: try parseLine(line))
        }

        return chunks
    }

    public mutating func finish() throws -> [ProviderResponseChunk] {
        guard let line = String(data: buffer, encoding: .utf8) else {
            buffer.removeAll()
            return []
        }
        buffer.removeAll()
        return try parseLine(line)
    }

    private func parseLine(_ line: String) throws -> [ProviderResponseChunk] {
        let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("data:") else {
            return []
        }

        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else {
            return []
        }

        let decoded = try JSONDecoder().decode(
            ChatCompletionsStreamResponse.self,
            from: Data(payload.utf8)
        )
        return decoded.choices.compactMap { choice in
            guard let content = choice.delta.content, !content.isEmpty else {
                return nil
            }
            return ProviderResponseChunk(
                providerRequestID: providerRequestID,
                delta: .text(content),
                finishReason: nil
            )
        }
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let stream: Bool
    let messages: [ChatCompletionsMessage]
}

private struct ChatCompletionsMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionsStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

extension Optional where Wrapped == String {
    fileprivate var providerFinishReason: ProviderFinishReason? {
        switch self {
        case .some("stop"):
            return .stop
        case .some("length"):
            return .length
        default:
            return nil
        }
    }
}
