import Foundation
import CryptoKit
import NIOSSH
import NIO

/// Stores and verifies SSH host keys to prevent MITM attacks
final class HostKeyStore {
    static let shared = HostKeyStore()

    private let userDefaults = UserDefaults.standard
    private let knownHostsKey = "known_hosts"

    // In-memory cache of known hosts
    private var knownHosts: [String: HostKeyInfo] = [:]

    private init() {
        loadKnownHosts()
    }

    // MARK: - Host Key Info

    struct HostKeyInfo: Codable {
        let fingerprint: String
        let keyType: String
        let firstSeen: Date
        let lastSeen: Date
        let hostname: String
        let port: Int

        var hostIdentifier: String {
            "\(hostname):\(port)"
        }
    }

    // MARK: - Verification Result

    enum VerificationResult {
        case trusted           // Key matches stored key
        case newHost           // First time connecting to this host
        case keyChanged        // Key differs from stored key (potential MITM!)
    }

    // MARK: - Public API

    /// Verify a host key and return the result
    func verify(hostKey: NIOSSHPublicKey, hostname: String, port: Int) -> VerificationResult {
        let hostId = "\(hostname):\(port)"
        let fingerprint = calculateFingerprint(hostKey)

        if let stored = knownHosts[hostId] {
            if stored.fingerprint == fingerprint {
                // Update last seen
                updateLastSeen(hostId: hostId)
                return .trusted
            } else {
                return .keyChanged
            }
        } else {
            return .newHost
        }
    }

    /// Store a host key as trusted
    func trustHostKey(_ hostKey: NIOSSHPublicKey, hostname: String, port: Int) {
        let hostId = "\(hostname):\(port)"
        let fingerprint = calculateFingerprint(hostKey)
        let keyType = getKeyType(hostKey)

        let info = HostKeyInfo(
            fingerprint: fingerprint,
            keyType: keyType,
            firstSeen: Date(),
            lastSeen: Date(),
            hostname: hostname,
            port: port
        )

        knownHosts[hostId] = info
        saveKnownHosts()

        Logger.network.info("Trusted new host key for \(hostname):\(port)")
    }

    /// Remove a stored host key
    func removeHostKey(hostname: String, port: Int) {
        let hostId = "\(hostname):\(port)"
        knownHosts.removeValue(forKey: hostId)
        saveKnownHosts()
    }

    /// Get stored host key info
    func getHostKeyInfo(hostname: String, port: Int) -> HostKeyInfo? {
        let hostId = "\(hostname):\(port)"
        return knownHosts[hostId]
    }

    /// Get all known hosts
    func getAllKnownHosts() -> [HostKeyInfo] {
        Array(knownHosts.values).sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Calculate fingerprint for display
    func calculateFingerprint(_ hostKey: NIOSSHPublicKey) -> String {
        // Serialize the key to SSH wire format and compute SHA256 fingerprint
        let keyData = serializePublicKey(hostKey)
        let hash = SHA256.hash(data: keyData)
        let base64 = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        return "SHA256:\(base64)"
    }

    /// Get a displayable fingerprint with colons
    func displayFingerprint(_ hostKey: NIOSSHPublicKey) -> String {
        let keyData = serializePublicKey(hostKey)
        let hash = SHA256.hash(data: keyData)

        // Format as colon-separated hex (traditional SSH style)
        return hash.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    /// Serialize a public key to SSH wire format
    private func serializePublicKey(_ hostKey: NIOSSHPublicKey) -> Data {
        var buffer = ByteBufferAllocator().buffer(capacity: 512)
        _ = hostKey.write(to: &buffer)
        return Data(buffer.readableBytesView)
    }

    // MARK: - Private

    private func getKeyType(_ hostKey: NIOSSHPublicKey) -> String {
        // Determine key type by checking the serialized key prefix
        let keyData = serializePublicKey(hostKey)

        // Check for key type prefixes in the serialized data
        if keyData.count > 11 {
            let prefix = String(data: keyData[4..<15], encoding: .utf8) ?? ""
            if prefix.hasPrefix("ssh-ed25519") {
                return "ED25519"
            } else if prefix.hasPrefix("ecdsa") {
                return "ECDSA"
            } else if prefix.hasPrefix("ssh-rsa") {
                return "RSA"
            }
        }

        return "Unknown"
    }

    private func updateLastSeen(hostId: String) {
        guard var info = knownHosts[hostId] else { return }
        info = HostKeyInfo(
            fingerprint: info.fingerprint,
            keyType: info.keyType,
            firstSeen: info.firstSeen,
            lastSeen: Date(),
            hostname: info.hostname,
            port: info.port
        )
        knownHosts[hostId] = info
        saveKnownHosts()
    }

    private func loadKnownHosts() {
        guard let data = userDefaults.data(forKey: knownHostsKey) else { return }

        do {
            let decoder = JSONDecoder()
            knownHosts = try decoder.decode([String: HostKeyInfo].self, from: data)
            Logger.network.info("Loaded \(knownHosts.count) known hosts")
        } catch {
            Logger.network.error("Failed to load known hosts: \(error.localizedDescription)")
        }
    }

    private func saveKnownHosts() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(knownHosts)
            userDefaults.set(data, forKey: knownHostsKey)
        } catch {
            Logger.network.error("Failed to save known hosts: \(error.localizedDescription)")
        }
    }
}

