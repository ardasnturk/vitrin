import Foundation

/// The Apple Ads API key pair. Apple Ads signs in with an EC (prime256v1) key: Apple keeps the public half, which the
/// user pastes into Apple Ads once; the private half stays here, owner-only, next to the App Store Connect key.
enum AppleAdsKey {
    static var privateKey: URL { AppSupport.base.appendingPathComponent("keys/apple-ads-private.pem") }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// The public key to paste into Apple Ads; the pair is generated the first time and reused after that, because a
    /// new pair would invalidate the one already uploaded.
    static func publicKey() async throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: privateKey.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let env = ProcessInfo.processInfo.environment
        if !fm.fileExists(atPath: privateKey.path) {
            let r = try await ProcessRunner.run("/usr/bin/openssl", ["ecparam", "-genkey", "-name", "prime256v1", "-noout", "-out", privateKey.path], environment: env)
            guard r.code == 0 else { throw Failure(message: r.stderr) }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKey.path)
        }
        let r = try await ProcessRunner.run("/usr/bin/openssl", ["ec", "-in", privateKey.path, "-pubout"], environment: env)
        guard r.code == 0, r.stdout.contains("BEGIN PUBLIC KEY") else { throw Failure(message: r.stderr) }
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Apple shows the three values as one block (`clientId SEARCHADS.…`, `teamId SEARCHADS.…`, `keyId …`): pasted
    /// whole into any of the fields, it fills all three.
    static func parse(block: String) -> (clientId: String, teamId: String, keyId: String)? {
        func value(_ name: String) -> String? {
            let pattern = "(?i)\(name)[\"'\\s:=]+([A-Za-z0-9._-]+)"
            guard let r = block.range(of: pattern, options: .regularExpression) else { return nil }
            return String(block[r]).replacingOccurrences(of: "(?i)^\(name)[\"'\\s:=]+", with: "", options: .regularExpression)
        }
        guard let c = value("clientId"), let t = value("teamId"), let k = value("keyId") else { return nil }
        return (c, t, k)
    }
}
