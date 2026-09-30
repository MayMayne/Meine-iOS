import SwiftUI
import UIKit

struct MangaReaderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let sourceID: SourceID
    let item: CatalogItem

    @State private var mode: ReadingMode = .webtoon
    @State private var zonePreset: TapZonePreset = .kindle
    @State private var pageIndex = 0
    @State private var webtoonOffset: CGFloat = 0
    @State private var gap: Double = 0
    @State private var chromeVisible = true
    @State private var modeDrawer = false
    @State private var zoneDrawer = false
    @State private var filterDrawer = false
    @State private var scrollDrawer = false
    @State private var smartInvert = false
    @State private var unsharp = false
    @State private var autoCrop = false
    @State private var orientation: MangaOrientationLock = .sensor
    @State private var autoscroll = false
    @State private var scrollSpeed: Double = 48
    @State private var stopMinutes: Int?
    @State private var remainingSeconds: Int = 0
    @State private var tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var didRestore = false

    private var pages: [String] {
        item.pageURLs
    }

    private var pageCount: Int {
        pages.isEmpty ? MangaPageSynth.placeholderCount : pages.count
    }

    private var usesWebtoonProgress: Bool {
        mode == .webtoon
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                app.theme.backgroundColor.ignoresSafeArea()
                content(in: size)
                    .ignoresSafeArea()
                tapCatcher(in: size)
                    .padding(.horizontal, chromeVisible ? 24 : 0)
                    .padding(.vertical, chromeVisible ? 56 : 0)
                    .allowsHitTesting(!modeDrawer && !zoneDrawer && !filterDrawer && !scrollDrawer)
                if chromeVisible {
                    chrome
                }
                if let stopMinutes, autoscroll {
                    timerBadge(minutes: stopMinutes)
                }
            }
        }
        .background(app.theme.backgroundColor)
        .background(MangaOrientationHost(lock: orientation))
        .statusBarHidden(!chromeVisible)
        .toolbar(.hidden, for: .navigationBar)
        .contextualDrawer(isPresented: $modeDrawer) { modeDrawerContent }
        .contextualDrawer(isPresented: $zoneDrawer) { zoneDrawerContent }
        .contextualDrawer(isPresented: $filterDrawer) { filterDrawerContent }
        .contextualDrawer(isPresented: $scrollDrawer) { scrollDrawerContent }
        .onAppear(perform: restore)
        .onDisappear(perform: persist)
        .onChange(of: pageIndex) { _, _ in persist() }
        .onChange(of: webtoonOffset) { _, _ in persist() }
        .onChange(of: mode) { _, newMode in
            HapticTap.light()
            if newMode != .webtoon {
                autoscroll = false
            }
            persist()
        }
        .onReceive(tick) { _ in
            advanceAutoscroll()
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        let dual = mode == .dualPage && size.width > 700
        Group {
            if mode == .webtoon {
                webtoonStack(width: size.width)
            } else if dual {
                dualPager(size: size)
            } else if mode.isHorizontal {
                horizontalPager(size: size)
            } else {
                verticalPager(size: size)
            }
        }
        .modifier(MangaFilterStyle(invert: smartInvert, unsharp: unsharp))
    }

    private func webtoonStack(width: CGFloat) -> some View {
        MangaWebtoonScroll(
            pageCount: pageCount,
            width: width,
            spacing: gap,
            offset: $webtoonOffset,
            autoscroll: autoscroll,
            speed: scrollSpeed
        ) { index in
            pageView(index: index, fill: false)
                .frame(width: width)
        }
    }

    private func horizontalPager(size: CGSize) -> some View {
        let indices = mode.reversesDirection ? Array((0..<pageCount).reversed()) : Array(0..<pageCount)
        return TabView(selection: horizontalSelection) {
            ForEach(indices, id: \.self) { index in
                pageView(index: index, fill: autoCrop)
                    .frame(width: size.width, height: size.height)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, mode.reversesDirection ? .rightToLeft : .leftToRight)
    }

    private var horizontalSelection: Binding<Int> {
        Binding(
            get: { min(max(pageIndex, 0), max(pageCount - 1, 0)) },
            set: { pageIndex = min(max($0, 0), max(pageCount - 1, 0)) }
        )
    }

    private func verticalPager(size: CGSize) -> some View {
        TabView(selection: horizontalSelection) {
            ForEach(0..<pageCount, id: \.self) { index in
                pageView(index: index, fill: autoCrop)
                    .frame(width: size.width, height: size.height)
                    .rotationEffect(.degrees(-90))
                    .frame(width: size.height, height: size.width)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: size.height, height: size.width)
        .rotationEffect(.degrees(90))
        .frame(width: size.width, height: size.height)
    }

    private func dualPager(size: CGSize) -> some View {
        let spreads = stride(from: 0, to: pageCount, by: 2).map { $0 }
        return TabView(selection: spreadSelection) {
            ForEach(spreads, id: \.self) { start in
                HStack(spacing: 0) {
                    let left = mode.reversesDirection ? start + 1 : start
                    let right = mode.reversesDirection ? start : start + 1
                    dualSlot(index: left, width: size.width / 2, height: size.height)
                    dualSlot(index: right, width: size.width / 2, height: size.height)
                }
                .environment(\.layoutDirection, .leftToRight)
                .tag(start)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var spreadSelection: Binding<Int> {
        Binding(
            get: {
                let start = (pageIndex / 2) * 2
                return min(start, max(pageCount - 1, 0))
            },
            set: { pageIndex = min(max($0, 0), max(pageCount - 1, 0)) }
        )
    }

    @ViewBuilder
    private func dualSlot(index: Int, width: CGFloat, height: CGFloat) -> some View {
        if index >= 0, index < pageCount {
            pageView(index: index, fill: autoCrop)
                .frame(width: width, height: height)
        } else {
            app.theme.backgroundColor
                .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private func pageView(index: Int, fill: Bool) -> some View {
        let fit: ContentMode = fill ? .fill : .fit
        if pages.isEmpty {
            MangaSynthPage(index: index, total: pageCount, crop: autoCrop)
                .aspectRatio(2.0 / 3.0, contentMode: fit)
                .clipped()
        } else {
            MangaRemotePage(reference: pages[index], fill: fill)
        }
    }

    private func tapCatcher(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        HapticTap.light()
                        autoscroll = true
                        scrollDrawer = true
                        if stopMinutes == nil {
                            armTimer(minutes: 15)
                        }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .global)
                    .onEnded { value in
                        let origin = value.location
                        let action = TapZoneMap.action(
                            preset: zonePreset,
                            x: origin.x,
                            y: origin.y,
                            width: size.width,
                            height: size.height
                        )
                        HapticTap.light()
                        apply(action)
                    }
            )
    }

    private func apply(_ action: TapZoneAction) {
        switch action {
        case .menu:
            withAnimation(.easeInOut(duration: 0.2)) {
                chromeVisible.toggle()
            }
        case .next:
            step(forward: !mode.reversesDirection || mode == .webtoon || mode == .singleVertical)
        case .previous:
            step(forward: mode.reversesDirection && mode.isHorizontal)
        }
    }

    private func step(forward: Bool) {
        let delta = forward ? 1 : -1
        let stride = (mode == .dualPage) ? 2 : 1
        let next = pageIndex + (delta * stride)
        pageIndex = min(max(next, 0), max(pageCount - 1, 0))
    }

    private var chrome: some View {
        VStack {
            HStack(spacing: 10) {
                IconButton(systemName: "xmark", tooltip: "Đóng") {
                    HapticTap.light()
                    persist()
                    dismiss()
                }
                IconButton(systemName: "chevron.backward", tooltip: "Quay lại") {
                    HapticTap.light()
                    persist()
                    dismiss()
                }
                Spacer(minLength: 0)
                pageCapsule
                IconButton(systemName: "rectangle.split.2x1", tooltip: "Chế độ đọc") {
                    HapticTap.light()
                    modeDrawer = true
                }
                IconButton(systemName: "hand.tap", tooltip: "Vùng chạm") {
                    HapticTap.light()
                    zoneDrawer = true
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                IconButton(systemName: "crop", tooltip: "Bộ lọc") {
                    HapticTap.light()
                    filterDrawer = true
                }
                IconButton(systemName: autoscroll ? "timer" : "timer", tooltip: "Tự cuộn") {
                    HapticTap.light()
                    scrollDrawer = true
                }
                IconButton(
                    systemName: vaulted ? "bookmark.fill" : "bookmark",
                    tooltip: vaulted ? "Bỏ khỏi kho" : "Lưu vào kho"
                ) {
                    HapticTap.light()
                    app.toggleVault(sourceID: sourceID, item: item)
                    app.showHUD(vaulted ? "Đã lưu vào kho" : "Đã bỏ khỏi kho")
                }
                Spacer(minLength: 0)
                IconButton(systemName: "circle.lefthalf.filled", tooltip: "Nền chủ đề") {
                    HapticTap.light()
                    app.showHUD("Đang dùng nền chủ đề")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var pageCapsule: some View {
        Text("\(min(pageIndex + 1, pageCount))/\(pageCount)")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(app.theme.inkColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(app.theme.backgroundColor.opacity(0.82), in: Capsule())
            .accessibilityLabel("Trang \(min(pageIndex + 1, pageCount)) trên \(pageCount)")
    }

    private func timerBadge(minutes: Int) -> some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text("\(max(remainingSeconds, 0))")
                        .monospacedDigit()
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(app.theme.inkColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(app.theme.primaryColor.opacity(0.9), in: Capsule())
                .accessibilityLabel("Còn \(max(remainingSeconds, 0)) giây, hẹn \(minutes) phút")
                .padding(.trailing, 28)
                .padding(.top, 56)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private var modeDrawerContent: some View {
        MangaDrawerShell(title: "Chế độ") {
            ForEach(ReadingMode.allCases, id: \.self) { reading in
                Button {
                    HapticTap.light()
                    mode = reading
                } label: {
                    Label(reading.accessibilityName, systemImage: reading == mode ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.theme.inkColor)
            }
        }
    }

    private var zoneDrawerContent: some View {
        MangaDrawerShell(title: "Vùng chạm") {
            ForEach(TapZonePreset.allCases, id: \.self) { preset in
                Button {
                    HapticTap.light()
                    zonePreset = preset
                } label: {
                    Label(preset.accessibilityName, systemImage: preset == zonePreset ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(app.theme.inkColor)
            }
        }
    }

    private var filterDrawerContent: some View {
        MangaDrawerShell(title: "Bộ lọc") {
            Toggle("Đảo màu thông minh", isOn: $smartInvert)
            Text("Đảo màu áp dụng ColorInvert cho nền ít sắc.")
                .font(.caption)
                .foregroundStyle(app.theme.inkColor.opacity(0.7))
            Toggle("Làm nét", isOn: $unsharp)
            Toggle("Tự cắt viền", isOn: $autoCrop)
            Text("Khoảng cách webtoon")
                .font(.caption)
                .foregroundStyle(app.theme.inkColor)
            Slider(value: $gap, in: 0...24, step: 1) {
                Text("Khoảng cách")
            }
            HStack {
                ForEach(MangaOrientationLock.allCases) { lock in
                    Button {
                        HapticTap.light()
                        orientation = lock
                    } label: {
                        Image(systemName: lock.symbol)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                orientation == lock ? app.theme.primaryColor.opacity(0.35) : Color.clear,
                                in: RoundedRectangle(cornerRadius: app.theme.corner, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lock.accessibilityName)
                    .foregroundStyle(app.theme.inkColor)
                }
            }
        }
        .tint(app.theme.primaryColor)
    }

    private var scrollDrawerContent: some View {
        MangaDrawerShell(title: "Tự cuộn") {
            Toggle("Đang cuộn", isOn: $autoscroll)
            Text("Tốc độ")
                .font(.caption)
                .foregroundStyle(app.theme.inkColor)
            Slider(value: $scrollSpeed, in: 12...180, step: 4) {
                Text("Tốc độ")
            }
            HStack {
                ForEach(MangaAutoscrollStop.allCases) { chip in
                    Button {
                        HapticTap.light()
                        armTimer(minutes: chip.minutes)
                        autoscroll = true
                    } label: {
                        Text("\(chip.minutes)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                stopMinutes == chip.minutes ? app.theme.primaryColor : app.theme.inkColor.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dừng sau \(chip.minutes) phút")
                    .foregroundStyle(app.theme.inkColor)
                }
            }
        }
        .tint(app.theme.primaryColor)
    }

    private var vaulted: Bool {
        app.inVault(sourceID: sourceID, item: item)
    }

    private func armTimer(minutes: Int) {
        stopMinutes = minutes
        remainingSeconds = minutes * 60
    }

    private func advanceAutoscroll() {
        guard autoscroll else { return }
        if mode != .webtoon {
            let interval = max(1, Int(90 / max(scrollSpeed, 12)))
            if remainingSeconds % interval == 0 {
                step(forward: true)
            }
        }
        guard stopMinutes != nil else { return }
        remainingSeconds = max(0, remainingSeconds - 1)
        if remainingSeconds == 0 {
            autoscroll = false
            stopMinutes = nil
            app.showHUD("Đã dừng tự cuộn")
        }
    }

    private var mediaRef: MediaRef {
        app.mediaRef(sourceID: sourceID, item: item)
    }

    private func restore() {
        guard !didRestore else { return }
        didRestore = true
        guard let snapshot = app.progress(for: mediaRef) else { return }
        switch snapshot.payload {
        case .mangaPaged(let page, let total):
            let clampedTotal = max(total, 1)
            let resolved = min(max(page, 0), pageCount - 1)
            if clampedTotal == pageCount || page < pageCount {
                pageIndex = resolved
            }
        case .mangaWebtoon(let yOffset):
            webtoonOffset = CGFloat(yOffset)
            mode = .webtoon
            let estimated = Int(yOffset / 900)
            pageIndex = min(max(estimated, 0), max(pageCount - 1, 0))
        default:
            break
        }
    }

    private func persist() {
        let payload: ProgressPayload
        if usesWebtoonProgress {
            payload = .mangaWebtoon(yOffset: Double(webtoonOffset))
        } else {
            payload = .mangaPaged(page: pageIndex, total: pageCount)
        }
        app.saveProgress(
            ProgressSnapshot(ref: mediaRef, updatedAt: Date(), payload: payload)
        )
    }
}

private struct MangaWebtoonScroll<Page: View>: View {
    var pageCount: Int
    var width: CGFloat
    var spacing: Double
    @Binding var offset: CGFloat
    var autoscroll: Bool
    var speed: Double
    @ViewBuilder var page: (Int) -> Page

    var body: some View {
        MangaOffsetScroll(
            offset: $offset,
            autoscroll: autoscroll,
            pointsPerSecond: speed
        ) {
            LazyVStack(spacing: spacing) {
                ForEach(0..<pageCount, id: \.self) { index in
                    page(index)
                }
            }
            .frame(width: width)
        }
    }
}

private struct MangaOffsetScroll<Content: View>: UIViewRepresentable {
    @Binding var offset: CGFloat
    var autoscroll: Bool
    var pointsPerSecond: Double
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delegate = context.coordinator
        let host = UIHostingController(rootView: AnyView(content()))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        context.coordinator.host = host
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content())
        context.coordinator.pointsPerSecond = pointsPerSecond
        context.coordinator.autoscroll = autoscroll
        if !context.coordinator.didRestore, offset > 0 {
            context.coordinator.didRestore = true
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        }
        context.coordinator.syncTimer()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var offset: Binding<CGFloat>
        var host: UIHostingController<AnyView>?
        weak var scrollView: UIScrollView?
        var autoscroll = false
        var pointsPerSecond: Double = 48
        var didRestore = false
        private var timer: Timer?

        init(offset: Binding<CGFloat>) {
            self.offset = offset
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            let y = max(0, scrollView.contentOffset.y)
            if abs(offset.wrappedValue - y) > 0.5 {
                offset.wrappedValue = y
            }
        }

        func syncTimer() {
            if autoscroll {
                guard timer == nil else { return }
                let next = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    self?.tick()
                }
                timer = next
                RunLoop.main.add(next, forMode: .common)
            } else {
                timer?.invalidate()
                timer = nil
            }
        }

        private func tick() {
            guard let scrollView, autoscroll else { return }
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let next = min(maxY, scrollView.contentOffset.y + CGFloat(pointsPerSecond / 30.0))
            scrollView.setContentOffset(CGPoint(x: 0, y: next), animated: false)
            if next >= maxY {
                autoscroll = false
                syncTimer()
            }
        }
    }
}

private struct MangaFilterStyle: ViewModifier {
    var invert: Bool
    var unsharp: Bool

    func body(content: Content) -> some View {
        content
            .contrast(unsharp ? 1.18 : 1)
            .brightness(unsharp ? -0.02 : 0)
            .colorInvert(invert)
    }
}

private extension View {
    @ViewBuilder
    func colorInvert(_ enabled: Bool) -> some View {
        if enabled {
            self.colorInvert()
        } else {
            self
        }
    }
}

private struct MangaDrawerShell<Content: View>: View {
    @Environment(AppModel.self) private var app
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(app.theme.inkColor)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(app.theme.backgroundColor)
        .foregroundStyle(app.theme.inkColor)
    }
}

private struct MangaSynthPage: View {
    var index: Int
    var total: Int
    var crop: Bool

    var body: some View {
        let ink = MangaPageSynth.ink(for: index)
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(Color(red: ink.red, green: ink.green, blue: ink.blue)))
            let margin = crop ? size.width * 0.04 : size.width * 0.08
            var panel = rect.insetBy(dx: margin, dy: margin * 1.2)
            context.stroke(Path(roundedRect: panel, cornerRadius: 8), with: .color(.white.opacity(0.55)), lineWidth: 1.5)
            panel = panel.insetBy(dx: 18, dy: 28)
            let rows = 5
            for row in 0..<rows {
                let y = panel.minY + panel.height * CGFloat(row) / CGFloat(rows)
                var bar = CGRect(x: panel.minX, y: y, width: panel.width * (0.55 + 0.08 * CGFloat(row % 3)), height: 8)
                context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(.white.opacity(0.78)))
            }
            let bubble = CGRect(x: panel.minX, y: panel.minY, width: panel.width * 0.46, height: 54)
            context.fill(Path(ellipseIn: bubble), with: .color(.white.opacity(0.16)))
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(index + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .padding(10)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("Trang minh họa \(index + 1) trên \(total)")
    }
}

private struct MangaRemotePage: View {
    var reference: String
    var fill: Bool

    var body: some View {
        let fit: ContentMode = fill ? .fill : .fit
        Group {
            if let url = MangaPageLocator.resolve(reference) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: fit)
                    case .failure:
                        MangaMissingPage()
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            } else {
                MangaMissingPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private enum MangaPageLocator {
    static func resolve(_ string: String) -> URL? {
        if let located = MediaLocator.url(for: string) {
            return located
        }
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return URL(string: string)
        }
        if string.hasPrefix("file://") {
            return URL(string: string)
        }
        if string.hasPrefix("/") {
            return URL(fileURLWithPath: string)
        }
        return URL(string: string)
    }
}

private struct MangaMissingPage: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
            Text("Không mở được trang")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35))
        .accessibilityLabel("Không mở được trang")
    }
}

private struct MangaOrientationHost: UIViewControllerRepresentable {
    var lock: MangaOrientationLock

    func makeUIViewController(context: Context) -> MangaOrientationController {
        let controller = MangaOrientationController()
        controller.lock = lock
        return controller
    }

    func updateUIViewController(_ controller: MangaOrientationController, context: Context) {
        controller.lock = lock
        controller.applyLock()
    }
}

private final class MangaOrientationController: UIViewController {
    var lock: MangaOrientationLock = .sensor

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        switch lock {
        case .portrait: return .portrait
        case .landscape: return .landscape
        case .sensor: return .all
        }
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        switch lock {
        case .portrait: return .portrait
        case .landscape: return .landscapeRight
        case .sensor: return .portrait
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyLock()
    }

    func applyLock() {
        let value: Int
        switch lock {
        case .portrait:
            value = UIInterfaceOrientation.portrait.rawValue
        case .landscape:
            value = UIInterfaceOrientation.landscapeRight.rawValue
        case .sensor:
            UIViewController.attemptRotationToDeviceOrientation()
            return
        }
        UIDevice.current.setValue(value, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
