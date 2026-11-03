import Foundation
import Observation

/// The Apple Account session behind `asc web`: what the public App Store Connect API cannot do (create an app, create
/// an API key, read the Analytics dashboards) goes through it. Vitrin never keeps the password: it is handed to asc
/// for one run through the environment, and asc stores it in the keychain after a successful sign-in.
///
/// asc asks for the two-factor code by running a command, because it has no terminal here. That command is a small
/// script that says it was asked and waits for a file: the form then shows a code field and writes the file.
@MainActor @Observable final class AppleWebSession {
    static let shared = AppleWebSession()

    private(set) var authenticated = false
    private(set) var appleID = ""
    /// asc holds the password in the keychain, so only the code may be needed.
    private(set) var passwordStored = false
    /// Apple sent a code and asc is waiting for it.
    private(set) var needsCode = false

    private var folder: URL { AppSupport.base.appendingPathComponent("web-2fa", isDirectory: true) }
    private var codeFile: URL { folder.appendingPathComponent("code") }
    private var askedFile: URL { folder.appendingPathComponent("asked") }
    private var script: URL { folder.appendingPathComponent("code.sh") }

    func refresh() async {
        guard let o = (try? await AscCLI.json(["web", "auth", "status"]))?.objectValue else { return }
        apply(status: o)
    }

    func apply(status o: [String: JSONValue]) {
        authenticated = o["authenticated"]?.boolValue ?? false
        appleID = o["appleId"]?.stringValue ?? appleID
        passwordStored = o["passwordStored"]?.boolValue ?? false
    }

    /// The form's code: the waiting script picks it up.
    func submit(code: String) {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return }
        try? Data(digits.utf8).write(to: codeFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: codeFile.path)
        needsCode = false
    }

    func signIn(appleID: String, password: String) async throws {
        let r = try await run(["web", "auth", "login", "--apple-id", appleID, "--output", "json"], password: password)
        guard r.ok else { throw AscCLI.Failure(message: r.errorLine.replacingOccurrences(of: "Error: ", with: "")) }
        await refresh()
    }

    /// One `asc web` run that may have to sign in again on the way.
    func run(_ args: [String], password: String = "") async throws -> AscCLI.Result {
        try prepareBridge()
        var env = ["ASC_WEB_2FA_CODE_COMMAND": "/bin/sh '\(script.path)'"]
        if !password.isEmpty { env["ASC_WEB_PASSWORD"] = password }
        let watcher = Task { [askedFile] in
            while !Task.isCancelled {
                if FileManager.default.fileExists(atPath: askedFile.path) { needsCode = true; return }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer {
            watcher.cancel()
            needsCode = false
            try? FileManager.default.removeItem(at: folder)
        }
        return try await AscCLI.run(args, readOnly: false, timeout: 320, extraEnv: env)
    }

    private func prepareBridge() throws {
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(Self.scriptText(folder: folder.path).utf8).write(to: script, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    }

    /// Waits up to five minutes (asc's own run ends after that), prints the code, removes it.
    nonisolated static func scriptText(folder: String) -> String {
        """
        #!/bin/sh
        d='\(folder)'
        : > "$d/asked"
        i=0
        while [ ! -s "$d/code" ] && [ "$i" -lt 580 ]; do sleep 0.5; i=$((i+1)); done
        [ -s "$d/code" ] || exit 1
        cat "$d/code"
        rm -f "$d/code"
        """
    }
}
