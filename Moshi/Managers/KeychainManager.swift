import Foundation
import Security
import LocalAuthentication
import CryptoKit

final class KeychainManager {
    static let shared = KeychainManager()

    private let serviceName = "com.moshi.terminal"
    private let accessGroup: String? = nil // Use for app group sharing if needed

    private init() {}

    // MARK: - Password Storage

    func savePassword(_ password: String, for hostId: UUID) throws {
        let account = "host-\(hostId.uuidString)"

        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        try? deletePassword(for: hostId)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData
        ]

        // Use biometric authentication on real devices, simple accessibility on simulator
        #if targetEnvironment(simulator)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        if let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        ) {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getPassword(for hostId: UUID) throws -> String? {
        let account = "host-\(hostId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseOperationPrompt as String: "Authenticate to access SSH credentials"
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                return nil
            }
            return password

        case errSecItemNotFound:
            return nil

        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.authenticationFailed

        default:
            throw KeychainError.readFailed(status)
        }
    }

    func deletePassword(for hostId: UUID) throws {
        let account = "host-\(hostId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - SSH Key Storage

    func savePrivateKey(_ keyData: Data, for keyId: UUID, passphrase: String? = nil) throws {
        let account = "key-\(keyId.uuidString)"

        // Encrypt the key if passphrase provided
        let dataToStore: Data
        if let passphrase = passphrase {
            dataToStore = try encryptData(keyData, with: passphrase)
        } else {
            dataToStore = keyData
        }

        try? deletePrivateKey(for: keyId)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(serviceName).keys",
            kSecAttrAccount as String: account,
            kSecValueData as String: dataToStore
        ]

        // Use biometric authentication on real devices, simple accessibility on simulator
        #if targetEnvironment(simulator)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        #else
        if let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func getPrivateKey(for keyId: UUID, passphrase: String? = nil) throws -> Data? {
        let account = "key-\(keyId.uuidString)"

        let context = LAContext()
        context.localizedReason = "Access SSH key for authentication"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(serviceName).keys",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "Authenticate to access SSH key"
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }

            // Decrypt if passphrase provided
            if let passphrase = passphrase {
                return try decryptData(data, with: passphrase)
            }
            return data

        case errSecItemNotFound:
            return nil

        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.authenticationFailed

        default:
            throw KeychainError.readFailed(status)
        }
    }

    func deletePrivateKey(for keyId: UUID) throws {
        let account = "key-\(keyId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(serviceName).keys",
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Encryption Helpers

    private func encryptData(_ data: Data, with passphrase: String) throws -> Data {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Derive key from passphrase using SHA256
        let hash = SHA256.hash(data: passphraseData)
        let key = SymmetricKey(data: hash)

        // Encrypt using AES-GCM
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw KeychainError.encodingFailed
        }
        return combined
    }

    private func decryptData(_ data: Data, with passphrase: String) throws -> Data {
        guard let passphraseData = passphrase.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Derive key from passphrase using SHA256
        let hash = SHA256.hash(data: passphraseData)
        let key = SymmetricKey(data: hash)

        // Decrypt using AES-GCM
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Biometric Check

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func biometricType() -> String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        default:
            return "Biometrics"
        }
    }

    // MARK: - Clear All

    func clearAll() throws {
        let classes = [
            kSecClassGenericPassword,
            kSecClassInternetPassword,
            kSecClassCertificate,
            kSecClassKey,
            kSecClassIdentity
        ]

        for secClass in classes {
            let query: [String: Any] = [
                kSecClass as String: secClass,
                kSecAttrService as String: serviceName
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case authenticationFailed
    case notFound

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data"
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .readFailed(let status):
            return "Failed to read from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        case .authenticationFailed:
            return "Authentication failed"
        case .notFound:
            return "Item not found in keychain"
        }
    }
}
