import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import UIKit

struct CinemaPlayerView: View {
    var sourceID: SourceID
    var item: CatalogItem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var host = CinemaPlaybackHost()
    @State private var chrome = true
    @State private var fitMode = true
    @State private var landscapeLocked = false
    @State private var cues: [SubtitleCue] = []
    @State private var importedCues: [SubtitleCue] = []
    @State private var cueFont: Double = 17
    @State private var cueInk = Color.white
    @State private var cueBox = Color.black
    @State private var cueOpacity: Double = 0.62
    @State private var danmakuOn = false
    @State private var danmakuOpacity: Double = 0.85
    @State private var danmakuSpeed: Double = 1
    @State private var volume: Double = 1
    @State private var seconds: Double = 0
    @State private var length: Double = 0
    @State private var videoSize = CGSize(width: 16, height: 9)
    @State private var scrubLabel: String?
    @State private var scrubTarget: Double?
    @State private var captionsOpen = false
    @State private var importOpen = false
    @State private var importQuery = ""
    @State private var shareOpen = false
    @State private var pipWanted = false
    @State private var hideWork: Task<Void, Never>?

    private let demoDanmaku = ["Ê đẹp quá", "Xem lại lần hai", "Im lặng nào", "Mưa rồi", "Cảnh này hay"]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black.ignoresSafeArea()
                stage(in: size)
                if danmakuOn {
                    CinemaDanmakuLayer(lines: demoDanmaku, speed: danmakuSpeed, opacity: danmakuOpacity)
                }
                captionOverlay
                if let scrubLabel {
                    Text(scrubLabel)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .accessibilityLabel("Xem trước \(scrubLabel)")
                }
                if chrome { controls(in: size) }
                gestureCatcher(in: size)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(!chrome)
        .persistentSystemOverlays(chrome ? .automatic : .hidden)
        .onAppear(perform: boot)
        .onDisappear {
            persist()
            host.pause()
            host.pip?.stopPictureInPicture()
        }
        .task { await tick() }
        .contextualDrawer(isPresented: $captionsOpen) { captionDrawer }
        .sheet(isPresented: $importOpen) { importSheet }
        .sheet(isPresented: $shareOpen) { ShareSheet(items: [item.title]) }
    }

    @ViewBuilder
    private func stage(in size: CGSize) -> some View {
        if playURL == nil {
            VStack(spacing: 14) {
                Image(systemName: "play.slash")
                    .font(.system(size: 52, weight: .ultraLight))
                    .accessibilityLabel("Không phát được")
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("Không có nguồn phát")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
            .padding(32)
        } else {
            CinemaVideoSurface(
                host: host,
                fit: fitMode,
                videoSize: videoSize,
                container: size
            )
            .ignoresSafeArea()
        }
    }

    private var captionOverlay: some View {
        VStack {
            Spacer()
            if let cue = activeCues.last(where: { seconds >= $0.start && seconds <= $0.end }) {
                Text(cue.text)
                    .font(.system(size: cueFont, weight: .semibold))
                    .foregroundStyle(cueInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(cueBox.opacity(cueOpacity), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 36)
                    .padding(.bottom, chrome ? 118 : 40)
                    .accessibilityLabel(cue.text)
            }
        }
        .allowsHitTesting(false)
    }

    private func controls(in size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                IconButton(systemName: "chevron.backward", tooltip: "Đóng") {
                    HapticTap.light()
                    persist()
                    dismiss()
                }
                Spacer(minLength: 8)
                IconButton(systemName: "captions.bubble", tooltip: "Phụ đề") {
                    HapticTap.light()
                    captionsOpen = true
                }
                IconButton(systemName: fitMode ? "aspectratio" : "rectangle.arrowtriangle.2.inward", tooltip: fitMode ? "Vừa khung" : "Phủ đầy") {
                    HapticTap.light()
                    fitMode.toggle()
                }
                IconButton(systemName: "rotate.right", tooltip: landscapeLocked ? "Đang xoay ngang" : "Xoay ngang") {
                    HapticTap.light()
                    forceLandscape()
                }
                CinemaAirPlayButton()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("AirPlay")
                IconButton(systemName: pipWanted ? "pip.exit" : "pip.enter", tooltip: "Hình trong hình") {
                    HapticTap.light()
                    togglePiP()
                }
                IconButton(
                    systemName: app.inVault(sourceID: sourceID, item: item) ? "bookmark.fill" : "bookmark",
                    tooltip: "Kho"
                ) {
                    HapticTap.light()
                    app.toggleVault(sourceID: sourceID, item: item)
                }
                if nextEpisode != nil {
                    IconButton(systemName: "forward.end", tooltip: "Tập sau") {
                        HapticTap.light()
                        jumpNext()
                    }
                }
            }
            .padding(.horizontal, EdgeDeadzone.margin)
            .padding(.top, 8)
            Spacer()
            bottomTransport
                .padding(.horizontal, EdgeDeadzone.margin)
                .padding(.bottom, EdgeDeadzone.margin)
        }
        .foregroundStyle(.white)
    }

    private var bottomTransport: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if IntroOutroHint.showIntroSkip(current: seconds) {
                    Button {
                        HapticTap.light()
                        host.seek(to: 90)
                        seconds = 90
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bỏ qua phần mở đầu")
                }
                if IntroOutroHint.inCredits(current: seconds, duration: length), nextEpisode != nil {
                    Button {
                        HapticTap.light()
                        jumpNext()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Tập tiếp theo")
                }
                Spacer()
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 10) {
                Text(TimeCodes.format(seconds))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 52, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { min(seconds, max(length, 1)) },
                        set: { host.seek(to: $0); seconds = $0 }
                    ),
                    in: 0...max(length, 1)
                )
                .tint(.white)
                .accessibilityLabel("Tiến trình")
                Text(TimeCodes.format(length))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 52, alignment: .trailing)
            }
            .foregroundStyle(.white)
        }
    }

    private var captionDrawer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Phụ đề")
                .font(.headline)
            labeledSlider("Cỡ chữ", value: $cueFont, range: 12...34)
            labeledSlider("Độ đục hộp", value: $cueOpacity, range: 0...1)
            HStack(spacing: 12) {
                Text("Màu chữ").font(.caption)
                ColorPicker("Màu chữ", selection: $cueInk, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Màu chữ phụ đề")
                Text("Màu hộp").font(.caption)
                ColorPicker("Màu hộp", selection: $cueBox, supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel("Màu hộp phụ đề")
            }
            Toggle(isOn: $danmakuOn) {
                Text("Danmaku")
            }
            .accessibilityLabel("Bật danmaku")
            labeledSlider("Tốc độ danmaku", value: $danmakuSpeed, range: 0.35...2.4)
            labeledSlider("Độ đục danmaku", value: $danmakuOpacity, range: 0.15...1)
            Button {
                HapticTap.light()
                importOpen = true
            } label: {
                Label("Tìm phụ đề", systemImage: "text.magnifyingglass")
            }
            .accessibilityLabel("Tìm phụ đề")
            Button {
                HapticTap.light()
                pasteSubtitles()
            } label: {
                Label("Dán phụ đề", systemImage: "doc.on.clipboard")
            }
            .accessibilityLabel("Dán phụ đề")
        }
        .padding(20)
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dán SRT hoặc VTT. Meine không gọi máy chủ phụ đề.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Tìm trong tệp đã dán", text: $importQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Tìm phụ đề")
                ScrollView {
                    Text(importPreview)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    HapticTap.light()
                    pasteSubtitles()
                } label: {
                    Text("Dán phụ đề")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Dán phụ đề")
            }
            .padding(20)
            .navigationTitle("OpenSubtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { importOpen = false }
                        .accessibilityLabel("Đóng")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private func gestureCatcher(in size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(drag(in: size))
            .onTapGesture {
                HapticTap.light()
                withAnimation(.easeInOut(duration: 0.22)) { chrome.toggle() }
                if chrome { armHide() }
            }
            .allowsHitTesting(playURL != nil)
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard value.startLocation.x >= EdgeDeadzone.margin else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let vertical = EdgeDeadzone.isVerticalLock(dx: dx, dy: dy)
                if vertical, EdgeDeadzone.brightnessZone(width: size.width).contains(value.startLocation.x) {
                    nudgeBrightness(dy: dy, height: size.height)
                } else if vertical, EdgeDeadzone.volumeZone(width: size.width).contains(value.startLocation.x) {
                    let next = min(1, max(0, volume - Double(dy / max(size.height, 1))))
                    volume = next
                    host.setVolume(Float(next))
                    CinemaVolumeBridge.apply(next)
                } else if value.startLocation.y < size.height * 0.72, abs(dx) > abs(dy) {
                    let span = max(length, 30)
                    let preview = min(max(seconds + Double(dx / max(size.width, 1)) * span * 0.45, 0), max(length, 0))
                    scrubTarget = preview
                    scrubLabel = TimeCodes.format(preview)
                }
            }
            .onEnded { value in
                guard value.startLocation.x >= EdgeDeadzone.margin else {
                    scrubLabel = nil
                    scrubTarget = nil
                    return
                }
                if let target = scrubTarget {
                    host.seek(to: target)
                    seconds = target
                }
                scrubLabel = nil
                scrubTarget = nil
            }
    }

    private var playURL: URL? {
        MediaLocator.url(for: item.streamURL ?? "")
    }

    private var activeCues: [SubtitleCue] {
        importedCues.isEmpty ? cues : importedCues
    }

    private var importPreview: String {
        let rows = activeCues.filter { cue in
            importQuery.isEmpty || cue.text.localizedCaseInsensitiveContains(importQuery)
        }
        if rows.isEmpty { return "Chưa có cue." }
        return rows.prefix(12).map { "\(TimeCodes.format($0.start))  \($0.text)" }.joined(separator: "\n")
    }

    private var nextEpisode: CatalogItem? {
        guard let series = item.seriesID, !series.isEmpty else { return nil }
        let rows = app.itemsForSeries(series, sourceID: sourceID)
        guard let index = rows.firstIndex(where: { $0.id == item.id }) else { return nil }
        let next = index + 1
        guard rows.indices.contains(next) else { return nil }
        return rows[next]
    }

    private func boot() {
        cues = SubtitleParser.parse(item.subtitles ?? "")
        length = item.duration ?? 0
        Task { await AudioSessionCoordinator.shared.request(.videoExclusive) }
        guard let url = playURL else { return }
        host.load(url: url)
        host.setVolume(Float(volume))
        restore()
        host.play()
        armHide()
        Task { await readNaturalSize() }
    }

    private func restore() {
        let ref = app.mediaRef(sourceID: sourceID, item: item)
        guard let snapshot = app.progress(for: ref) else { return }
        let playing = length > 0 ? Duration.seconds(length) : nil
        let decision = ResumePolicy.decide(snapshot: snapshot, nowPlayingDuration: playing)
        switch decision.action {
        case .resume(let from, let toast):
            let mark = durationSeconds(from)
            host.seek(to: mark)
            seconds = mark
            app.showHUD(toast)
        case .restart:
            host.seek(to: 0)
            seconds = 0
        default:
            break
        }
    }

    private func durationSeconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private func readNaturalSize() async {
        guard let asset = host.player.currentItem?.asset else { return }
        let tracks = try? await asset.loadTracks(withMediaType: .video)
        guard let track = tracks?.first else { return }
        if let size = try? await track.load(.naturalSize), size.width > 0, size.height > 0 {
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let box = CGRect(origin: .zero, size: size).applying(transform)
            videoSize = CGSize(width: abs(box.width), height: abs(box.height))
        }
    }

    private func tick() async {
        var lastSave = Date.distantPast
        while !Task.isCancelled {
            let time = host.player.currentTime().seconds
            if time.isFinite, time >= 0, scrubLabel == nil { seconds = time }
            if let total = host.player.currentItem?.duration.seconds, total.isFinite, total > 0 {
                length = total
            }
            if Date().timeIntervalSince(lastSave) >= 5 {
                persist()
                lastSave = Date()
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func persist() {
        let total = max(length, 0.01)
        let completed = seconds / total >= 0.90
        let snapshot = ProgressSnapshot(
            ref: app.mediaRef(sourceID: sourceID, item: item),
            updatedAt: Date(),
            payload: .cinema(
                current: .seconds(seconds),
                duration: .seconds(total),
                completed: completed
            )
        )
        app.saveProgress(snapshot)
    }

    private func jumpNext() {
        guard let next = nextEpisode else { return }
        persist()
        app.showHUD(next.title)
    }

    private func pasteSubtitles() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            app.showHUD("Bảng tạm trống")
            return
        }
        let parsed = SubtitleParser.parse(text)
        if parsed.isEmpty {
            app.showHUD("Không đọc được phụ đề")
            return
        }
        importedCues = parsed
        app.showHUD("Đã nạp \(parsed.count) cue")
    }

    private func nudgeBrightness(dy: CGFloat, height: CGFloat) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let screen = scene.screen
        let next = min(1, max(0.01, screen.brightness - dy / max(height, 1)))
        screen.brightness = next
    }

    private func forceLandscape() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        landscapeLocked = true
        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscapeRight)
        scene.requestGeometryUpdate(preferences) { _ in
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private func togglePiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            app.showHUD("Thiết bị không hỗ trợ PiP")
            return
        }
        host.ensurePiP()
        guard let pip = host.pip, pip.isPictureInPicturePossible else {
            app.showHUD("Chưa thể thu nhỏ")
            return
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
            pipWanted = false
        } else {
            pip.startPictureInPicture()
            pipWanted = true
        }
    }

    private func armHide() {
        hideWork?.cancel()
        hideWork = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) { chrome = false }
            }
        }
    }
}

