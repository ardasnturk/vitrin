import Foundation

/// One server-sent event from `GET /api/events`.
struct StudioEvent: Sendable {
    var name: String
    var data: Data
    func decode<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(T.self, from: data) }
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
                    var name = "message"
                    var data = ""
                    var line: [UInt8] = []
                    func handle(_ raw: [UInt8]) {
                        let text = String(decoding: raw, as: UTF8.self)
                        if text.isEmpty {
                            if !data.isEmpty { continuation.yield(StudioEvent(name: name, data: Data(data.utf8))) }
                            name = "message"
                            data = ""
                        } else if text.hasPrefix(":") {
                            return
                        } else if text.hasPrefix("event:") {
                            name = text.dropFirst(6).trimmingCharacters(in: .whitespaces)
                        } else if text.hasPrefix("data:") {
                            data += (data.isEmpty ? "" : "\n") + text.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 10 {
                            if line.last == 13 { line.removeLast() }
                            handle(line)
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(byte)
                        }
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
