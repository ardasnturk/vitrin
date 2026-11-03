import Foundation

/// One server-sent event from `GET /api/events`.
struct StudioEvent: Sendable {
    var name: String
    var data: Data
    func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(T.self, from: data) }
}

/// The text/event-stream wire format, one byte at a time: lines end with LF (a CR before it is dropped), `event:` names
/// the event, `data:` lines are joined with newlines, `:` lines are comments, and a blank line ends an event, which is
/// emitted only when it carries data. The field names and values are trimmed as the Studio page's EventSource reads them.
struct SSEParser: Sendable {
    private var name = "message"
    private var data = ""
    private var line: [UInt8] = []

    init() {}

    /// Feeds one byte; returns the event a blank line completed, if any.
    mutating func feed(_ byte: UInt8) -> StudioEvent? {
        guard byte == 10 else {
            line.append(byte)
            return nil
        }
        if line.last == 13 { line.removeLast() }
        let event = handle(line)
        line.removeAll(keepingCapacity: true)
        return event
    }

    /// Feeds a chunk; returns every event completed in it, in order.
    mutating func feed<S: Sequence>(_ bytes: S) -> [StudioEvent] where S.Element == UInt8 {
        var out: [StudioEvent] = []
        for b in bytes { if let e = feed(b) { out.append(e) } }
        return out
    }

    private mutating func handle(_ raw: [UInt8]) -> StudioEvent? {
        let text = String(decoding: raw, as: UTF8.self)
        if text.isEmpty {
            let event = data.isEmpty ? nil : StudioEvent(name: name, data: Data(data.utf8))
            name = "message"
            data = ""
            return event
        } else if text.hasPrefix(":") {
            return nil
        } else if text.hasPrefix("event:") {
            name = text.dropFirst(6).trimmingCharacters(in: .whitespaces)
        } else if text.hasPrefix("data:") {
            data += (data.isEmpty ? "" : "\n") + text.dropFirst(5).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

/// Reads the Studio's event stream (text/event-stream) as an async sequence; the caller reconnects.
enum StudioEvents {
    static func stream(_ url: URL) -> AsyncThrowingStream<StudioEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var req = URLRequest(url: url)
                req.timeoutInterval = 3600
                req.setValue("text/event-stream", forHTTPHeaderField: "accept")
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    // Parsed byte by byte: `bytes.lines` drops the empty line that ends an event.
                    var parser = SSEParser()
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if let event = parser.feed(byte) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
