import AVFoundation
import SwiftUI
import UIKit

struct ShortsFeedView: View {
    var sourceID: SourceID
    var items: [CatalogItem]
    var startID: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var page = ""
    @State private var hearts: [String: Int] = [:]
    @State private var bubbles: [String: Int] = [:]
    @State private var seconds: Double = 0
    @State private var shareTitle: String?
    @State private var episodesOpen = false
    @State private var lastSaved = Date.distantPast

    private let pool = ShortsPlayerPool.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if items.isEmpty {
                    empty
                } else {
                    TabView(selection: $page) {
                        ForEach(items) { item in
                            card(item, size: geo.size)
                                .tag(item.id)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .rotationEffect(.degrees(-90))
                                .frame(width: geo.size.height, height: geo.size.width)
                        }
                    }
                    .frame(width: geo.size.height, height: geo.size.width)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .rotationEffect(.degrees(90))
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                VStack {
                    HStack {
                        IconButton(systemName: "chevron.backward", tooltip: "Đóng") {
                            HapticTap.light()
                            persist(page)
                            dismiss()
                        }
                        Spacer()
                        IconButton(systemName: "rectangle.grid.2x2", tooltip: "Tập") {
                            HapticTap.light()
                            episodesOpen = true
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, EdgeDeadzone.margin)
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear(perform: boot)
        .onDisappear {
            persist(page)
            pool.pause()
        }
        .onChange(of: page) { old, new in
            if old != new {
                persist(old)
                attach(new, resume: true)
            }
        }
        .task { await clock() }
        .sheet(isPresented: $episodesOpen) { episodeSheet }
        .sheet(item: shareBinding) { ticket in
            ShareSheet(items: [ticket.title])
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash")
                .font(.system(size: 44, weight: .ultraLight))
                .accessibilityLabel("Không có short")
            Text("Chưa có short")
                .font(.headline)
        }
        .foregroundStyle(.white)
    }

    private func card(_ item: CatalogItem, size: CGSize) -> some View {
        ZStack {
            if item.id == page {
                ShortsVideoSurface(pool: pool)
                    .ignoresSafeArea()
            } else {
                poster(item)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            HStack(alignment: .bottom) {
                meta(item)
                Spacer(minLength: 12)
                rail(item)
            }
            .padding(.horizontal, EdgeDeadzone.margin)
            .padding(.bottom, EdgeDeadzone.margin)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            HapticTap.light()
            if pool.isPlaying() {
                pool.pause()
            } else {
                pool.play()
            }
        }
    }

    private func poster(_ item: CatalogItem) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.16), Color(white: 0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 14) {
                Image(systemName: symbolName(item.symbol))
                    .font(.system(size: 64, weight: .ultraLight))
                    .accessibilityLabel(item.title)
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 36)
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }

    private func meta(_ item: CatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let episode = item.episode {
                let total = item.episodeTotal ?? episode
                Text("Tập \(episode)/\(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            progressBar(item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressBar(_ item: CatalogItem) -> some View {
        let fraction = item.id == page ? liveFraction(item) : savedFraction(item)
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.28))
            GeometryReader { geo in
                Capsule()
                    .fill(.white)
                    .frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: 2)
        .accessibilityLabel("Tiến trình")
    }

    private func rail(_ item: CatalogItem) -> some View {
        VStack(spacing: 18) {
            countButton(
                systemName: "heart",
                tip: "Thích",
                count: hearts[item.id, default: 0]
            ) {
                hearts[item.id, default: 0] += 1
            }
            countButton(
                systemName: "bubble.left",
                tip: "Bình luận",
                count: bubbles[item.id, default: 0]
            ) {
                bubbles[item.id, default: 0] += 1
            }
            IconButton(
                systemName: app.inVault(sourceID: sourceID, item: item) ? "bookmark.fill" : "bookmark",
                tooltip: "Kho"
            ) {
                HapticTap.light()
                app.toggleVault(sourceID: sourceID, item: item)
            }
            IconButton(systemName: "square.and.arrow.up", tooltip: "Chia sẻ") {
                HapticTap.light()
                shareTitle = item.title
            }
        }
        .foregroundStyle(.white)
    }

    private func countButton(systemName: String, tip: String, count: Int, action: @escaping () -> Void) -> some View {
        Button {
            HapticTap.light()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.title3)
                    .frame(width: 44, height: 28)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tip)
    }

