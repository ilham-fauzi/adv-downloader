import Foundation

enum VPNAuthMethod: String, CaseIterable, Identifiable {
    case key, password
    var id: String { rawValue }
    var title: String { self == .key ? "SSH Key" : "Password" }
}

/// Connection details for the SSH tunnel. Non-secret fields live in UserDefaults;
/// the private key, passphrase and password live in the Keychain.
@Observable
final class VPNSettings {
    enum Account {
        static let privateKey = "privateKey"
        static let passphrase = "passphrase"
        static let password = "password"
    }

    var host: String = UserDefaults.standard.string(forKey: "vpnHost") ?? "" {
        didSet { UserDefaults.standard.set(host, forKey: "vpnHost") }
    }
    var sshPort: Int = UserDefaults.standard.object(forKey: "vpnSSHPort") as? Int ?? 22 {
        didSet { UserDefaults.standard.set(sshPort, forKey: "vpnSSHPort") }
    }
    var username: String = UserDefaults.standard.string(forKey: "vpnUser") ?? "" {
        didSet { UserDefaults.standard.set(username, forKey: "vpnUser") }
    }
    var localPort: Int = UserDefaults.standard.object(forKey: "vpnLocalPort") as? Int ?? 1080 {
        didSet { UserDefaults.standard.set(localPort, forKey: "vpnLocalPort") }
    }
    var authMethod: VPNAuthMethod = VPNAuthMethod(rawValue: UserDefaults.standard.string(forKey: "vpnAuth") ?? "") ?? .key {
        didSet { UserDefaults.standard.set(authMethod.rawValue, forKey: "vpnAuth") }
    }

    var hasPrivateKey: Bool = KeychainStore.has(Account.privateKey)
    var hasPassphrase: Bool = KeychainStore.has(Account.passphrase)
    var hasPassword: Bool = KeychainStore.has(Account.password)

    var proxyURL: String { "socks5h://127.0.0.1:\(localPort)" }

    /// nil when ready to connect, otherwise what is still missing.
    var missingField: String? {
        if host.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the server address." }
        if username.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter the username." }
        if !(1...65535).contains(sshPort) || !(1024...65535).contains(localPort) { return "Check the port numbers." }
        switch authMethod {
        case .key: if !hasPrivateKey { return "Paste your private key and save it." }
        case .password: if !hasPassword { return "Enter your password and save it." }
        }
        return nil
    }

    // MARK: - Credentials

    enum KeyError: LocalizedError {
        case empty, publicKey, notAKey
        var errorDescription: String? {
            switch self {
            case .empty: return "The key is empty."
            case .publicKey: return "That is the public key (.pub). Paste the private key instead, the file without .pub."
            case .notAKey: return "This does not look like a private key. Include the BEGIN and END lines."
            }
        }
    }

    /// Normalise line endings and make sure the key ends with a newline (ssh rejects it otherwise).
    static func normalizedKey(_ raw: String) throws -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if key.isEmpty { throw KeyError.empty }
        if key.hasPrefix("ssh-") || key.hasPrefix("ecdsa-") { throw KeyError.publicKey }
        guard key.hasPrefix("-----BEGIN"), key.contains("PRIVATE KEY-----"), key.contains("-----END") else {
            throw KeyError.notAKey
        }
        key += "\n"
        return key
    }

    func saveKey(_ raw: String) throws {
        let key = try Self.normalizedKey(raw)
        KeychainStore.set(key, for: Account.privateKey)
        hasPrivateKey = true
    }

    func savePassphrase(_ value: String) {
        if value.isEmpty { KeychainStore.remove(Account.passphrase) } else { KeychainStore.set(value, for: Account.passphrase) }
        hasPassphrase = !value.isEmpty
    }

    func savePassword(_ value: String) {
        if value.isEmpty { KeychainStore.remove(Account.password) } else { KeychainStore.set(value, for: Account.password) }
        hasPassword = !value.isEmpty
    }

    func removeKey() {
        KeychainStore.remove(Account.privateKey)
        KeychainStore.remove(Account.passphrase)
        hasPrivateKey = false
        hasPassphrase = false
    }

    func removePassword() { savePassword("") }
}