@MainActor
final class CinemaPlaybackHost: ObservableObject {
    let player = AVPlayer()
    private(set) var pip: AVPictureInPictureController?
    private weak var boundLayer: AVPlayerLayer?

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        let safe = seconds.isFinite ? max(0, seconds) : 0
        let time = CMTime(seconds: safe, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setVolume(_ value: Float) {
        player.volume = min(1, max(0, value))
    }

    func bind(layer: AVPlayerLayer) {
        boundLayer = layer
        layer.player = player
        ensurePiP()
    }

    func ensurePiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported(), let layer = boundLayer else { return }
        if pip == nil {
            pip = AVPictureInPictureController(playerLayer: layer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = false
        }
    }
}

struct CinemaVideoSurface: UIViewRepresentable {
    var host: CinemaPlaybackHost
    var fit: Bool
    var videoSize: CGSize
    var container: CGSize

    func makeUIView(context: Context) -> CinemaPlayerCanvas {
        let view = CinemaPlayerCanvas()
        view.backgroundColor = .black
        host.bind(layer: view.playerLayer)
        return view
    }

    func updateUIView(_ view: CinemaPlayerCanvas, context: Context) {
        host.bind(layer: view.playerLayer)
        view.playerLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        view.fitFrame = AspectFitCalculator.fittedRect(video: videoSize, container: container)
        view.usesFit = fit
        view.setNeedsLayout()
    }
}

final class CinemaPlayerCanvas: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            return AVPlayerLayer()
        }
        return layer
    }
    var fitFrame: CGRect = .zero
    var usesFit = true

    override func layoutSubviews() {
        super.layoutSubviews()
        if usesFit, fitFrame.width > 1, fitFrame.height > 1 {
            playerLayer.frame = fitFrame
        } else {
            playerLayer.frame = bounds
        }
    }
}

struct CinemaAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = .white
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

enum CinemaVolumeBridge {
    static func apply(_ value: Double) {
        let clamped = min(1, max(0, value))
        let holder = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        guard let slider = holder.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = Float(clamped)
    }
}

struct CinemaDanmakuLayer: View {
    var lines: [String]
    var speed: Double
    var opacity: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let span = geo.size.width + 220
                        let phase = (t * 70 * speed + Double(index) * 140).truncatingRemainder(dividingBy: span)
                        Text(line)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(opacity))
                            .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                            .position(x: span - phase - 40, y: 72 + CGFloat(index) * 28)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
