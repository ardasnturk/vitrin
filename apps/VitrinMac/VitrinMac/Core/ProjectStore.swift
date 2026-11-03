import Foundation
import Observation

/// A project the user added: a folder with (or soon with) `vitrin.config.yaml`.
struct Project: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var path: String
    var addedAt: Date
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var hasConfig: Bool { FileManager.default.fileExists(atPath: path + "/vitrin.config.yaml") }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// The project list, kept as JSON in ~/Library/Application Support/Vitrin/projects.json.
@MainActor @Observable final class ProjectStore {
    private(set) var projects: [Project] = []
    private let file: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vitrin", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        file = base.appendingPathComponent("projects.json")
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([Project].self, from: data) { projects = list }
    }

    @discardableResult
    func add(path: String) -> Project {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = projects.first(where: { $0.path == standardized }) { return existing }
        let p = Project(id: UUID().uuidString, path: standardized, addedAt: .now)
        projects.append(p)
        save()
        return p
    }

    func remove(_ id: String) {
        projects.removeAll { $0.id == id }
        save()
    }

    func project(_ id: String?) -> Project? { id.flatMap { id in projects.first { $0.id == id } } }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(projects).write(to: file, options: .atomic)
    }
}
