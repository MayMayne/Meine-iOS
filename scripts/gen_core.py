#!/usr/bin/env python3
"""Generate Meine core Swift sources. Logic lives here so files stay consistent."""
from pathlib import Path

ROOT = Path("/var/minis/workspace/Meine-iOS/Meine")

FILES = {}

def put(rel, text):
    FILES[rel] = text.strip() + "\n"

put("Core/Models.swift", r'''
import Foundation

enum MediaKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case novel, manga, music, cinema, shortFilm, shorts
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .novel: return "text.book.closed"
        case .manga: return "book.pages"
        case .music: return "music.note"
        case .cinema: return "film"
        case .shortFilm: return "film.stack"
        case .shorts: return "rectangle.portrait"
        }
    }
    var accessibilityName: String {
        switch self {
        case .novel: return "Truyện chữ"
        case .manga: return "Truyện tranh"
        case .music: return "Nhạc"
        case .cinema: return "Phim"
        case .shortFilm: return "Phim ngắn"
        case .shorts: return "Shorts"
        }
    }
}

struct SourceID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

struct ItemID: Hashable, Codable, Sendable, RawRepresentable {
    var rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
}

struct MediaRef: Hashable, Codable, Sendable {
    var sourceID: SourceID
    var itemID: ItemID
    var kind: MediaKind
}

struct TextChapter: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var body: String
}

struct CatalogItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var kind: MediaKind
    var symbol: String
    var streamURL: String?
    var chapters: [TextChapter]
    var pageURLs: [String]
    var lyrics: String?
    var subtitles: String?
    var duration: Double?
    var artist: String?
    var seriesID: String?
    var episode: Int?
    var episodeTotal: Int?

    init(
        id: String,
        title: String,
        subtitle: String,
        kind: MediaKind,
        symbol: String,
        streamURL: String? = nil,
        chapters: [TextChapter] = [],
        pageURLs: [String] = [],
        lyrics: String? = nil,
        subtitles: String? = nil,
        duration: Double? = nil,
        artist: String? = nil,
        seriesID: String? = nil,
        episode: Int? = nil,
        episodeTotal: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.symbol = symbol
        self.streamURL = streamURL
        self.chapters = chapters
        self.pageURLs = pageURLs
        self.lyrics = lyrics
        self.subtitles = subtitles
        self.duration = duration
        self.artist = artist
        self.seriesID = seriesID
        self.episode = episode
        self.episodeTotal = episodeTotal
    }
}

enum RepeatMode: String, Codable, Sendable, Hashable, CaseIterable {
    case off, one, all
}

enum ProgressPayload: Equatable, Codable, Sendable {
    case cinema(current: Duration, duration: Duration, completed: Bool)
    case music(seconds: Double, trackID: String, repeatMode: RepeatMode, shuffle: Bool)
    case mangaPaged(page: Int, total: Int)
    case mangaWebtoon(yOffset: Double)
    case novel(chapterID: String, paragraphIndex: Int, workPercent: Double)
}

struct ProgressSnapshot: Equatable, Codable, Sendable {
    var ref: MediaRef
    var updatedAt: Date
    var payload: ProgressPayload
}

struct StoryAIContext: Codable, Hashable, Sendable {
    var storyID: String
    var glossary: [String: String]
    var genrePrompt: String
    var customPrompt: String
    var negative: [String]

    static func empty(storyID: String) -> StoryAIContext {
        StoryAIContext(storyID: storyID, glossary: [:], genrePrompt: "", customPrompt: "", negative: [])
    }
}

struct MeinePlaylistDocument: Codable, Sendable, Equatable {
    var schema: String
    var title: String
    var kind: MediaKind
    var items: [MediaRef]
    static let currentSchema = "meine.playlist.v1"
}

enum MeineError: Error, Equatable {
    case invalidSource
    case locked
    case notFound
    case transport(String)
}
''')

put("Core/ColorMath.swift", r'''
import Foundation

enum ContrastInk: Equatable, Sendable {
    case dark
    case light
    var hex: String { self == .dark ? "1E1E1E" : "F5F5F7" }
}

enum Palette12 {
    static let allHex: [String] = [
        "#FF0000", "#FF8000", "#FFFF00", "#00FF00", "#0000FF", "#4B0082",
        "#800080", "#FFC0CB", "#8B4513", "#000000", "#FFFFFF", "#808080"
    ]
}

struct HSBColor: Equatable, Codable, Sendable {
    var baseHex: String
    var saturation: Double
    var brightness: Double

    func resolvedRGB() -> (r: Double, g: Double, b: Double) {
        let rgb = HexColor.parse(baseHex)
        let hsv = RGBHSB.rgbToHSV(r: rgb.r, g: rgb.g, b: rgb.b)
        let sat = min(max(saturation, 0), 1)
        let bri = min(max(brightness, 0), 1)
        return RGBHSB.hsvToRGB(h: hsv.h, s: sat, v: bri)
    }
}

enum HexColor {
    static func parse(_ raw: String) -> (r: Double, g: Double, b: Double) {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return (1, 1, 1)
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return (r, g, b)
    }

    static func format(r: Double, g: Double, b: Double) -> String {
        let ri = Int((min(max(r, 0), 1) * 255).rounded())
        let gi = Int((min(max(g, 0), 1) * 255).rounded())
        let bi = Int((min(max(b, 0), 1) * 255).rounded())
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}

enum RGBHSB {
    static func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV
        var h = 0.0
        if delta > 0.00001 {
            if maxV == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxV == 0 ? 0 : delta / maxV
        return (h, s, maxV)
    }

    static func hsvToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let sat = min(max(s, 0), 1)
        let val = min(max(v, 0), 1)
        let hue = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let i = Int(hue * 6)
        let f = hue * 6 - Double(i)
        let p = val * (1 - sat)
        let q = val * (1 - f * sat)
        let t = val * (1 - (1 - f) * sat)
        switch i % 6 {
        case 0: return (val, t, p)
        case 1: return (q, val, p)
        case 2: return (p, val, t)
        case 3: return (p, q, val)
        case 4: return (t, p, val)
        default: return (val, p, q)
        }
    }
}

enum RelativeLuminance {
    public static func value(r: Double, g: Double, b: Double) -> Double {
        func f(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    public static func ink(luminance L: Double) -> ContrastInk {
        L > 0.5 ? .dark : .light
    }

    static func ink(for color: HSBColor) -> ContrastInk {
        let rgb = color.resolvedRGB()
        return ink(luminance: value(r: rgb.r, g: rgb.g, b: rgb.b))
    }
}
''')

