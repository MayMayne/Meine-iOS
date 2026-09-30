import CommonCrypto
import CryptoKit
import Foundation
import Security

enum KeychainStore {
    static func set(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.meine.ios",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var next = query
        next[kSecValueData as String] = data
        next[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(next as CFDictionary, nil)
    }

    static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.meine.ios",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.meine.ios",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct PasswordHash: Codable, Equatable {
    var salt: Data
    var hash: Data
    var iterations: Int
}

enum SourcePasswordHasher {
    static let iterations = 120_000

    static func make(password: String, salt: Data = randomSalt()) -> PasswordHash {
        let hash = pbkdf2(password: password, salt: salt, iterations: iterations)
        return PasswordHash(salt: salt, hash: hash, iterations: iterations)
    }

    static func verify(password: String, stored: PasswordHash) -> Bool {
        let hash = pbkdf2(password: password, salt: stored.salt, iterations: stored.iterations)
        return hash == stored.hash
    }

    static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func pbkdf2(password: String, salt: Data, iterations: Int) -> Data {
        let passwordData = Data(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            passwordData.withUnsafeBytes { passwordBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    derived.count
                )
            }
        }
        if status != kCCSuccess {
            var material = Data(password.utf8)
            material.append(salt)
            for _ in 0..<max(1, iterations / 1000) {
                material = Data(SHA256.hash(data: material))
            }
            return material
        }
        return Data(derived)
    }
}

actor LRUDiskCache {
    let root: URL
    var quotaBytes: Int
    private var index: [String: Date] = [:]

    init(root: URL, quotaBytes: Int) {
        self.root = root
        self.quotaBytes = quotaBytes
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func put(key: String, data: Data) throws {
        let url = fileURL(key)
        try data.write(to: url, options: .atomic)
        index[key] = Date()
        try enforceQuota()
    }

    func get(key: String) -> Data? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        index[key] = Date()
        return data
    }

    func enforceQuota() throws {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        var sized: [(URL, Int, Date)] = files.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
        }
        var total = sized.reduce(0) { $0 + $1.1 }
        sized.sort { $0.2 < $1.2 }
        while total > quotaBytes, let first = sized.first {
            try? FileManager.default.removeItem(at: first.0)
            total -= first.1
            sized.removeFirst()
        }
    }

    private func fileURL(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent(safe)
    }
}

enum VaultCrypto {
    static func seal(plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw MeineError.transport("seal") }
        return combined
    }

    static func open(combined: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    static func key(from pin: String, salt: Data) -> SymmetricKey {
        let hash = SourcePasswordHasher.pbkdf2(password: pin, salt: salt, iterations: 50_000)
        return SymmetricKey(data: hash)
    }
}

struct MeineBackupPayload: Codable, Equatable {
    var schema: String
    var sources: [SourceManifest]
    var progress: [ProgressSnapshot]
    var contexts: [StoryAIContext]
    var themeHex: String
    var saturation: Double
    var brightness: Double
    var includeSecrets: Bool
    var apiKeyNote: String
}

enum BackupCodec {
    static let schema = "meine.backup.v1"

    static func export(payload: MeineBackupPayload, pin: String) throws -> Data {
        let json = try JSONEncoder().encode(payload)
        let salt = SourcePasswordHasher.randomSalt()
        let key = VaultCrypto.key(from: pin, salt: salt)
        let sealed = try VaultCrypto.seal(plaintext: json, key: key)
        var out = Data("MEINE1".utf8)
        out.append(salt)
        out.append(sealed)
        return out
    }

    static func restore(data: Data, pin: String) throws -> MeineBackupPayload {
        guard data.count > 6 + 16 else { throw MeineError.invalidSource }
        let magic = data.prefix(6)
        guard magic == Data("MEINE1".utf8) else { throw MeineError.invalidSource }
        let salt = data.subdata(in: 6..<22)
        let sealed = data.subdata(in: 22..<data.count)
        let key = VaultCrypto.key(from: pin, salt: salt)
        let json = try VaultCrypto.open(combined: sealed, key: key)
        return try JSONDecoder().decode(MeineBackupPayload.self, from: json)
    }
}
