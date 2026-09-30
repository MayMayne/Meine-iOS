import CryptoKit
import Foundation

enum HeuristicChapterSplitter {
    static func split(_ text: String) -> [TextChapter] {
        let patterns = [
            #"^(Quyển|Tập|Phần|Book|Volume)\s+([0-9IVXLCDM]+|[一二三四五六七八九十]+)[\s:：\-\.](.*)?$"#,
            #"^(Chương|Hồi|Tiết|Thứ|Chapter|Chap)\s+([0-9IVXLCDM]+)[\s:：\-\.](.*)?$"#
        ]
        let regexes: [NSRegularExpression] = patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines, .caseInsensitive])
        }
        guard !regexes.isEmpty else {
            return [TextChapter(id: "toan-van", title: "Toàn văn", body: text)]
        }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var hits: [(range: NSRange, title: String)] = []
        for regex in regexes {
            regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match else { return }
                let line = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return }
                hits.append((match.range, line))
            }
        }
        hits.sort { $0.range.location < $1.range.location }
        var unique: [(range: NSRange, title: String)] = []
        var seen = Set<Int>()
        for hit in hits where seen.insert(hit.range.location).inserted {
            unique.append(hit)
        }
        guard !unique.isEmpty else {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return [TextChapter(id: "toan-van", title: "Toàn văn", body: body.isEmpty ? text : body)]
        }
        var chapters: [TextChapter] = []
        for (index, hit) in unique.enumerated() {
            let bodyStart = hit.range.location + hit.range.length
            let bodyEnd = index + 1 < unique.count ? unique[index + 1].range.location : ns.length
            let length = max(0, bodyEnd - bodyStart)
            let body = ns.substring(with: NSRange(location: bodyStart, length: length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let slug = NovelSlug.make(hit.title, index: index)
            chapters.append(TextChapter(id: slug, title: hit.title, body: body))
        }
        return chapters
    }
}

enum EPUBTOCParser {
    static func chapters(fromEPUB data: Data) -> [TextChapter] {
        guard let files = NovelStoredZIP.extract(data) else { return [] }
        let opfPath = containerOPFPath(files: files)
        let opf = opfPath.flatMap { files[$0] }.flatMap { String(data: $0, encoding: .utf8) }
        let base = opfPath.map { NovelPath.parent($0) } ?? ""
        let manifest = opf.map { parseManifest($0) } ?? [:]
        let spine = opf.map { parseSpine($0, manifest: manifest) } ?? []
        let tocBytes = locateTOC(files: files, opf: opf, base: base)
        let titles: [(href: String, title: String)] = tocBytes.flatMap { bytes in
            guard let xml = String(data: bytes, encoding: .utf8) else { return [] }
            if xml.contains("<navPoint") || xml.contains("navPoint") {
                return parseNCX(xml)
            }
            return parseNav(xml)
        } ?? []
        if titles.isEmpty && spine.isEmpty { return [] }
        var chapters: [TextChapter] = []
        let entries: [(href: String, title: String)] = titles.isEmpty
            ? spine.enumerated().map { ("\($0.element)", "Chương \($0.offset + 1)") }
            : titles
        for (index, entry) in entries.enumerated() {
            let resolved = NovelPath.resolve(entry.href, base: base)
            let html = lookup(files: files, href: resolved) ?? lookup(files: files, href: entry.href)
            let body = html.flatMap { String(data: $0, encoding: .utf8) }.map(NovelHTMLText.strip) ?? ""
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let safeTitle = title.isEmpty ? "Chương \(index + 1)" : title
            chapters.append(TextChapter(id: NovelSlug.make(safeTitle, index: index), title: safeTitle, body: body))
        }
        return chapters
    }

    private static func containerOPFPath(files: [String: Data]) -> String? {
        let key = files.keys.first { $0.lowercased().hasSuffix("meta-inf/container.xml") || $0.lowercased() == "meta-inf/container.xml" }
        guard let key, let xml = String(data: files[key] ?? Data(), encoding: .utf8) else { return nil }
        return NovelXML.attr("full-path", in: xml)
    }

