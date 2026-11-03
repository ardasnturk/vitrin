import Foundation
import Observation

/// The first-run tour: what Vitrin does, the tools it needs, the App Store Connect key, the apps and project folders,
/// and the Claude model. Shown once (AppSettings.onboardingDone); Help → "Show the welcome tour" opens it again.
/// Every step after the first can be skipped: the app works without a key (local projects) and without Claude
/// (the briefs can be done by hand).
@MainActor @Observable final class Onboarding {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, tools, account, apps, claude, done
        var id: Int { rawValue }
        var titleKey: String { "onb.step.\(self)" }
        var symbol: String {
            switch self {
            case .welcome: return "sparkles.rectangle.stack"
            case .tools: return "wrench.and.screwdriver"
            case .account: return "key.horizontal"
            case .apps: return "square.grid.2x2"
            case .claude: return "brain"
            case .done: return "checkmark.seal"
            }
        }
    }

    /// One local tool the pipeline uses, found on the login shell's PATH.
    struct Tool: Identifiable, Hashable {
        enum Need { case required, recommended, optional }
        var id: String
        var name: String
        var purposeKey: String
        var need: Need
        var install: String
        var path: String?
        var found: Bool { path != nil }
    }

    var step: Step = .welcome
    private(set) var tools: [Tool] = []
    private(set) var checkingTools = false

    func next() { if let n = Step(rawValue: step.rawValue + 1) { step = n } }
    func back() { if let p = Step(rawValue: step.rawValue - 1) { step = p } }

    /// node, the Vitrin CLI, Claude Code, the asc CLI and ffmpeg, looked up the way the app runs them.
    func checkTools(cli: CLILocation?) async {
        checkingTools = true
        defer { checkingTools = false }
        func which(_ t: String) async -> String? { await ShellEnvironment.which(t) }
        var list: [Tool] = []
        list.append(Tool(id: "node", name: "Node.js 22+", purposeKey: "onb.tool.node", need: .required, install: "brew install node", path: try? await CLILocator.node()))
        list.append(Tool(id: "vitrin", name: "Vitrin CLI", purposeKey: "onb.tool.vitrin", need: .required, install: "npm install -g @ardasnturk/vitrin", path: cli.map { $0.version.map { "v\($0)" } ?? $0.executable }))
        list.append(Tool(id: "claude", name: "Claude Code", purposeKey: "onb.tool.claude", need: .recommended, install: "npm install -g @anthropic-ai/claude-code", path: await which("claude")))
        list.append(Tool(id: "asc", name: "asc CLI", purposeKey: "onb.tool.uploader", need: .recommended, install: AscCLI.installHint, path: await which("asc")))
        list.append(Tool(id: "ffmpeg", name: "ffmpeg", purposeKey: "onb.tool.ffmpeg", need: .optional, install: "brew install ffmpeg", path: await which("ffmpeg")))
        tools = list
    }

    var missingRequired: Bool { tools.contains { $0.need == .required && !$0.found } }
}
