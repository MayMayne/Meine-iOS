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
