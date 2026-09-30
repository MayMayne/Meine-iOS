#!/usr/bin/env python3
from pathlib import Path
ROOT = Path("/var/minis/workspace/Meine-iOS/Meine")

def put(rel, text):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n")
    print("wrote", rel, path.stat().st_size)

put("App/AppModel.swift", r'''
import Foundation
import Observation
import SwiftUI

struct SleepTimerState: Equatable {
    var deadline: Date?
    var endOfTrack: Bool
    var fadeStarted: Date?
}

struct VaultRecord: Codable, Hashable, Identifiable {
    var id: String { "\(sourceID.rawValue)/\(itemID)" }
    var sourceID: SourceID
    var itemID: String
    var title: String
    var kind: MediaKind
    var symbol: String
}

struct AIPresetTemplate: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var genrePrompt: String
    var customPrompt: String
    var negative: [String]
}

@MainActor
@Observable
final class AppModel {
    var theme = ThemeStore()
    var sources: [SourceManifest] = []
    var progressByKey: [String: ProgressSnapshot] = [:]
    var vault: [VaultRecord] = []
    var contexts: [String: StoryAIContext] = [:]
    var presets: [AIPresetTemplate] = []
    var passwords: [String: PasswordHash] = [:]
    var unlocked: Set<String> = []
    var sleepTimer = SleepTimerState(deadline: nil, endOfTrack: false, fadeStarted: nil)
    var cacheQuotaGB: Double = 2
    var allowBackgroundTranslate = false
    var hudMessage: String?
    var pendingClipboard: SourceManifest?
    var aiConfig = AIGatewayConfig.empty
    var includeSecretsInBackup = false

    init() {
        sources = [SampleCatalog.bundledManifest()]
        presets = [
            AIPresetTemplate(id: "tien-hiep", name: "Tiên Hiệp Cổ Phong", genrePrompt: "Tiên hiệp cổ phong, văn phong trang trọng, giữ tên kiếm và cảnh giới.", customPrompt: "", negative: ["giọng hiện đại", "tiếng lóng"]),
            AIPresetTemplate(id: "do-thi", name: "Đô Thị Hiện Đại", genrePrompt: "Đô thị hiện đại, đối thoại tự nhiên, giữ tên riêng.", customPrompt: "", negative: ["văn cổ", "sáo ngữ"])
        ]
    }

    var visibleSources: [SourceManifest] {
        sources.filter { source in
            !source.passwordProtected || unlocked.contains(source.id.rawValue)
        }
    }

    func mediaRef(sourceID: SourceID, item: CatalogItem) -> MediaRef {
        MediaRef(sourceID: sourceID, itemID: ItemID(rawValue: item.id), kind: item.kind)
    }

    func progressKey(_ ref: MediaRef) -> String {
        "\(ref.sourceID.rawValue)|\(ref.itemID.rawValue)|\(ref.kind.rawValue)"
    }

    func progress(for ref: MediaRef) -> ProgressSnapshot? {
        progressByKey[progressKey(ref)]
    }

    func saveProgress(_ snapshot: ProgressSnapshot) {
        let key = progressKey(snapshot.ref)
        if let existing = progressByKey[key], existing == snapshot { return }
        progressByKey[key] = snapshot
        persistSoon()
    }

    func showHUD(_ message: String) {
        hudMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if hudMessage == message { hudMessage = nil }
        }
    }

    func context(for storyID: String) -> StoryAIContext {
        contexts[storyID] ?? StoryAIContext.empty(storyID: storyID)
    }

    func updateContext(_ ctx: StoryAIContext) {
        contexts[ctx.storyID] = ctx
        persistSoon()
    }

    func inVault(sourceID: SourceID, item: CatalogItem) -> Bool {
        vault.contains { $0.sourceID == sourceID && $0.itemID == item.id }
    }

    func toggleVault(sourceID: SourceID, item: CatalogItem) {
        if let index = vault.firstIndex(where: { $0.sourceID == sourceID && $0.itemID == item.id }) {
            vault.remove(at: index)
        } else {
            vault.insert(VaultRecord(sourceID: sourceID, itemID: item.id, title: item.title, kind: item.kind, symbol: item.symbol), at: 0)
        }
        persistSoon()
    }

    func itemsForSeries(_ seriesID: String, sourceID: SourceID) -> [CatalogItem] {
        guard let source = sources.first(where: { $0.id == sourceID }) else { return [] }
        return source.catalog.filter { $0.seriesID == seriesID }.sorted { ($0.episode ?? 0) < ($1.episode ?? 0) }
    }

    func item(sourceID: SourceID, itemID: String) -> CatalogItem? {
        sources.first { $0.id == sourceID }?.catalog.first { $0.id == itemID }
    }

    func importManifest(_ manifest: SourceManifest) {
        if let index = sources.firstIndex(where: { $0.id == manifest.id }) {
            sources[index] = manifest
        } else {
            sources.append(manifest)
        }
        persistSoon()
        showHUD("Đã nạp \(manifest.name)")
    }

    func removeSource(_ id: SourceID) {
        sources.removeAll { $0.id == id }
        persistSoon()
    }

    func setPassword(_ password: String, sourceID: SourceID) {
        passwords[sourceID.rawValue] = SourcePasswordHasher.make(password: password)
        if let index = sources.firstIndex(where: { $0.id == sourceID }) {
            sources[index].passwordProtected = true
        }
        unlocked.remove(sourceID.rawValue)
        persistSoon()
    }

    func unlock(sourceID: SourceID, password: String) -> Bool {
        guard let stored = passwords[sourceID.rawValue] else {
            unlocked.insert(sourceID.rawValue)
            return true
        }
        let ok = SourcePasswordHasher.verify(password: password, stored: stored)
        if ok { unlocked.insert(sourceID.rawValue) }
        return ok
    }

    func lock(_ sourceID: SourceID) {
        unlocked.remove(sourceID.rawValue)
    }

    func search(_ query: String) -> [(SourceID, CatalogItem)] {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
        guard !needle.isEmpty else { return [] }
        var rows: [(SourceID, CatalogItem)] = []
        for source in visibleSources {
            for item in source.catalog {
                let hay = "\(item.title) \(item.subtitle) \(item.artist ?? "")".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
                if hay.contains(needle) { rows.append((source.id, item)) }
            }
        }
        return rows
    }

    func applyAIConfig() {
        AIGatewayClient.shared.config = aiConfig
        if let data = try? JSONEncoder().encode(aiConfig) {
            KeychainStore.set(data, account: "ai.gateway")
        }
    }

    func loadPersisted() {
        let dir = supportDir()
        if let data = try? Data(contentsOf: dir.appendingPathComponent("library.json")),
           let blob = try? JSONDecoder().decode(LibraryBlob.self, from: data) {
            if !blob.sources.isEmpty { sources = blob.sources }
            progressByKey = Dictionary(uniqueKeysWithValues: blob.progress.map { (progressKey($0.ref), $0) })
            vault = blob.vault
            contexts = Dictionary(uniqueKeysWithValues: blob.contexts.map { ($0.storyID, $0) })
            if !blob.presets.isEmpty { presets = blob.presets }
            theme.background = blob.background
            cacheQuotaGB = blob.cacheQuotaGB
            allowBackgroundTranslate = blob.allowBackgroundTranslate
        }
        if let data = KeychainStore.get(account: "ai.gateway"),
           let config = try? JSONDecoder().decode(AIGatewayConfig.self, from: data) {
            aiConfig = config
            AIGatewayClient.shared.config = config
        }
        if let data = KeychainStore.get(account: "source.passwords"),
           let map = try? JSONDecoder().decode([String: PasswordHash].self, from: data) {
            passwords = map
        }
    }

    func persistSoon() {
        let blob = LibraryBlob(
            sources: sources,
            progress: Array(progressByKey.values),
            vault: vault,
            contexts: Array(contexts.values),
            presets: presets,
            background: theme.background,
            cacheQuotaGB: cacheQuotaGB,
            allowBackgroundTranslate: allowBackgroundTranslate
        )
        let dir = supportDir()
        if let data = try? JSONEncoder().encode(blob) {
            try? data.write(to: dir.appendingPathComponent("library.json"), options: .atomic)
        }
        if let data = try? JSONEncoder().encode(passwords) {
            KeychainStore.set(data, account: "source.passwords")
        }
    }

    func makeBackup(pin: String) throws -> Data {
        let payload = MeineBackupPayload(
            schema: BackupCodec.schema,
            sources: sources,
            progress: Array(progressByKey.values),
            contexts: Array(contexts.values),
            themeHex: theme.background.baseHex,
            saturation: theme.background.saturation,
            brightness: theme.background.brightness,
            includeSecrets: includeSecretsInBackup,
            apiKeyNote: includeSecretsInBackup ? aiConfig.apiKey : ""
        )
        return try BackupCodec.export(payload: payload, pin: pin)
    }

    func restoreBackup(_ data: Data, pin: String, merge: Bool) throws {
        let payload = try BackupCodec.restore(data: data, pin: pin)
        if merge {
            for source in payload.sources { importManifest(source) }
            for snapshot in payload.progress { progressByKey[progressKey(snapshot.ref)] = snapshot }
        } else {
            sources = payload.sources
            progressByKey = Dictionary(uniqueKeysWithValues: payload.progress.map { (progressKey($0.ref), $0) })
            contexts = Dictionary(uniqueKeysWithValues: payload.contexts.map { ($0.storyID, $0) })
        }
        theme.background = HSBColor(baseHex: payload.themeHex, saturation: payload.saturation, brightness: payload.brightness)
        if payload.includeSecrets, !payload.apiKeyNote.isEmpty {
            aiConfig.apiKey = payload.apiKeyNote
            applyAIConfig()
        }
        persistSoon()
    }

    private func supportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("Meine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct LibraryBlob: Codable {
    var sources: [SourceManifest]
    var progress: [ProgressSnapshot]
    var vault: [VaultRecord]
    var contexts: [StoryAIContext]
    var presets: [AIPresetTemplate]
    var background: HSBColor
    var cacheQuotaGB: Double
    var allowBackgroundTranslate: Bool
}

@MainActor
final class AudioSessionCoordinator: AudioSessionCoordinating {
    static let shared = AudioSessionCoordinator()
    private(set) var policy: AudioSessionPolicy = .music

    func request(_ policy: AudioSessionPolicy) async {
        self.policy = policy
        NotificationCenter.default.post(name: Notification.Name("meine.audio.policy"), object: nil, userInfo: ["policy": Self.token(policy)])
    }

    static func token(_ policy: AudioSessionPolicy) -> String {
        switch policy {
        case .videoExclusive: return "videoExclusive"
        case .music: return "music"
        case .ttsSolo: return "ttsSolo"
        case .ttsDuckedMusic: return "ttsDuckedMusic"
        }
    }
}
''')

