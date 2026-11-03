import Foundation

/// Errors the Studio API answers with (`{ error, code?, issues?, params? }`).
struct StudioAPIError: LocalizedError, Sendable {
    var status: Int
    var message: String
    var code: String?
    var issues: [String]
    var errorDescription: String? { issues.isEmpty ? message : message + "\n" + issues.joined(separator: "\n") }
}

/// The Studio's HTTP API (packages/cli/src/studio/server.ts). Every POST, PUT and DELETE carries the session token.
struct StudioClient: Sendable {
    let baseURL: URL
    let token: String

    init(handshake: StudioHandshake) {
        baseURL = URL(string: handshake.url)!
        token = handshake.token
    }

    func url(_ path: String, query: [String: String] = [:]) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.path = path
        c.queryItems = query.isEmpty ? nil : query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }

    /// A file under the app root (`metadata/…`) as the Studio serves it.
    func fileURL(_ rel: String, bust: String? = nil) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.path = "/files/" + rel.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        if let bust { c.queryItems = [URLQueryItem(name: "v", value: bust)] }
        return c.url!
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private func request<T: Decodable>(_ method: String, _ path: String, query: [String: String] = [:], body: (any Encodable)? = nil, as type: T.Type) async throws -> T {
        var req = URLRequest(url: url(path, query: query))
        req.httpMethod = method
        req.timeoutInterval = 600
        if method != "GET" {
            req.setValue(token, forHTTPHeaderField: "x-vitrin-token")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try Self.encoder.encode(AnyEncodable(body ?? [String: String]()))
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let e = try? Self.decoder.decode(ErrorBody.self, from: data)
            throw StudioAPIError(status: status, message: e?.error ?? "HTTP \(status)", code: e?.code, issues: e?.issues ?? [])
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    private struct ErrorBody: Decodable {
        var error: String
        var code: String?
        var issues: [String]?
    }
    private struct AnyEncodable: Encodable {
        let value: any Encodable
        init(_ value: any Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    }
    private struct Empty: Decodable {}
    struct OK: Decodable, Sendable { var ok: Bool? }

    func overview() async throws -> Overview { try await request("GET", "/api/overview", as: Overview.self) }
    func jobs() async throws -> [JobSummary] { try await request("GET", "/api/jobs", as: [JobSummary].self) }
    func job(_ id: String) async throws -> Job { try await request("GET", "/api/jobs/\(id)", as: Job.self) }
    func run(_ command: String, args: [String: JSONValue] = [:], force: Bool = false) async throws -> JobSummary {
        struct Body: Encodable { var command: String; var args: [String: JSONValue]; var force: Bool }
        return try await request("POST", "/api/jobs", body: Body(command: command, args: args, force: force), as: JobSummary.self)
    }
    func file(_ path: String) async throws -> EditableFile { try await request("GET", "/api/file", query: ["path": path], as: EditableFile.self) }
    func save(_ path: String, text: String) async throws {
        struct Body: Encodable { var path: String; var text: String }
        _ = try await request("PUT", "/api/file", body: Body(path: path, text: text), as: OK.self)
    }
    func claude() async throws -> ClaudeInfo { try await request("GET", "/api/claude", as: ClaudeInfo.self) }
    func askClaude(prompt: String? = nil, stage: String? = nil, extra: String? = nil, fresh: Bool? = nil) async throws {
        struct Body: Encodable { var prompt: String?; var stage: String?; var extra: String?; var fresh: Bool? }
        struct Started: Decodable { var id: String }
        _ = try await request("POST", "/api/claude", body: Body(prompt: prompt, stage: stage, extra: extra, fresh: fresh), as: Started.self)
    }
    func cancelClaude() async throws { _ = try await request("POST", "/api/claude/cancel", body: [String: String](), as: Empty.self) }
    func resetClaude() async throws { _ = try await request("POST", "/api/claude/reset", body: [String: String](), as: OK.self) }
    func answer(question id: String, answer: String) async throws {
        struct Body: Encodable { var id: String; var answer: String }
        struct Started: Decodable { var id: String }
        _ = try await request("POST", "/api/questions/answer", body: Body(id: id, answer: answer), as: Started.self)
    }
    func review() async throws -> ReviewState { try await request("GET", "/api/review", as: ReviewState.self) }
    func approve(overallHash: String) async throws {
        struct Body: Encodable { var overallHash: String }
        _ = try await request("POST", "/api/approve", body: Body(overallHash: overallHash), as: OK.self)
    }
    struct Rejection: Encodable, Sendable { var item: String; var comment: String }
    func reject(overallHash: String, rejections: [Rejection]) async throws -> Int {
        struct Body: Encodable { var overallHash: String; var rejections: [Rejection] }
        struct Result: Decodable { var rejected: Int }
        return try await request("POST", "/api/reject", body: Body(overallHash: overallHash, rejections: rejections), as: Result.self).rejected
    }
    func open(_ path: String, reveal: Bool = false) async throws {
        struct Body: Encodable { var path: String; var reveal: Bool }
        _ = try await request("POST", "/api/open", body: Body(path: path, reveal: reveal), as: OK.self)
    }
}
