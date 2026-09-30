#!/usr/bin/env python3
from pathlib import Path
ROOT = Path("/var/minis/workspace/Meine-iOS/Meine")

def put(rel, text):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n")
    print("wrote", rel, path.stat().st_size)

put("Source/SourceEngine.swift", r'''
import Foundation

enum UpstreamKind: String, Codable, Sendable {
    case scraper, rest, graphql, googleDrivePublic, oneDrive, dropbox, webdav, local
}

struct UpstreamDescriptor: Codable, Sendable, Equatable {
    var id: String
    var kind: UpstreamKind
    var config: JSONValue
}

struct SourceManifest: Codable, Sendable, Equatable {
    var id: SourceID
    var name: String
    var version: String
    var updateURL: URL?
    var passwordProtected: Bool
    var upstreams: [UpstreamDescriptor]
    var mirrors: [URL]
    var home: SDUINode?
    var catalog: [CatalogItem]

    init(
        id: SourceID,
        name: String,
        version: String = "1",
        updateURL: URL? = nil,
        passwordProtected: Bool = false,
        upstreams: [UpstreamDescriptor] = [],
        mirrors: [URL] = [],
        home: SDUINode? = nil,
        catalog: [CatalogItem] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.updateURL = updateURL
        self.passwordProtected = passwordProtected
        self.upstreams = upstreams
        self.mirrors = mirrors
        self.home = home
        self.catalog = catalog
    }
}

enum SDUINode: Codable, Sendable, Equatable {
    case vStack(children: [SDUINode], spacing: Double?)
    case hStack(children: [SDUINode], spacing: Double?)
    case zStack(children: [SDUINode])
    case scroll(child: SDUINode)
    case text(value: String)
    case symbol(name: String)
    case mediaCard(itemID: String)
    case hero(itemIDs: [String])
    case grid(columns: Int, children: [SDUINode])
    case spacer
    case unknown(type: String)

    private enum Kind: String, Codable {
        case vStack, hStack, zStack, scroll, text, symbol, mediaCard, hero, grid, spacer
    }

    private enum CodingKeys: String, CodingKey { case type, children, child, spacing, value, name, itemID, itemIDs, columns }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let type = try box.decode(String.self, forKey: .type)
        switch type {
        case "vStack":
            self = .vStack(children: try box.decodeIfPresent([SDUINode].self, forKey: .children) ?? [], spacing: try box.decodeIfPresent(Double.self, forKey: .spacing))
        case "hStack":
            self = .hStack(children: try box.decodeIfPresent([SDUINode].self, forKey: .children) ?? [], spacing: try box.decodeIfPresent(Double.self, forKey: .spacing))
        case "zStack":
            self = .zStack(children: try box.decodeIfPresent([SDUINode].self, forKey: .children) ?? [])
        case "scroll":
            if let child = try box.decodeIfPresent(SDUINode.self, forKey: .child) {
                self = .scroll(child: child)
            } else {
                let children = try box.decodeIfPresent([SDUINode].self, forKey: .children) ?? []
                self = .scroll(child: .vStack(children: children, spacing: 12))
            }
        case "text":
            self = .text(value: try box.decodeIfPresent(String.self, forKey: .value) ?? "")
        case "symbol":
            self = .symbol(name: try box.decodeIfPresent(String.self, forKey: .name) ?? "circle")
        case "mediaCard":
            self = .mediaCard(itemID: try box.decodeIfPresent(String.self, forKey: .itemID) ?? "")
        case "hero":
            self = .hero(itemIDs: try box.decodeIfPresent([String].self, forKey: .itemIDs) ?? [])
        case "grid":
            self = .grid(columns: try box.decodeIfPresent(Int.self, forKey: .columns) ?? 2, children: try box.decodeIfPresent([SDUINode].self, forKey: .children) ?? [])
        case "spacer":
            self = .spacer
        default:
            self = .unknown(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vStack(let children, let spacing):
            try box.encode("vStack", forKey: .type)
            try box.encode(children, forKey: .children)
            try box.encodeIfPresent(spacing, forKey: .spacing)
        case .hStack(let children, let spacing):
            try box.encode("hStack", forKey: .type)
            try box.encode(children, forKey: .children)
            try box.encodeIfPresent(spacing, forKey: .spacing)
        case .zStack(let children):
            try box.encode("zStack", forKey: .type)
            try box.encode(children, forKey: .children)
        case .scroll(let child):
            try box.encode("scroll", forKey: .type)
            try box.encode(child, forKey: .child)
        case .text(let value):
            try box.encode("text", forKey: .type)
            try box.encode(value, forKey: .value)
        case .symbol(let name):
            try box.encode("symbol", forKey: .type)
            try box.encode(name, forKey: .name)
        case .mediaCard(let itemID):
            try box.encode("mediaCard", forKey: .type)
            try box.encode(itemID, forKey: .itemID)
        case .hero(let itemIDs):
            try box.encode("hero", forKey: .type)
            try box.encode(itemIDs, forKey: .itemIDs)
        case .grid(let columns, let children):
            try box.encode("grid", forKey: .type)
            try box.encode(columns, forKey: .columns)
            try box.encode(children, forKey: .children)
        case .spacer:
            try box.encode("spacer", forKey: .type)
        case .unknown(let type):
            try box.encode(type, forKey: .type)
        }
    }
}

enum ClipboardSourceDetector {
    static func detect(_ string: String) -> SourceManifest? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("\"id\""), trimmed.contains("\"upstreams\"") || trimmed.contains("\"catalog\"") else {
            return nil
        }
        return try? SourceImporter.decode(trimmed)
    }
}

enum SourceImporter {
    static func decode(_ text: String) throws -> SourceManifest {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { throw MeineError.invalidSource }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(SourceManifest.self, from: data), !manifest.id.rawValue.isEmpty else {
            throw MeineError.invalidSource
        }
        return manifest
    }

    static func importRawJSON(_ text: String) throws -> SourceManifest { try decode(text) }

    static func importQRPayload(_ payload: String) throws -> SourceManifest {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return try decode(trimmed) }
        if let data = Data(base64Encoded: trimmed), let text = String(data: data, encoding: .utf8) {
            return try decode(text)
        }
        throw MeineError.invalidSource
    }

    static func importFile(_ url: URL) throws -> SourceManifest {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw MeineError.invalidSource }
        return try decode(text)
    }
}

enum DrivePublicResolver {
    static func folderID(from link: String) -> String? {
        guard let url = URL(string: link) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(of: "folders"), parts.count > index + 1 {
            let id = parts[index + 1]
            return id.split(separator: "?").first.map(String.init)
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let id = items.first(where: { $0.name == "id" })?.value, !id.isEmpty {
            return id
        }
        return nil
    }

    static func directDownload(fileID: String) -> URL? {
        URL(string: "https://drive.google.com/uc?export=download&id=\(fileID)")
    }
}

enum StreamResolver {
    static func firstHealthy(preferred: URL, mirrors: [URL], status: (URL) -> Int) -> URL? {
        let chain = [preferred] + mirrors
        for url in chain {
            let code = status(url)
            if code == 200 || code == 206 { return url }
            if code == 403 || code == 404 || code == 0 { continue }
            if (200..<400).contains(code) { return url }
        }
        return nil
    }
}

enum ETagDecision {
    static func shouldReplace(status: Int) -> Bool { status == 200 }
    static func isUnchanged(status: Int) -> Bool { status == 304 }
}

struct ScrapeRule: Equatable {
    var itemPattern: String
    var titleGroup: Int
    var hrefGroup: Int
}

enum ScraperUpstream {
    static func extract(html: String, rule: ScrapeRule) -> [(title: String, href: String)] {
        guard let regex = try? NSRegularExpression(pattern: rule.itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        var rows: [(String, String)] = []
        regex.enumerateMatches(in: html, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            func group(_ index: Int) -> String {
                guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound else { return "" }
                return ns.substring(with: match.range(at: index))
            }
            let title = group(rule.titleGroup).trimmingCharacters(in: .whitespacesAndNewlines)
            let href = group(rule.hrefGroup).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !href.isEmpty { rows.append((title, href)) }
        }
        return rows
    }
}
''')

put("Persistence/SecurityStore.swift", r'''
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

import CommonCrypto

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
''')

print("source+persistence queued")