// MARK: - Custom Host Key Validator

/// A custom host key validator that integrates with HostKeyStore
final class InteractiveHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let hostname: String
    private let port: Int
    private let onNewHost: (NIOSSHPublicKey, String) async -> Bool
    private let onKeyChanged: (NIOSSHPublicKey, String, String) async -> Bool

    /// Creates a validator that calls back for user decisions
    /// - Parameters:
    ///   - hostname: The hostname being connected to
    ///   - port: The port being connected to
    ///   - onNewHost: Called when connecting to a new host. Returns true to trust.
    ///   - onKeyChanged: Called when host key changed. Returns true to trust (dangerous!).
    init(
        hostname: String,
        port: Int,
        onNewHost: @escaping (NIOSSHPublicKey, String) async -> Bool,
        onKeyChanged: @escaping (NIOSSHPublicKey, String, String) async -> Bool
    ) {
        self.hostname = hostname
        self.port = port
        self.onNewHost = onNewHost
        self.onKeyChanged = onKeyChanged
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let store = HostKeyStore.shared
        let result = store.verify(hostKey: hostKey, hostname: hostname, port: port)
        let fingerprint = store.displayFingerprint(hostKey)

        switch result {
        case .trusted:
            // Key matches, allow connection
            validationCompletePromise.succeed(())

        case .newHost:
            // First time connecting - ask user
            Task {
                let trusted = await onNewHost(hostKey, fingerprint)
                if trusted {
                    store.trustHostKey(hostKey, hostname: hostname, port: port)
                    validationCompletePromise.succeed(())
                } else {
                    validationCompletePromise.fail(HostKeyError.rejected)
                }
            }

        case .keyChanged:
            // Key changed - this is dangerous!
            let oldFingerprint = store.getHostKeyInfo(hostname: hostname, port: port)?.fingerprint ?? "unknown"
            Task {
                let trusted = await onKeyChanged(hostKey, fingerprint, oldFingerprint)
                if trusted {
                    // User accepted the new key - update store
                    store.removeHostKey(hostname: hostname, port: port)
                    store.trustHostKey(hostKey, hostname: hostname, port: port)
                    validationCompletePromise.succeed(())
                } else {
                    validationCompletePromise.fail(HostKeyError.keyChanged)
                }
            }
        }
    }
}

// MARK: - Errors

enum HostKeyError: LocalizedError {
    case rejected
    case keyChanged

    var errorDescription: String? {
        switch self {
        case .rejected:
            return "Host key rejected by user"
        case .keyChanged:
            return "Host key changed - possible security breach"
        }
    }
}
