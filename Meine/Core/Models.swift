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