    private static func locateTOC(files: [String: Data], opf: String?, base: String) -> Data? {
        if let opf {
            if let href = NovelXML.attr("href", near: "application/x-dtbncx+xml", in: opf)
                ?? NovelXML.attr("href", near: "nav", in: opf) {
                let path = NovelPath.resolve(href, base: base)
                if let data = lookup(files: files, href: path) ?? lookup(files: files, href: href) {
                    return data
                }
            }
        }
        let preferred = files.keys.first { key in
            let lower = key.lowercased()
            return lower.hasSuffix("toc.ncx") || lower.hasSuffix("nav.xhtml") || lower.hasSuffix("nav.html")
        }
        return preferred.flatMap { files[$0] }
    }

    private static func lookup(files: [String: Data], href: String) -> Data? {
        let clean = NovelPath.dropFragment(href)
        if let hit = files[clean] { return hit }
        let lower = clean.lowercased()
        return files.first { $0.key.lowercased() == lower || $0.key.lowercased().hasSuffix("/" + lower) }?.value
    }

    private static func parseManifest(_ opf: String) -> [String: String] {
        var map: [String: String] = [:]
        let pattern = #"<item\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return map }
        let ns = opf as NSString
        regex.enumerateMatches(in: opf, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let tag = ns.substring(with: match.range)
            guard let id = NovelXML.attr("id", in: tag), let href = NovelXML.attr("href", in: tag) else { return }
            map[id] = href
        }
        return map
    }

    private static func parseSpine(_ opf: String, manifest: [String: String]) -> [String] {
        let pattern = #"<itemref\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = opf as NSString
        var hrefs: [String] = []
        regex.enumerateMatches(in: opf, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let tag = ns.substring(with: match.range)
            guard let idref = NovelXML.attr("idref", in: tag), let href = manifest[idref] else { return }
            hrefs.append(href)
        }
        return hrefs
    }

    private static func parseNCX(_ xml: String) -> [(href: String, title: String)] {
        let pattern = #"<navPoint\b[^>]*>[\s\S]*?</navPoint>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = xml as NSString
        var rows: [(href: String, title: String)] = []
        regex.enumerateMatches(in: xml, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let block = ns.substring(with: match.range)
            let title = NovelXML.text("text", in: block) ?? ""
            let href = NovelXML.attr("src", in: block) ?? ""
            guard !href.isEmpty else { return }
            rows.append((href, title))
        }
        return rows
    }

    private static func parseNav(_ xml: String) -> [(href: String, title: String)] {
        let pattern = #"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = xml as NSString
        var rows: [(href: String, title: String)] = []
        regex.enumerateMatches(in: xml, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }
            let href = ns.substring(with: match.range(at: 1))
            let raw = ns.substring(with: match.range(at: 2))
            let title = NovelHTMLText.strip(raw)
            guard !href.isEmpty else { return }
            rows.append((href, title))
        }
        return rows
    }
}

enum TranslationContinue {
    static func cacheKey(chapterID: String, original: String) -> String {
        sha256Hex("\(chapterID)|\(original)")
    }

    static func shouldSkip(storyID: String, chapterID: String, original: String, cacheKeys: Set<String>) -> Bool {
        _ = storyID
        return cacheKeys.contains(cacheKey(chapterID: chapterID, original: original))
    }

    static func sha256Hex(_ raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum CharacterAnchorLock {
    static func paragraphIndex(offset: Int, in paragraphs: [String]) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        if offset <= 0 { return 0 }
        var cursor = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let next = cursor + paragraph.utf16.count
            if offset < next { return index }
            cursor = next + 1
        }
        return paragraphs.count - 1
    }

    static func offsetFor(paragraphIndex: Int, in paragraphs: [String]) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        let clamped = min(max(paragraphIndex, 0), paragraphs.count - 1)
        var cursor = 0
        for index in 0..<clamped {
            cursor += paragraphs[index].utf16.count + 1
        }
        return cursor
    }
}

enum NovelGenrePresets {
    static let genrePresets: [String] = [
        "Tiên Hiệp Cổ Phong",
        "Đô Thị Hiện Đại"
    ]
}

private enum NovelSlug {
    static func make(_ title: String, index: Int) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
        let allowed = folded.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        var slug = String(allowed)
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "chuong" }
        return "\(index)-\(slug)"
    }
}

