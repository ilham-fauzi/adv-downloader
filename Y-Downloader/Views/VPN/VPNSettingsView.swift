import SwiftUI

/// Server, login and test controls for the SSH tunnel. Shown as a Settings tab and as a sheet in Simple mode.
struct VPNSettingsView: View {
    @Environment(SSHTunnelManager.self) private var tunnel
    @State private var keyDraft = ""
    @State private var passphraseDraft = ""
    @State private var passwordDraft = ""
    @State private var keyError: String?
    @State private var showKeyEditor = false

    var body: some View {
        let s = tunnel.settings
        @Bindable var v = tunnel.settings
        Form {
            Section {
                TextField("Server address", text: $v.host, prompt: Text("203.0.113.10 or vpn.example.com"))
                    .autocorrectionDisabled()
                TextField("SSH port", value: $v.sshPort, format: .number.grouping(.never))
                TextField("Username", text: $v.username, prompt: Text("root"))
                    .autocorrectionDisabled()
            } header: {
                Text("Server")
            } footer: {
                Text("The server you log in to with ssh. Only downloads from this app go through it; the rest of your Mac keeps its normal network.")
            }

            Section("Login") {
                Picker("Method", selection: $v.authMethod) {
                    ForEach(VPNAuthMethod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if s.authMethod == .key { keyFields(s) } else { passwordFields(s) }
            }

            Section {
                TextField("Local proxy port", value: $v.localPort, format: .number.grouping(.never))
            } header: {
                Text("Advanced")
            } footer: {
                Text("Port on this Mac used by the tunnel. Leave 1080 unless it is taken.")
            }

            Section("Test") {
                HStack {
                    Button("Test connection") { Task { await tunnel.test() } }
                        .disabled(tunnel.isTesting || tunnel.status.isConnecting)
                    Button("Forget server") { Task { await tunnel.forgetServer() } }
                        .help("Remove the saved fingerprint. You will be asked to trust the server again.")
                    if tunnel.isTesting { ProgressView().controlSize(.small) }
                }
                if let result = tunnel.testResult {
                    Text(result).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let missing = s.missingField {
                    Text(missing).font(.callout).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Key

    @ViewBuilder
    private func keyFields(_ s: VPNSettings) -> some View {
        if s.hasPrivateKey && !showKeyEditor {
            HStack {
                Label("Private key saved in Keychain", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Spacer()
                Button("Replace") { showKeyEditor = true }
                Button("Remove", role: .destructive) { s.removeKey(); keyDraft = "" }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Private key").font(.callout)
                TextEditor(text: $keyDraft)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("Paste the whole content of id_ed25519 or id_rsa, from -----BEGIN to -----END. Show it with: cat ~/.ssh/id_ed25519. Never share it with anyone.")
                    .font(.caption).foregroundStyle(.secondary)
                if let keyError { Text(keyError).font(.caption).foregroundStyle(.red) }
            }
        }
        SecureField("Key passphrase (optional)", text: $passphraseDraft,
                    prompt: Text(s.hasPassphrase ? "Saved. Type to replace" : "Only if the key has one"))
        HStack {
            Button("Save") { saveKey(s) }
                .disabled(keyDraft.isEmpty && passphraseDraft.isEmpty)
            if s.hasPassphrase {
                Button("Remove passphrase") { s.savePassphrase("") }
            }
        }
    }

    private func saveKey(_ s: VPNSettings) {
        keyError = nil
        if !keyDraft.isEmpty {
            do {
                try s.saveKey(keyDraft)
                keyDraft = ""
                showKeyEditor = false
            } catch {
                keyError = error.localizedDescription
                return
            }
        }
        if !passphraseDraft.isEmpty {
            s.savePassphrase(passphraseDraft)
            passphraseDraft = ""
        }
    }

    // MARK: - Password

    @ViewBuilder
    private func passwordFields(_ s: VPNSettings) -> some View {
        SecureField("Password", text: $passwordDraft,
                    prompt: Text(s.hasPassword ? "Saved. Type to replace" : "Your SSH login password"))
        HStack {
            Button("Save") { s.savePassword(passwordDraft); passwordDraft = "" }
                .disabled(passwordDraft.isEmpty)
            if s.hasPassword {
                Label("Saved in Keychain", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Button("Remove", role: .destructive) { s.removePassword() }
            }
        }
        Text("A key is safer than a password. Servers that only accept keys will refuse this.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// Toolbar control: a coloured dot shows the state, the popover has the on/off switch.
struct VPNToolbarButton: View {
    @Environment(SSHTunnelManager.self) private var tunnel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("VPN")
            }
        }
        .help(statusText)
        .accessibilityLabel("VPN \(statusText)")
        .popover(isPresented: $open, arrowEdge: .bottom) { VPNPopover().environment(tunnel) }
    }

    private var color: Color {
        switch tunnel.status {
        case .connected(_, let verified): return verified ? .green : .orange
        case .connecting: return .yellow
        case .failed: return .red
        case .disconnected: return tunnel.wantsVPN ? .red : .gray
        }
    }

    private var statusText: String {
        switch tunnel.status {
        case .disconnected: return "VPN off"
        case .connecting: return "VPN connecting…"
        case .connected: return "VPN connected"
        case .failed(let m): return "VPN error: \(m)"
        }
    }
}

struct VPNPopover: View {
    @Environment(SSHTunnelManager.self) private var tunnel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { tunnel.wantsVPN }, set: { tunnel.setOn($0) })) {
                Text("Connect by VPN").font(.headline)
            }
            .toggleStyle(.switch)
            .disabled(tunnel.status.isConnecting)

            Group {
                switch tunnel.status {
                case .disconnected:
                    Text("Downloads use your normal network.")
                case .connecting:
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Connecting…") }
                case .connected(let ip, let verified):
                    if verified {
                        Label("Connected. Exit IP \(ip ?? "unknown")", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Connected, but traffic could not pass through. The server may block TCP forwarding.",
                              systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)

            if tunnel.wantsVPN && !tunnel.status.isConnected {
                Text("Downloads are paused from using the network until the VPN is back.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            SettingsLink { Text("VPN settings…") }
        }
        .padding(14)
        .frame(width: 290)
    }
}