    private var episodeSheet: some View {
        let series = seriesItems
        return NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(series) { row in
                        Button {
                            HapticTap.light()
                            page = row.id
                            episodesOpen = false
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Text(episodeLabel(row))
                                    .font(.callout.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(
                                        row.id == page ? Color.white.opacity(0.18) : Color.white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                if app.progress(for: app.mediaRef(sourceID: sourceID, item: row)) != nil {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 6, height: 6)
                                        .padding(7)
                                        .accessibilityLabel("Đã xem")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Tập \(episodeLabel(row))")
                    }
                }
                .padding(22)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Tập")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { episodesOpen = false }
                        .accessibilityLabel("Đóng")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var seriesItems: [CatalogItem] {
        guard let current = items.first(where: { $0.id == page }) ?? items.first,
              let series = current.seriesID, !series.isEmpty else {
            return items
        }
        let rows = app.itemsForSeries(series, sourceID: sourceID)
        return rows.isEmpty ? items.filter { $0.seriesID == series } : rows
    }

    private var shareBinding: Binding<ShortsShareTicket?> {
        Binding(
            get: { shareTitle.map { ShortsShareTicket(title: $0) } },
            set: { shareTitle = $0?.title }
        )
    }

    private func boot() {
        if items.contains(where: { $0.id == startID }) {
            page = startID
        } else {
            page = items.first?.id ?? ""
        }
        Task { await AudioSessionCoordinator.shared.request(.videoExclusive) }
        attach(page, resume: true)
    }

    private func attach(_ id: String, resume: Bool) {
        guard let item = items.first(where: { $0.id == id }) else {
            pool.attach(url: nil)
            return
        }
        let url = (item.streamURL ?? "").isEmpty ? nil : MediaLocator.url(for: item.streamURL ?? "")
        pool.attach(url: url)
        if resume {
            applyResume(item)
        } else {
            pool.seek(0)
            seconds = 0
        }
        if url != nil {
            pool.play()
        }
        preloadNeighbors(of: id)
    }

    private func applyResume(_ item: CatalogItem) {
        let ref = app.mediaRef(sourceID: sourceID, item: item)
        guard let snapshot = app.progress(for: ref) else {
            pool.seek(0)
            seconds = 0
            return
        }
        let playing = (item.duration ?? 0) > 0 ? Duration.seconds(item.duration ?? 0) : nil
        let decision = ResumePolicy.decide(snapshot: snapshot, nowPlayingDuration: playing)
        switch decision.action {
        case .resume(let from, let toast):
            let mark = durationSeconds(from)
            pool.seek(mark)
            seconds = mark
            app.showHUD(toast)
        case .restart:
            pool.seek(0)
            seconds = 0
        default:
            if case .cinema(_, _, let completed) = snapshot.payload, completed {
                pool.seek(0)
                seconds = 0
            } else if case .cinema(let current, _, _) = snapshot.payload {
                let mark = durationSeconds(current)
                pool.seek(mark)
                seconds = mark
            } else {
                pool.seek(0)
                seconds = 0
            }
        }
    }

    private func preloadNeighbors(of id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let neighbors = [index - 1, index + 1].filter { items.indices.contains($0) }
        for offset in neighbors {
            let item = items[offset]
            guard let raw = item.streamURL, let url = MediaLocator.url(for: raw) else { continue }
            let key = ShortsPreloader.cacheKey(item.id)
            Task { await ShortsPreloader.preload(url: url, key: key) }
        }
    }

    private func clock() async {
        while !Task.isCancelled {
            if !page.isEmpty {
                seconds = pool.seconds
                if Date().timeIntervalSince(lastSaved) >= 5 {
                    persist(page)
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    private func persist(_ id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let total = max(item.duration ?? lengthFallback, 0.01)
        let now = item.id == page ? seconds : savedSeconds(item)
        let completed = now / total >= 0.90
        app.saveProgress(
            ProgressSnapshot(
                ref: app.mediaRef(sourceID: sourceID, item: item),
                updatedAt: Date(),
                payload: .cinema(current: .seconds(now), duration: .seconds(total), completed: completed)
            )
        )
        lastSaved = Date()
    }

    private var lengthFallback: Double {
        let value = pool.knownDuration()
        return value.isFinite && value > 0 ? value : 1
    }

    private func liveFraction(_ item: CatalogItem) -> Double {
        let total = max(item.duration ?? lengthFallback, 0.01)
        return min(1, max(0, seconds / total))
    }

    private func savedFraction(_ item: CatalogItem) -> Double {
        let total = max(item.duration ?? 1, 0.01)
        return min(1, savedSeconds(item) / total)
    }

    private func savedSeconds(_ item: CatalogItem) -> Double {
        guard let snapshot = app.progress(for: app.mediaRef(sourceID: sourceID, item: item)),
              case .cinema(let current, _, _) = snapshot.payload else { return 0 }
        return durationSeconds(current)
    }

    private func durationSeconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private func episodeLabel(_ item: CatalogItem) -> String {
        if let episode = item.episode { return "\(episode)" }
        return item.title
    }

    private func symbolName(_ raw: String) -> String {
        raw.contains(".") ? raw : "play.rectangle"
    }
}

private struct ShortsShareTicket: Identifiable {
    var id: String { title }
    var title: String
}

private struct ShortsVideoSurface: UIViewRepresentable {
    var pool: ShortsPlayerPool

    func makeUIView(context: Context) -> ShortsPlayerCanvas {
        let canvas = ShortsPlayerCanvas()
        pool.bind(canvas)
        return canvas
    }

    func updateUIView(_ view: ShortsPlayerCanvas, context: Context) {
        pool.bind(view)
    }
}