private enum NovelPath {
    static func parent(_ path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let slash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[..<slash])
    }

    static func dropFragment(_ href: String) -> String {
        guard let hash = href.firstIndex(of: "#") else { return href }
        return String(href[..<hash])
    }

    static func resolve(_ href: String, base: String) -> String {
        let clean = dropFragment(href).removingPercentEncoding ?? dropFragment(href)
        if clean.hasPrefix("/") { return String(clean.dropFirst()) }
        if base.isEmpty { return clean }
        return base + "/" + clean
    }
}

private enum NovelXML {
    static func attr(_ name: String, in xml: String) -> String? {
        let pattern = name + #"\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = xml as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: xml, range: range), match.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    static func attr(_ name: String, near marker: String, in xml: String) -> String? {
        let lower = xml.lowercased()
        guard let range = lower.range(of: marker.lowercased()) else { return attr(name, in: xml) }
        let start = xml.index(range.lowerBound, offsetBy: -240, limitedBy: xml.startIndex) ?? xml.startIndex
        let end = xml.index(range.upperBound, offsetBy: 240, limitedBy: xml.endIndex) ?? xml.endIndex
        return attr(name, in: String(xml[start..<end])) ?? attr(name, in: xml)
    }

    static func text(_ tag: String, in xml: String) -> String? {
        let pattern = "<\(tag)\\b[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        return NovelHTMLText.strip(ns.substring(with: match.range(at: 1)))
    }
}

private enum NovelHTMLText {
    static func strip(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (key, value) in named { text = text.replacingOccurrences(of: key, with: value) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum NovelStoredZIP {
    static func extract(_ data: Data) -> [String: Data]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return nil }
        guard let eocd = findEOCD(bytes) else { return nil }
        let count = intAt(bytes, eocd + 10, 2)
        let centralOffset = intAt(bytes, eocd + 16, 4)
        guard count >= 0, centralOffset >= 0, centralOffset < bytes.count else { return nil }
        var files: [String: Data] = [:]
        var cursor = centralOffset
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count else { return files.isEmpty ? nil : files }
            guard bytes[cursor] == 0x50, bytes[cursor + 1] == 0x4b, bytes[cursor + 2] == 0x01, bytes[cursor + 3] == 0x02 else {
                return files.isEmpty ? nil : files
            }
            let method = intAt(bytes, cursor + 10, 2)
            let compSize = intAt(bytes, cursor + 20, 4)
            let nameLen = intAt(bytes, cursor + 28, 2)
            let extraLen = intAt(bytes, cursor + 30, 2)
            let commentLen = intAt(bytes, cursor + 32, 2)
            let localOffset = intAt(bytes, cursor + 42, 4)
            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            guard nameLen >= 0, nameEnd <= bytes.count else { return files.isEmpty ? nil : files }
            let name = String(bytes: bytes[nameStart..<nameEnd], encoding: .utf8) ?? ""
            cursor = nameEnd + extraLen + commentLen
            guard method == 0 else { continue }
            guard localOffset >= 0, localOffset + 30 <= bytes.count else { continue }
            guard bytes[localOffset] == 0x50, bytes[localOffset + 1] == 0x4b else { continue }
            let localName = intAt(bytes, localOffset + 26, 2)
            let localExtra = intAt(bytes, localOffset + 28, 2)
            let dataStart = localOffset + 30 + localName + localExtra
            let dataEnd = dataStart + compSize
            guard dataStart >= 0, dataEnd <= bytes.count, dataEnd >= dataStart else { continue }
            if name.hasSuffix("/") || name.isEmpty { continue }
            files[name] = Data(bytes[dataStart..<dataEnd])
        }
        return files
    }

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        let minStart = max(0, bytes.count - 22 - 65535)
        var index = bytes.count - 22
        while index >= minStart {
            if bytes[index] == 0x50, bytes[index + 1] == 0x4b, bytes[index + 2] == 0x05, bytes[index + 3] == 0x06 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func intAt(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> Int {
        guard offset >= 0, offset + length <= bytes.count else { return -1 }
        var value = 0
        for shift in 0..<length {
            value |= Int(bytes[offset + shift]) << (8 * shift)
        }
        return value
    }
}
