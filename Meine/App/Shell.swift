import SwiftUI
import UIKit

@main
struct MeineApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(app)
                .preferredColorScheme(app.theme.ink == .light ? .dark : .light)
                .tint(app.theme.activeColor)
                .onAppear { app.loadPersisted() }
        }
    }
}

struct RootTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Image(systemName: "square.grid.2x2") }
                .tag(0)
                .accessibilityLabel("Trang chủ nguồn")
            VaultView()
                .tabItem { Image(systemName: "books.vertical") }
                .tag(1)
                .accessibilityLabel("Thư viện riêng")
            RecentsView()
                .tabItem { Image(systemName: "play.circle") }
                .tag(2)
                .accessibilityLabel("Đang phát")
            SettingsRootView()
                .tabItem { Image(systemName: "gearshape") }
                .tag(3)
                .accessibilityLabel("Cài đặt")
        }
        .overlay(alignment: .top) { hud }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { detectClipboard() }
            if phase == .background { app.persistSoon() }
        }
        .alert("Nạp nguồn từ clipboard?", isPresented: clipboardPresented) {
            Button("Nạp") {
                if let pending = app.pendingClipboard { app.importManifest(pending) }
                app.pendingClipboard = nil
            }
            Button("Bỏ", role: .cancel) { app.pendingClipboard = nil }
        } message: {
            Text(app.pendingClipboard?.name ?? "")
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    private var clipboardPresented: Binding<Bool> {
        Binding(get: { app.pendingClipboard != nil }, set: { if !$0 { app.pendingClipboard = nil } })
    }

    @ViewBuilder private var hud: some View {
        if let message = app.hudMessage {
            Text(message)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.top, 8)
                .padding(.horizontal, 28)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func detectClipboard() {
        guard let text = UIPasteboard.general.string, let manifest = ClipboardSourceDetector.detect(text) else { return }
        if app.sources.contains(where: { $0.id == manifest.id && $0.version == manifest.version }) { return }
        app.pendingClipboard = manifest
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    searchField
                    if query.isEmpty {
                        ForEach(app.visibleSources, id: \.id) { source in
                            sourceBlock(source)
                        }
                    } else {
                        searchResults
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(app.theme.backgroundColor.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(systemName: "plus", tooltip: "Nạp nguồn") { showAdd = true }
                }
            }
            .navigationDestination(for: Route.self) { route in
                routeDestination(route)
            }
            .sheet(isPresented: $showAdd) { SourceImportSheet() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meine")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(app.theme.inkColor)
            Text("Đọc, xem, nghe — nguồn của bạn.")
                .font(.subheadline)
                .foregroundStyle(app.theme.inkColor.opacity(0.62))
        }
        .padding(.top, 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(app.theme.inkColor.opacity(0.5))
            TextField("Tìm trong nguồn đã mở", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sourceBlock(_ source: SourceManifest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(source.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(app.theme.inkColor)
                Spacer()
                Image(systemName: "lock.open")
                    .foregroundStyle(app.theme.activeColor)
                    .accessibilityLabel("Nguồn đang mở")
            }
            if let home = source.home {
                SDUIView(node: home, source: source)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(source.catalog) { item in
                        NavigationLink(value: Route.item(source.id.rawValue, item.id)) {
                            MediaCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var searchResults: some View {
        VStack(spacing: 10) {
            ForEach(app.search(query), id: \.1.id) { pair in
                NavigationLink(value: Route.item(pair.0.rawValue, pair.1.id)) {
                    HStack(spacing: 12) {
                        Image(systemName: pair.1.symbol)
                            .frame(width: 42, height: 42)
                            .background(app.theme.primaryColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(pair.1.title).font(.headline)
                            Text(pair.1.kind.accessibilityName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func routeDestination(_ route: Route) -> some View {
        switch route {
        case .item(let source, let item):
            if let sid = app.sources.first(where: { $0.id.rawValue == source })?.id,
               let found = app.item(sourceID: sid, itemID: item) {
                PlayerHost(sourceID: sid, item: found)
            } else {
                MissingView()
            }
        }
    }
}

enum Route: Hashable {
    case item(String, String)
}

struct MediaCard: View {
    @Environment(AppModel.self) private var app
    var item: CatalogItem
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(app.theme.primaryColor.opacity(0.45))
                Image(systemName: item.symbol)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(app.theme.inkColor)
                    .accessibilityLabel(item.kind.accessibilityName)
            }
            .frame(height: 120)
            Text(item.title)
                .font(.headline)
                .foregroundStyle(app.theme.inkColor)
                .lineLimit(2)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(app.theme.inkColor.opacity(0.6))
                .lineLimit(2)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

struct SDUIView: View {
    @Environment(AppModel.self) private var app
    var node: SDUINode
    var source: SourceManifest

    var body: some View {
        SDUIBlock(node: node, source: source)
    }
}

private struct SDUIBlock: View {
    @Environment(AppModel.self) private var app
    var node: SDUINode
    var source: SourceManifest

    var body: some View {
        switch node {
        case .vStack(let children, let spacing):
            VStack(alignment: .leading, spacing: spacing ?? 12) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    SDUIBlock(node: child, source: source)
                }
            }
        case .hStack(let children, let spacing):
            HStack(spacing: spacing ?? 12) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    SDUIBlock(node: child, source: source)
                }
            }
        case .zStack(let children):
            ZStack {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    SDUIBlock(node: child, source: source)
                }
            }
        case .scroll(let child):
            ScrollView(.horizontal, showsIndicators: false) { SDUIBlock(node: child, source: source) }
        case .text(let value):
            Text(value).font(.title2.weight(.semibold)).foregroundStyle(app.theme.inkColor)
        case .symbol(let name):
            Image(systemName: name).font(.title).accessibilityLabel(name)
        case .mediaCard(let itemID):
            if let item = source.catalog.first(where: { $0.id == itemID }) {
                NavigationLink(value: Route.item(source.id.rawValue, item.id)) { MediaCard(item: item) }.buttonStyle(.plain)
            }
        case .hero(let itemIDs):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(itemIDs, id: \.self) { id in
                        if let item = source.catalog.first(where: { $0.id == id }) {
                            NavigationLink(value: Route.item(source.id.rawValue, item.id)) {
                                SDUIHero(item: item)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        case .grid(let columns, let children):
            let count = max(1, columns)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: count), spacing: 12) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    SDUIBlock(node: child, source: source)
                }
            }
        case .spacer:
            Spacer(minLength: 8)
        case .unknown:
            EmptyView()
        }
    }
}

private struct SDUIHero: View {
    @Environment(AppModel.self) private var app
    var item: CatalogItem
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [app.theme.primaryColor, app.theme.activeColor.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: item.symbol).font(.title2)
                Text(item.title).font(.title3.weight(.bold))
                Text(item.subtitle).font(.caption).lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(width: 280, height: 168)
    }
}

struct PlayerHost: View {
    var sourceID: SourceID
    var item: CatalogItem
    @Environment(AppModel.self) private var app

    var body: some View {
        switch item.kind {
        case .novel:
            NovelReaderView(sourceID: sourceID, item: item)
        case .manga:
            MangaReaderView(sourceID: sourceID, item: item)
        case .music:
            AudioPlayerView(sourceID: sourceID, item: item)
        case .cinema, .shortFilm:
            CinemaPlayerView(sourceID: sourceID, item: item)
        case .shorts:
            ShortsFeedView(sourceID: sourceID, items: shorts, startID: item.id)
        }
    }

    private var shorts: [CatalogItem] {
        if let series = item.seriesID {
            let rows = app.itemsForSeries(series, sourceID: sourceID)
            if !rows.isEmpty { return rows }
        }
        return [item]
    }
}

struct MissingView: View {
    var body: some View {
        Image(systemName: "questionmark")
            .font(.largeTitle)
            .accessibilityLabel("Không tìm thấy")
    }
}

struct VaultView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        NavigationStack {
            Group {
                if app.vault.isEmpty {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(app.theme.inkColor.opacity(0.4))
                        .accessibilityLabel("Thư viện riêng trống")
                } else {
                    List(app.vault) { record in
                        if let item = app.item(sourceID: record.sourceID, itemID: record.itemID) {
                            NavigationLink(value: Route.item(record.sourceID.rawValue, record.itemID)) {
                                Label(record.title, systemImage: record.symbol)
                            }
                            .accessibilityLabel(item.title)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(app.theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .navigationDestination(for: Route.self) { route in
                if case .item(let source, let id) = route,
                   let sid = app.sources.first(where: { $0.id.rawValue == source })?.id,
                   let item = app.item(sourceID: sid, itemID: id) {
                    PlayerHost(sourceID: sid, item: item)
                }
            }
        }
    }
}

struct RecentsView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        NavigationStack {
            List(recent, id: \.updatedAt) { snapshot in
                if let item = app.item(sourceID: snapshot.ref.sourceID, itemID: snapshot.ref.itemID.rawValue) {
                    NavigationLink(value: Route.item(snapshot.ref.sourceID.rawValue, item.id)) {
                        HStack {
                            Image(systemName: item.symbol)
                            VStack(alignment: .leading) {
                                Text(item.title)
                                Text(TimeCodes.format(snapshot.updatedAt.timeIntervalSince1970).isEmpty ? "" : relative(snapshot.updatedAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(app.theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .overlay {
                if recent.isEmpty {
                    Image(systemName: "play.circle")
                        .font(.system(size: 48, weight: .ultraLight))
                        .accessibilityLabel("Chưa có tiến trình")
                }
            }
            .navigationDestination(for: Route.self) { route in
                if case .item(let source, let id) = route,
                   let sid = app.sources.first(where: { $0.id.rawValue == source })?.id,
                   let item = app.item(sourceID: sid, itemID: id) {
                    PlayerHost(sourceID: sid, item: item)
                }
            }
        }
    }

    private var recent: [ProgressSnapshot] {
        app.progressByKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
