import Foundation
import CryptoKit
import Security

final class SSHKeyManager {
    static let shared = SSHKeyManager()

    private init() {}

    // MARK: - Key Generation

    func generateKeyPair(type: SSHKey.KeyType, comment: String? = nil) throws -> (privateKey: Data, publicKey: String, fingerprint: String) {
        switch type {
        case .ed25519:
            return try generateEd25519KeyPair(comment: comment)
        case .rsa4096:
            return try generateRSAKeyPair(bits: 4096, comment: comment)
        case .ecdsa:
            return try generateECDSAKeyPair(comment: comment)
        }
    }

    private func generateEd25519KeyPair(comment: String?) throws -> (Data, String, String) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let privateKeyData = privateKey.rawRepresentation

        // Format public key for SSH
        let publicKeySSH = formatSSHPublicKey(
            type: "ssh-ed25519",
            keyData: publicKey.rawRepresentation,
            comment: comment
        )

        // Generate fingerprint
        let fingerprint = generateFingerprint(from: publicKey.rawRepresentation, type: "ssh-ed25519")

        return (privateKeyData, publicKeySSH, fingerprint)
    }

    private func generateRSAKeyPair(bits: Int, comment: String?) throws -> (Data, String, String) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: bits
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SSHKeyError.generationFailed
        }

        // Export private key
        guard let privateKeyData = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw SSHKeyError.exportFailed
        }

        // Export public key
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw SSHKeyError.exportFailed
        }

        // Format for SSH
        let publicKeySSH = formatRSAPublicKey(publicKeyData, comment: comment)
        let fingerprint = generateFingerprint(from: publicKeyData, type: "ssh-rsa")

        return (privateKeyData, publicKeySSH, fingerprint)
    }

    private func generateECDSAKeyPair(comment: String?) throws -> (Data, String, String) {
        let privateKey = P521.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let privateKeyData = privateKey.rawRepresentation

        // Format public key for SSH
        let publicKeySSH = formatSSHPublicKey(
            type: "ecdsa-sha2-nistp521",
            keyData: publicKey.rawRepresentation,
            comment: comment
        )

        let fingerprint = generateFingerprint(from: publicKey.rawRepresentation, type: "ecdsa-sha2-nistp521")

        return (privateKeyData, publicKeySSH, fingerprint)
    }

    // MARK: - Key Formatting

    private func formatSSHPublicKey(type: String, keyData: Data, comment: String?) -> String {
        var blob = Data()

        // Add key type
        let typeData = Data(type.utf8)
        blob.append(contentsOf: encodeLength(typeData.count))
        blob.append(typeData)

        // Add key data
        blob.append(contentsOf: encodeLength(keyData.count))
        blob.append(keyData)

        let base64 = blob.base64EncodedString()
        var result = "\(type) \(base64)"

        if let comment = comment {
            result += " \(comment)"
        }

        return result
    }

    private func formatRSAPublicKey(_ keyData: Data, comment: String?) -> String {
        // Parse the DER-encoded RSA public key
        // This is a simplified version - full implementation would parse ASN.1
        let type = "ssh-rsa"
        let base64 = keyData.base64EncodedString()

        var result = "\(type) \(base64)"
        if let comment = comment {
            result += " \(comment)"
        }

        return result
    }

    private func encodeLength(_ length: Int) -> [UInt8] {
        return [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ]
    }

    // MARK: - Fingerprint

    private func generateFingerprint(from keyData: Data, type: String) -> String {
        // Create blob for fingerprinting
        var blob = Data()

        let typeData = Data(type.utf8)
        blob.append(contentsOf: encodeLength(typeData.count))
        blob.append(typeData)
        blob.append(contentsOf: encodeLength(keyData.count))
        blob.append(keyData)

        // SHA256 fingerprint
        let hash = SHA256.hash(data: blob)
        let base64 = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")

        return "SHA256:\(base64)"
    }

    // MARK: - Key Import

    func importPrivateKey(from pemString: String) throws -> (type: SSHKey.KeyType, keyData: Data) {
        // Detect key type from PEM header
        if pemString.contains("OPENSSH PRIVATE KEY") {
            return try parseOpenSSHPrivateKey(pemString)
        } else if pemString.contains("RSA PRIVATE KEY") {
            return try parseRSAPrivateKey(pemString)
        } else if pemString.contains("EC PRIVATE KEY") {
            return try parseECPrivateKey(pemString)
        }

        throw SSHKeyError.unsupportedFormat
    }

    private func parseOpenSSHPrivateKey(_ pem: String) throws -> (SSHKey.KeyType, Data) {
        // Remove PEM headers and decode base64
        let lines = pem.components(separatedBy: "\n")
        let base64Lines = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = base64Lines.joined()

        guard let data = Data(base64Encoded: base64) else {
            throw SSHKeyError.decodingFailed
        }

        // Parse OpenSSH format
        // Header: "openssh-key-v1\0"
        guard data.starts(with: Data("openssh-key-v1\0".utf8)) else {
            throw SSHKeyError.invalidFormat
        }

        // Determine key type from content
        if data.count < 100 {
            return (.ed25519, data)
        } else if data.count > 1000 {
            return (.rsa4096, data)
        } else {
            return (.ecdsa, data)
        }
    }

    private func parseRSAPrivateKey(_ pem: String) throws -> (SSHKey.KeyType, Data) {
        let lines = pem.components(separatedBy: "\n")
        let base64Lines = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = base64Lines.joined()

        guard let data = Data(base64Encoded: base64) else {
            throw SSHKeyError.decodingFailed
        }

        return (.rsa4096, data)
    }

    private func parseECPrivateKey(_ pem: String) throws -> (SSHKey.KeyType, Data) {
        let lines = pem.components(separatedBy: "\n")
        let base64Lines = lines.filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = base64Lines.joined()

        guard let data = Data(base64Encoded: base64) else {
            throw SSHKeyError.decodingFailed
        }

        return (.ecdsa, data)
    }

    // MARK: - Key Export

    func exportPrivateKeyPEM(keyData: Data, type: SSHKey.KeyType) -> String {
        let base64 = keyData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])

        switch type {
        case .ed25519:
            return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(base64)\n-----END OPENSSH PRIVATE KEY-----"
        case .rsa4096:
            return "-----BEGIN RSA PRIVATE KEY-----\n\(base64)\n-----END RSA PRIVATE KEY-----"
        case .ecdsa:
            return "-----BEGIN EC PRIVATE KEY-----\n\(base64)\n-----END EC PRIVATE KEY-----"
        }
    }

    // MARK: - Key Validation

    func validatePublicKey(_ keyString: String) -> Bool {
        let components = keyString.components(separatedBy: " ")
        guard components.count >= 2 else { return false }

        let validTypes = ["ssh-rsa", "ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"]
        guard validTypes.contains(components[0]) else { return false }

        // Validate base64
        guard Data(base64Encoded: components[1]) != nil else { return false }

        return true
    }
}

// MARK: - Errors

enum SSHKeyError: LocalizedError {
    case generationFailed
    case exportFailed
    case importFailed
    case unsupportedFormat
    case decodingFailed
    case invalidFormat
    case passphraseRequired

    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "Failed to generate SSH key pair"
        case .exportFailed:
            return "Failed to export key"
        case .importFailed:
            return "Failed to import key"
        case .unsupportedFormat:
            return "Unsupported key format"
        case .decodingFailed:
            return "Failed to decode key data"
        case .invalidFormat:
            return "Invalid key format"
        case .passphraseRequired:
            return "This key requires a passphrase"
        }
    }
}