put("Core/ProgressPolicy.swift", r'''
import Foundation

struct ResumeDecision: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case resume(from: Duration, toast: String)
        case restart
        case restoreMangaPaged(Int)
        case restoreWebtoon(yOffset: Double)
        case restoreNovel(chapterID: String, paragraphIndex: Int)
        case restoreMusic(seconds: Double, trackID: String, repeatMode: RepeatMode, shuffle: Bool)
        case none
    }
    var action: Action
}

enum ResumePolicy {
    static let autosaveInterval: TimeInterval = 5.0
    static let minResumeSeconds: TimeInterval = 10
    static let completionRatio: Double = 0.90

    static func decide(snapshot: ProgressSnapshot, nowPlayingDuration: Duration?) -> ResumeDecision {
        switch snapshot.payload {
        case .cinema(let current, let storedDuration, let completed):
            let duration = nowPlayingDuration ?? storedDuration
            let currentSeconds = seconds(current)
            let durationSeconds = seconds(duration)
            let ratio = durationSeconds > 0 ? currentSeconds / durationSeconds : 0
            if completed || ratio >= completionRatio {
                return ResumeDecision(action: .restart)
            }
            if currentSeconds > minResumeSeconds {
                let toast = "Đã tiếp tục phát từ \(TimeCodes.format(current))"
                return ResumeDecision(action: .resume(from: current, toast: toast))
            }
            return ResumeDecision(action: .restart)
        case .music(let seconds, let trackID, let repeatMode, let shuffle):
            return ResumeDecision(action: .restoreMusic(seconds: seconds, trackID: trackID, repeatMode: repeatMode, shuffle: shuffle))
        case .mangaPaged(let page, _):
            return ResumeDecision(action: .restoreMangaPaged(page))
        case .mangaWebtoon(let yOffset):
            return ResumeDecision(action: .restoreWebtoon(yOffset: yOffset))
        case .novel(let chapterID, let paragraphIndex, _):
            return ResumeDecision(action: .restoreNovel(chapterID: chapterID, paragraphIndex: paragraphIndex))
        }
    }

    static func markCompleted(current: Double, duration: Double) -> Bool {
        guard duration > 0 else { return false }
        return current / duration >= completionRatio
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

enum TimeCodes {
    static func format(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    static func format(_ duration: Duration) -> String {
        let parts = duration.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return format(seconds)
    }
}

enum EdgeDeadzone {
    static let margin: CGFloat = 24
    static let tan60: CGFloat = 1.732

    static func brightnessZone(width: CGFloat) -> ClosedRange<CGFloat> {
        margin ... width * 0.35
    }

    static func volumeZone(width: CGFloat) -> ClosedRange<CGFloat> {
        (width * 0.65) ... (width - margin)
    }

    static func isVerticalLock(dx: CGFloat, dy: CGFloat) -> Bool {
        abs(dy) > abs(dx) * tan60
    }
}

enum AudioSessionPolicy: Equatable, Sendable {
    case videoExclusive
    case music
    case ttsSolo
    case ttsDuckedMusic
}

protocol AudioSessionCoordinating: AnyObject, Sendable {
    func request(_ policy: AudioSessionPolicy) async
}

enum PhoneticMiddleware {
    static let bundled: [String: String] = [
        "ko": "không",
        "dc": "được",
        "k": "không",
        "mk": "mình",
        "mik": "mình",
        "t": "tao",
        "m": "mày",
        "vs": "với",
        "j": "gì",
        "r": "rồi",
        "ntn": "như thế nào",
        "cx": "cũng"
    ]

    static func rewrite(_ raw: String) -> String {
        let pattern = #"\b[\p{L}\p{N}]+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let ns = raw as NSString
        var output = raw
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            let word = ns.substring(with: match.range)
            let key = word.lowercased()
            guard let mapped = bundled[key] else { continue }
            let replacement = word.first?.isUppercase == true ? mapped.capitalized : mapped
            if let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: replacement)
            }
        }
        return output
    }
}
''')

put("Core/JSONValue.swift", r'''
import Foundation

enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() {
            self = .null
        } else if let value = try? box.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? box.decode(Double.self) {
            self = .number(value)
        } else if let value = try? box.decode(String.self) {
            self = .string(value)
        } else if let value = try? box.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? box.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: box, debugDescription: "JSONValue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .null: try box.encodeNil()
        case .bool(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .string(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }
}
''')

print(f"core module placeholders {len(FILES)}")
Path("/tmp/meine_files_count.txt").write_text(str(len(FILES)))
# Write immediately
for rel, text in FILES.items():
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print("wrote", rel, len(text))
