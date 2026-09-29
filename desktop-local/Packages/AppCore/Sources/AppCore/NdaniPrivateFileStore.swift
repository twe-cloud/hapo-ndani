import Foundation
import os.log

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(Security)
import Security
#endif

public enum NdaniPrivateFileStoreError: Error, LocalizedError {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keychainError(OSStatus)
    case keyGenerationFailed
    case utf8EncodingFailed
    case fileNotFound(URL)
    case fileReadFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed(let detail):
            return "Encryption failed: \(detail)"
        case .decryptionFailed(let detail):
            return "Decryption failed: \(detail)"
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case .utf8EncodingFailed:
            return "Failed to encode string as UTF-8"
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .fileReadFailed(let url, let underlying):
            return "Failed to read \(url.path): \(underlying.localizedDescription)"
        }
    }
}

public enum NdaniPrivateFileStore {

    private static let logger = Logger(
        subsystem: "biz.nibiashara.ndani.desktop",
        category: "PrivateFileStore"
    )

    // MARK: - Keychain key management (macOS only)

    #if os(macOS)
    private static let keychainService = "biz.nibiashara.ndani.desktop"
    private static let keychainAccount = "fileStoreKey"

    /// Retrieve or create the 256-bit AES-GCM key stored in the Keychain.
    static func encryptionKey() throws -> SymmetricKey {
        // Try to load existing key
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }

        if status != errSecItemNotFound {
            throw NdaniPrivateFileStoreError.keychainError(status)
        }

        // Generate a new 256-bit key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecValueData as String:        keyData,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            var retryResult: AnyObject?
            let retryStatus = SecItemCopyMatching(query as CFDictionary, &retryResult)
            if retryStatus == errSecSuccess, let keyData = retryResult as? Data {
                return SymmetricKey(data: keyData)
            }
            throw NdaniPrivateFileStoreError.keychainError(retryStatus)
        }
        guard addStatus == errSecSuccess else {
            throw NdaniPrivateFileStoreError.keychainError(addStatus)
        }

        return newKey
    }

    /// Encrypt data using AES-GCM. Returns combined nonce + ciphertext + tag.
    static func encrypt(_ plaintext: Data) throws -> Data {
        let key = try encryptionKey()
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                throw NdaniPrivateFileStoreError.encryptionFailed("Failed to produce combined sealed box")
            }
            return combined
        } catch let error as NdaniPrivateFileStoreError {
            throw error
        } catch {
            throw NdaniPrivateFileStoreError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypt AES-GCM combined data (nonce + ciphertext + tag).
    static func decrypt(_ combined: Data) throws -> Data {
        let key = try encryptionKey()
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let error as NdaniPrivateFileStoreError {
            throw error
        } catch {
            throw NdaniPrivateFileStoreError.decryptionFailed(error.localizedDescription)
        }
    }
    #endif

    // MARK: - Write options

    public static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        return [.atomic, .completeFileProtection]
        #else
        return [.atomic]
        #endif
    }

    // MARK: - Throwing write methods

    /// Prepare a directory, creating it if needed.
    public static func preparePrivateDirectoryThrowing(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try excludeFromBackupThrowing(directory)
    }

    /// Write data to a private file. On macOS the data is encrypted at rest with AES-GCM.
    public static func writePrivateDataThrowing(_ data: Data, to file: URL) throws {
        try preparePrivateDirectoryThrowing(file.deletingLastPathComponent())

        #if os(macOS)
        let payload = try encrypt(data)
        #else
        let payload = data
        #endif

        try payload.write(to: file, options: writeOptions)
        try excludeFromBackupThrowing(file)
    }

    /// Write a UTF-8 string to a private file. On macOS the data is encrypted at rest.
    public static func writePrivateStringThrowing(_ content: String, to file: URL) throws {
        guard let data = content.data(using: .utf8) else {
            throw NdaniPrivateFileStoreError.utf8EncodingFailed
        }
        try writePrivateDataThrowing(data, to: file)
    }

    /// Set the backup-exclusion resource value (throwing variant).
    public static func excludeFromBackupThrowing(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    // MARK: - Read + decrypt

    /// Read and decrypt a private file. On macOS the data is decrypted from AES-GCM.
    /// On iOS, data is returned as-is (iOS relies on file protection).
    public static func readPrivateData(from file: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw NdaniPrivateFileStoreError.fileNotFound(file)
        }

        let raw: Data
        do {
            raw = try Data(contentsOf: file)
        } catch {
            throw NdaniPrivateFileStoreError.fileReadFailed(file, error)
        }

        #if os(macOS)
        return try decrypt(raw)
        #else
        return raw
        #endif
    }

    /// Read and decrypt a private file, returning its contents as a UTF-8 string.
    public static func readPrivateString(from file: URL) throws -> String {
        let data = try readPrivateData(from: file)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NdaniPrivateFileStoreError.decryptionFailed("Decrypted data is not valid UTF-8")
        }
        return string
    }

    // MARK: - Migration-safe read (decrypt, fall back to plaintext)

    /// Read a private file, trying decryption first and falling back to plaintext
    /// for files written before encryption was enabled. On successful plaintext
    /// fallback, the file is NOT re-encrypted automatically (caller should save
    /// through normal write path to encrypt).
    public static func readPrivateDataMigrating(from file: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        guard let raw = try? Data(contentsOf: file) else { return nil }

        #if os(macOS)
        // Try decryption first
        if let decrypted = try? decrypt(raw) {
            return decrypted
        }
        // Fall back to plaintext (pre-encryption data)
        return raw
        #else
        return raw
        #endif
    }

    /// Read a private file as a UTF-8 string, with plaintext migration fallback.
    public static func readPrivateStringMigrating(from file: URL) -> String? {
        guard let data = readPrivateDataMigrating(from: file) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Legacy convenience wrappers (non-throwing, log on failure)

    public static func preparePrivateDirectory(_ directory: URL) {
        do {
            try preparePrivateDirectoryThrowing(directory)
        } catch {
            logger.error("preparePrivateDirectory failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func writePrivateData(_ data: Data, to file: URL) {
        do {
            try writePrivateDataThrowing(data, to: file)
        } catch {
            logger.error("writePrivateData failed for \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func writePrivateString(_ content: String, to file: URL) {
        do {
            try writePrivateStringThrowing(content, to: file)
        } catch {
            logger.error("writePrivateString failed for \(file.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    public static func excludeFromBackup(_ url: URL) {
        do {
            try excludeFromBackupThrowing(url)
        } catch {
            logger.error("excludeFromBackup failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
