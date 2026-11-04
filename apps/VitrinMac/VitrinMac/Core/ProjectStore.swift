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

/// The project list, kept as JSON in ~/Library/Application Support/Vitrin/projects.json
/// (`VITRIN_APP_SUPPORT` names another folder: the UI tests keep theirs apart from the user's).
@MainActor @Observable final class ProjectStore {
    private(set) var projects: [Project] = []
    private let file: URL
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    init(base: URL = AppSupport.base) {
        file = base.appendingPathComponent("projects.json")
        reload()
        watch()
    }

    /// `vitrin hub` shares this file, and adds and removes projects from the phone.
    func reload() {
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([Project].self, from: data), list != projects { projects = list }
    }

    /// Every writer replaces the file with a rename, which only the folder sees.
    private func watch() {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.reload() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    @discardableResult
    func add(path: String) -> Project {
        reload()
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = projects.first(where: { $0.path == standardized }) { return existing }
        let p = Project(id: UUID().uuidString, path: standardized, addedAt: .now)
        projects.append(p)
        save()
        return p
    }

    func remove(_ id: String) {
        reload()
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
