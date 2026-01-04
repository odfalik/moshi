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
        let privateKey = P256.Signing.PrivateKey()
        let publicKey = privateKey.publicKey

        let privateKeyData = privateKey.rawRepresentation

        // Format public key for SSH (ECDSA uses uncompressed point format)
        let publicKeySSH = formatECDSAPublicKey(
            curve: "nistp256",
            keyData: publicKey.x963Representation,
            comment: comment
        )

        let fingerprint = generateECDSAFingerprint(curve: "nistp256", keyData: publicKey.x963Representation)

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
        // Parse the DER-encoded RSA public key and convert to SSH format
        // DER format: SEQUENCE { INTEGER modulus, INTEGER exponent }
        // SSH format: string "ssh-rsa", mpint e, mpint n

        guard let (modulus, exponent) = parseRSAPublicKeyDER(keyData) else {
            // Fallback to raw base64 if parsing fails
            let base64 = keyData.base64EncodedString()
            return "ssh-rsa \(base64)" + (comment.map { " \($0)" } ?? "")
        }

        var blob = Data()
        let type = "ssh-rsa"

        // Add key type string
        let typeData = Data(type.utf8)
        blob.append(contentsOf: encodeLength(typeData.count))
        blob.append(typeData)

        // Add exponent (e) as mpint
        blob.append(contentsOf: encodeMPInt(exponent))

        // Add modulus (n) as mpint
        blob.append(contentsOf: encodeMPInt(modulus))

        let base64 = blob.base64EncodedString()
        var result = "\(type) \(base64)"
        if let comment = comment {
            result += " \(comment)"
        }

        return result
    }

    private func formatECDSAPublicKey(curve: String, keyData: Data, comment: String?) -> String {
        // SSH ECDSA format: string key-type, string curve, string Q (point)
        let keyType = "ecdsa-sha2-\(curve)"

        var blob = Data()

        // Add key type
        let typeData = Data(keyType.utf8)
        blob.append(contentsOf: encodeLength(typeData.count))
        blob.append(typeData)

        // Add curve identifier
        let curveData = Data(curve.utf8)
        blob.append(contentsOf: encodeLength(curveData.count))
        blob.append(curveData)

        // Add public key point (Q) in uncompressed format
        blob.append(contentsOf: encodeLength(keyData.count))
        blob.append(keyData)

        let base64 = blob.base64EncodedString()
        var result = "\(keyType) \(base64)"
        if let comment = comment {
            result += " \(comment)"
        }

        return result
    }

    private func parseRSAPublicKeyDER(_ data: Data) -> (modulus: Data, exponent: Data)? {
        // Parse ASN.1 DER encoded RSA public key
        // Format: SEQUENCE { INTEGER modulus, INTEGER exponent }
        var offset = 0

        // Check SEQUENCE tag (0x30)
        guard offset < data.count, data[offset] == 0x30 else { return nil }
        offset += 1

        // Skip sequence length
        guard let seqLength = parseDERLength(data, offset: &offset) else { return nil }
        _ = seqLength  // We don't need to validate the exact length

        // Parse modulus INTEGER
        guard offset < data.count, data[offset] == 0x02 else { return nil }
        offset += 1
        guard let modulusLength = parseDERLength(data, offset: &offset) else { return nil }
        guard offset + modulusLength <= data.count else { return nil }
        let modulus = data[offset..<(offset + modulusLength)]
        offset += modulusLength

        // Parse exponent INTEGER
        guard offset < data.count, data[offset] == 0x02 else { return nil }
        offset += 1
        guard let exponentLength = parseDERLength(data, offset: &offset) else { return nil }
        guard offset + exponentLength <= data.count else { return nil }
        let exponent = data[offset..<(offset + exponentLength)]

        return (Data(modulus), Data(exponent))
    }

    private func parseDERLength(_ data: Data, offset: inout Int) -> Int? {
        guard offset < data.count else { return nil }

        let firstByte = data[offset]
        offset += 1

        if firstByte < 0x80 {
            // Short form: length is in the first byte
            return Int(firstByte)
        } else {
            // Long form: first byte indicates number of length bytes
            let numLengthBytes = Int(firstByte & 0x7F)
            guard offset + numLengthBytes <= data.count else { return nil }

            var length = 0
            for _ in 0..<numLengthBytes {
                length = (length << 8) | Int(data[offset])
                offset += 1
            }
            return length
        }
    }

    private func encodeMPInt(_ data: Data) -> Data {
        var result = Data()

        // Remove leading zeros but keep one if the high bit is set
        var trimmed = data
        while trimmed.count > 1 && trimmed.first == 0 {
            trimmed = trimmed.dropFirst()
        }

        // If high bit is set, prepend a zero byte (SSH mpint is signed)
        if let first = trimmed.first, first & 0x80 != 0 {
            result.append(contentsOf: encodeLength(trimmed.count + 1))
            result.append(0)
            result.append(trimmed)
        } else {
            result.append(contentsOf: encodeLength(trimmed.count))
            result.append(trimmed)
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

    private func generateECDSAFingerprint(curve: String, keyData: Data) -> String {
        // ECDSA fingerprint needs the full SSH blob format
        let keyType = "ecdsa-sha2-\(curve)"
        var blob = Data()

        // Add key type
        let typeData = Data(keyType.utf8)
        blob.append(contentsOf: encodeLength(typeData.count))
        blob.append(typeData)

        // Add curve identifier
        let curveData = Data(curve.utf8)
        blob.append(contentsOf: encodeLength(curveData.count))
        blob.append(curveData)

        // Add public key point
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
        let header = "openssh-key-v1\0"
        guard data.starts(with: Data(header.utf8)) else {
            throw SSHKeyError.invalidFormat
        }

        // Parse the key type from the OpenSSH format
        // Format after header: ciphername (string), kdfname (string), kdfoptions (string),
        //                      number of keys (uint32), public key (string), private key (string)
        var offset = header.count

        // Skip ciphername
        guard let cipherLen = readUInt32(from: data, at: &offset) else {
            throw SSHKeyError.invalidFormat
        }
        offset += Int(cipherLen)

        // Skip kdfname
        guard let kdfLen = readUInt32(from: data, at: &offset) else {
            throw SSHKeyError.invalidFormat
        }
        offset += Int(kdfLen)

        // Skip kdfoptions
        guard let kdfOptsLen = readUInt32(from: data, at: &offset) else {
            throw SSHKeyError.invalidFormat
        }
        offset += Int(kdfOptsLen)

        // Skip number of keys
        guard readUInt32(from: data, at: &offset) != nil else {
            throw SSHKeyError.invalidFormat
        }

        // Read public key blob
        guard let pubKeyLen = readUInt32(from: data, at: &offset) else {
            throw SSHKeyError.invalidFormat
        }

        // Read key type from public key blob
        guard let keyTypeLen = readUInt32(from: data, at: &offset) else {
            throw SSHKeyError.invalidFormat
        }

        guard offset + Int(keyTypeLen) <= data.count else {
            throw SSHKeyError.invalidFormat
        }

        let keyTypeData = data[offset..<(offset + Int(keyTypeLen))]
        guard let keyTypeString = String(data: keyTypeData, encoding: .utf8) else {
            throw SSHKeyError.invalidFormat
        }

        // Determine key type from the parsed string
        let keyType: SSHKey.KeyType
        if keyTypeString.contains("ed25519") {
            keyType = .ed25519
        } else if keyTypeString.contains("rsa") {
            keyType = .rsa4096
        } else if keyTypeString.contains("ecdsa") {
            keyType = .ecdsa
        } else {
            throw SSHKeyError.unsupportedFormat
        }

        return (keyType, data)
    }

    private func readUInt32(from data: Data, at offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let value = UInt32(data[offset]) << 24 |
                    UInt32(data[offset + 1]) << 16 |
                    UInt32(data[offset + 2]) << 8 |
                    UInt32(data[offset + 3])
        offset += 4
        return value
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
