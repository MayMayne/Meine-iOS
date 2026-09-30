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