put("Sample/SampleCatalog.swift", r'''
import Foundation

enum SampleCatalog {
    static func bundledManifest() -> SourceManifest {
        SourceManifest(
            id: SourceID(rawValue: "meine.demo"),
            name: "Meine",
            version: "1.0",
            updateURL: nil,
            passwordProtected: false,
            upstreams: [UpstreamDescriptor(id: "local", kind: .local, config: .object(["path": .string("bundle")]))],
            mirrors: [],
            home: SDUINode.vStack(children: [
                .text(value: "Meine"),
                .hero(itemIDs: ["film-song-bien", "novel-gio"]),
                .grid(columns: 2, children: [
                    .mediaCard(itemID: "manga-mua"),
                    .mediaCard(itemID: "music-mua-nhe"),
                    .mediaCard(itemID: "short-01"),
                    .mediaCard(itemID: "film-short-lantern")
                ])
            ], spacing: 16),
            catalog: items
        )
    }

    static var items: [CatalogItem] {
        [
            novel, manga, music, cinema, shortFilm, shorts1, shorts2, shorts3
        ]
    }

    static let novel = CatalogItem(
        id: "novel-gio",
        title: "Gió qua hiên trúc",
        subtitle: "Một truyện ngắn tự viết cho Meine.",
        kind: .novel,
        symbol: "text.book.closed",
        chapters: [
            TextChapter(id: "c1", title: "Chương 1: Hiên vắng", body: novelChapter1),
            TextChapter(id: "c2", title: "Chương 2: Mưa nhỏ", body: novelChapter2)
        ],
        seriesID: "novel-gio",
        episode: 1,
        episodeTotal: 2
    )

    static let manga = CatalogItem(
        id: "manga-mua",
        title: "Mưa trên mái ngói",
        subtitle: "Tám trang vẽ trong máy.",
        kind: .manga,
        symbol: "book.pages",
        pageURLs: [],
        seriesID: "manga-mua",
        episode: 1,
        episodeTotal: 1
    )

    static let music = CatalogItem(
        id: "music-mua-nhe",
        title: "Mưa nhẹ",
        subtitle: "Bản nghe thử tổng hợp trong máy.",
        kind: .music,
        symbol: "music.note",
        lyrics: sampleLRC,
        duration: 8,
        artist: "Meine",
        seriesID: "album-hien",
        episode: 1,
        episodeTotal: 1
    )

    static let cinema = CatalogItem(
        id: "film-song-bien",
        title: "Sóng biển",
        subtitle: "Phim mẫu không có tệp. Mở để xem trình phát.",
        kind: .cinema,
        symbol: "film",
        subtitles: sampleVTT,
        duration: 120,
        seriesID: "film-song",
        episode: 1,
        episodeTotal: 2
    )

    static let shortFilm = CatalogItem(
        id: "film-short-lantern",
        title: "Đèn lồng",
        subtitle: "Phim ngắn cùng danh sách Sóng biển.",
        kind: .shortFilm,
        symbol: "film.stack",
        duration: 90,
        seriesID: "film-song",
        episode: 2,
        episodeTotal: 2
    )

    static let shorts1 = CatalogItem(
        id: "short-01",
        title: "Hiên chiều",
        subtitle: "Một khoảnh khắc rất ngắn.",
        kind: .shorts,
        symbol: "rectangle.portrait",
        duration: 15,
        seriesID: "shorts-hien",
        episode: 1,
        episodeTotal: 3
    )
    static let shorts2 = CatalogItem(
        id: "short-02",
        title: "Mái ngói",
        subtitle: "Mưa vừa tạnh.",
        kind: .shorts,
        symbol: "rectangle.portrait",
        duration: 15,
        seriesID: "shorts-hien",
        episode: 2,
        episodeTotal: 3
    )
    static let shorts3 = CatalogItem(
        id: "short-03",
        title: "Đèn cuối phố",
        subtitle: "Gió thổi tắt một ngọn.",
        kind: .shorts,
        symbol: "rectangle.portrait",
        duration: 15,
        seriesID: "shorts-hien",
        episode: 3,
        episodeTotal: 3
    )

    static let novelChapter1 = """
    Hiên trúc vắng người từ lúc chiều. Gió đi qua khe cửa, mang theo mùi mưa còn chưa rơi.

    Chương 1 chỉ là một khoảng lặng. Có người ngồi xếp lại chồng sách, không đọc, chỉ nghe tiếng lá.

    "Cậu còn ở lại không?" giọng nói rất nhỏ, như sợ làm vỡ mặt nước trong chén.

    Cậu gật. Ngoài sân, một con chim vừa đáp xuống thành giếng rồi lại bay đi. Không có gì lớn xảy ra, và đó là điều cậu cần.
    """

    static let novelChapter2 = """
    Mưa nhỏ bắt đầu lúc không ai để ý. Từng giọt gõ lên mái, đều, không vội.

    Cậu viết một dòng rồi xóa. Viết lại. Lần này giữ.

    "Ngày mai mình đi." Người kia nói, không nhìn cậu. "Ko phải vì giận. Chỉ là đường khác."

    Cậu muốn nói dc, nhưng nuốt lại. Mưa vẫn rơi. Trong ngăn kéo có một chiếc khóa cũ, không còn chìa.
    """

    static let sampleLRC = """
    [00:00.50] Mưa nhẹ trên hiên
    [00:02.00] Không cần nói thêm
    [00:04.20] Gió biết đường về
    [00:06.40] Mình ngồi đây thêm một chút
    """

    static let sampleVTT = """
    WEBVTT

    00:00:01.000 --> 00:00:04.000
    Sóng vừa chạm bờ.

    00:00:05.000 --> 00:00:08.000
    Không ai gọi tên mình.
    """
}
''')

print("app+sample written request")
