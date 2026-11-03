import SwiftUI

/// Installs a missing tool in place, with its progress and any failure under the button. The state is the app's
/// (`AppModel.installer`), so the same install shows wherever the tool is asked for.
struct ToolInstallButton: View {
    @Environment(AppModel.self) private var model
    var tool: LocalTool
    var prominent = true
    /// After an install ended, whichever tool it was: the caller reads again what it shows.
    var done: (() -> Void)?

    var body: some View {
        let installer = model.installer
        VStack(alignment: .leading, spacing: 6) {
            if installer.running == tool {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(installer.status).font(.callout).foregroundStyle(.secondary).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("tool.installing.\(tool.rawValue)")
            } else if prominent {
                button.buttonStyle(GradientButtonStyle(fullWidth: false))
            } else {
                button.controlSize(.small)
            }
            if let error = installer.errors[tool] {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }
        .onChange(of: model.installRevision) { done?() }
    }

    private var button: some View {
        Button(L.t(tool.installKey)) { Task { await model.install([tool]) } }
            .disabled(model.installer.busy)
            .accessibilityIdentifier("tool.install.\(tool.rawValue)")
    }
}
