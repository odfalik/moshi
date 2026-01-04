import Foundation
import SwiftUI

struct Host: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var hostname: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var useMosh: Bool
    var moshPorts: MoshPortRange
    var autoTmux: Bool
    var tmuxSessionName: String?
    var startupCommand: String?
    var group: String?
    var notes: String?
    var lastConnected: Date?
    var isFavorite: Bool
    var colorTag: ColorTag?

    // SSH specific settings
    var sshKeyId: UUID?
    var proxyJump: String?
    var keepAliveInterval: Int
    var compression: Bool
    var strictHostKeyChecking: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        hostname: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: AuthMethod = .password,
        useMosh: Bool = false,  // Mosh not implemented yet
        moshPorts: MoshPortRange = MoshPortRange(),
        autoTmux: Bool = true,
        tmuxSessionName: String? = nil,
        startupCommand: String? = nil,
        group: String? = nil,
        notes: String? = nil,
        lastConnected: Date? = nil,
        isFavorite: Bool = false,
        colorTag: ColorTag? = nil,
        sshKeyId: UUID? = nil,
        proxyJump: String? = nil,
        keepAliveInterval: Int = 60,
        compression: Bool = false,
        strictHostKeyChecking: Bool = true
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.useMosh = useMosh
        self.moshPorts = moshPorts
        self.autoTmux = autoTmux
        self.tmuxSessionName = tmuxSessionName
        self.startupCommand = startupCommand
        self.group = group
        self.notes = notes
        self.lastConnected = lastConnected
        self.isFavorite = isFavorite
        self.colorTag = colorTag
        self.sshKeyId = sshKeyId
        self.proxyJump = proxyJump
        self.keepAliveInterval = keepAliveInterval
        self.compression = compression
        self.strictHostKeyChecking = strictHostKeyChecking
    }

    var displayName: String {
        name.isEmpty ? hostname : name
    }

    var connectionString: String {
        "\(username)@\(hostname):\(port)"
    }

    var effectiveTmuxSessionName: String {
        tmuxSessionName ?? "moshi-\(hostname.replacingOccurrences(of: ".", with: "-"))"
    }
}

// MARK: - Auth Method

enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password = "Password"
    case key = "SSH Key"
    case keyAndPassword = "SSH Key + Password"
    case agent = "SSH Agent"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .password: return "key.fill"
        case .key: return "key.horizontal"
        case .keyAndPassword: return "key.horizontal.fill"
        case .agent: return "person.badge.key"
        }
    }
}

// MARK: - Mosh Port Range

struct MoshPortRange: Codable, Hashable {
    var start: Int
    var end: Int

    init(start: Int = 60000, end: Int = 61000) {
        self.start = start
        self.end = end
    }

    var range: ClosedRange<Int> {
        start...end
    }

    var description: String {
        "\(start)-\(end)"
    }
}

// MARK: - Color Tag

enum ColorTag: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }
}

// MARK: - Host Group

struct HostGroup: Identifiable, Hashable {
    let id: String
    let name: String
    var hosts: [Host]

    init(name: String, hosts: [Host] = []) {
        self.id = name
        self.name = name
        self.hosts = hosts
    }
}

// MARK: - SSH Key

struct SSHKey: Identifiable, Codable {
    let id: UUID
    var name: String
    var type: KeyType
    var publicKey: String
    var fingerprint: String
    var createdAt: Date
    var comment: String?

    enum KeyType: String, Codable, CaseIterable {
        case ed25519 = "Ed25519"
        case rsa4096 = "RSA 4096"
        case ecdsa = "ECDSA"

        var algorithm: String {
            switch self {
            case .ed25519: return "ed25519"
            case .rsa4096: return "rsa"
            case .ecdsa: return "ecdsa"
            }
        }

        var bits: Int? {
            switch self {
            case .ed25519: return nil
            case .rsa4096: return 4096
            case .ecdsa: return 521
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: KeyType,
        publicKey: String,
        fingerprint: String,
        createdAt: Date = Date(),
        comment: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.comment = comment
    }
}
