import SwiftUI
import AVFoundation
import UIKit

struct AudioPlayerView: View {
    var sourceID: SourceID
    var item: CatalogItem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var engine = AudioPlaybackEngine()
    @State private var queue: [CatalogItem] = []
    @State private var queueIndex = 0
    @State private var shuffle = false
    @State private var repeatMode: RepeatMode = .off
    @State private var order: [Int] = []
    @State private var lyricsFull = false
    @State private var meshOn = true
    @State private var eqOpen = false
    @State private var sleepOpen = false
    @State private var shareOpen = false
    @State private var sharePicks: Set<Int> = []
    @State private var shareImage: UIImage?
    @State private var bands: [Float] = Array(repeating: 0, count: 10)
    @State private var bassBoost: Float = 0
    @State private var crossfade: Double = 3
    @State private var duck: Float = 1
    @State private var restored = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            ZStack {
                backdrop
                VStack(spacing: 0) {
                    topChrome
                    Spacer(minLength: 8)
                    stage
                    Spacer(minLength: 8)
                    transport(now: context.date)
                    timeline
                    bottomChrome
                }
                .padding(24)
            }
            .onChange(of: context.date) { _, date in
                engine.tick(date: date, crossfade: crossfade, duck: duck, sleep: app.sleepTimer)
                applySleep(now: date)
                if engine.shouldAdvance {
                    engine.shouldAdvance = false
                    advance(automatic: true)
                }
                if Int(date.timeIntervalSinceReferenceDate) % 4 == 0 {
                    persist()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: boot)
        .onDisappear {
            persist()
            engine.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("meine.audio.policy"))) { note in
            applyPolicy(note.userInfo?["policy"] as? String)
        }
        .contextualDrawer(isPresented: $eqOpen) { eqDrawer }
        .contextualDrawer(isPresented: $sleepOpen) { sleepDrawer }
        .sheet(isPresented: $shareOpen) { shareSheet }
    }

    private var current: CatalogItem {
        guard queue.indices.contains(queueIndex) else { return item }
        return queue[queueIndex]
    }

    private var lines: [LyricLine] {
        LyricParser.parse(current.lyrics ?? "")
    }

    private var activeLine: Int {
        let t = engine.seconds
        var index = 0
        for (offset, line) in lines.enumerated() where line.time <= t {
            index = offset
        }
        return index
    }

    private var backdrop: some View {
        ZStack {
            if meshOn {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        app.theme.backgroundColor,
                        app.theme.primaryColor.opacity(0.85),
                        app.theme.activeColor.opacity(0.7),
                        app.theme.primaryColor.opacity(0.45),
                        app.theme.backgroundColor,
                        app.theme.activeColor,
                        app.theme.activeColor.opacity(0.55),
                        app.theme.backgroundColor,
                        app.theme.primaryColor
                    ]
                )
                .ignoresSafeArea()
            } else {
                app.theme.backgroundColor.ignoresSafeArea()
            }
        }
    }

    private var topChrome: some View {
        HStack {
            IconButton(systemName: "chevron.down", tooltip: "Đóng") {
                HapticTap.light()
                persist()
                dismiss()
            }
            Spacer()
            IconButton(systemName: "slider.vertical.3", tooltip: "Chỉnh âm") {
                HapticTap.light()
                eqOpen = true
            }
            IconButton(systemName: meshOn ? "water.waves" : "circle.lefthalf.filled", tooltip: meshOn ? "Nền lưới" : "Nền đặc") {
                HapticTap.light()
                withAnimation(.spring(duration: 0.45)) { meshOn.toggle() }
            }
            IconButton(systemName: "paintpalette", tooltip: "Màu giao diện") {
                HapticTap.light()
                withAnimation(.spring(duration: 0.45)) { meshOn = false }
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        if lyricsFull {
            lyricStage
        } else {
            vinylStage
        }
    }

    private var vinylStage: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [app.theme.inkColor.opacity(0.15), app.theme.primaryColor, .black],
                            center: .center,
                            startRadius: 18,
                            endRadius: 150
                        )
                    )
                    .overlay {
                        Circle().stroke(app.theme.inkColor.opacity(0.18), lineWidth: 10)
                        Circle().stroke(app.theme.inkColor.opacity(0.08), lineWidth: 1).padding(28)
                        Circle().fill(app.theme.activeColor).frame(width: 28, height: 28)
                    }
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(engine.playing ? engine.seconds * 18 : 0))
                    .animation(engine.playing ? .linear(duration: 20).repeatForever(autoreverses: false) : .default, value: engine.playing)
                    .shadow(color: app.theme.primaryColor.opacity(0.45), radius: 28, y: 12)
                Text(current.symbol)
                    .font(.largeTitle)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 6) {
                Text(current.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(app.theme.inkColor)
                    .lineLimit(1)
                Text(current.artist ?? current.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(app.theme.inkColor.opacity(0.7))
                    .lineLimit(1)
            }
            lyricPeek
        }
    }

    private var lyricPeek: some View {
        Text(lines.isEmpty ? "Chưa có lời" : lines[min(activeLine, lines.count - 1)].text)
            .font(.body.weight(.medium))
            .foregroundStyle(app.theme.inkColor)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.35), value: activeLine)
    }

    private var lyricStage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    if lines.isEmpty {
                        Text("Chưa có lời cho bài này")
                            .foregroundStyle(app.theme.inkColor.opacity(0.7))
                    }
                    ForEach(lines) { line in
                        let active = line.id == activeLine
                        Text(line.text)
                            .font(active ? .title2.weight(.semibold) : .body)
                            .foregroundStyle(app.theme.inkColor.opacity(active ? 1 : 0.38))
                            .blur(radius: active ? 0 : 1.2)
                            .scaleEffect(active ? 1.04 : 0.96)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .animation(.spring(duration: 0.42, bounce: 0.25), value: activeLine)
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: activeLine) { _, id in
                withAnimation(.spring(duration: 0.45)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func transport(now: Date) -> some View {
        HStack(spacing: 28) {
            IconButton(systemName: repeatSymbol, tooltip: repeatTip) {
                HapticTap.light()
                cycleRepeat()
            }
            IconButton(systemName: "backward.fill", tooltip: "Bài trước") {
                HapticTap.light()
                skip(-1)
            }
            Button {
                HapticTap.light()
                engine.toggle()
            } label: {
                Image(systemName: engine.playing ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(app.theme.backgroundColor)
                    .frame(width: 68, height: 68)
                    .background(app.theme.inkColor, in: Circle())
            }
            .accessibilityLabel(engine.playing ? "Tạm dừng" : "Phát")
            IconButton(systemName: "forward.fill", tooltip: "Bài sau") {
                HapticTap.light()
                advance(automatic: false)
            }
            IconButton(systemName: shuffle ? "shuffle" : "shuffle", tooltip: shuffle ? "Phát ngẫu nhiên đang bật" : "Phát ngẫu nhiên", hierarchical: !shuffle) {
                HapticTap.light()
                shuffle.toggle()
                rebuildOrder()
            }
            .opacity(shuffle ? 1 : 0.55)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .top) {
            if let left = sleepLeft(now: now) {
                Text(left)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(app.theme.activeColor)
                    .offset(y: -16)
                    .accessibilityLabel("Hẹn giờ còn \(left)")
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { engine.seconds },
                    set: { engine.seek(to: $0) }
                ),
                in: 0...max(engine.duration, 1)
            )
            .tint(app.theme.activeColor)
            .accessibilityLabel("Tiến trình")
            HStack {
                Text(clock(engine.seconds)).font(.caption2.monospacedDigit())
                Spacer()
                Text("-\(clock(max(engine.duration - engine.seconds, 0)))").font(.caption2.monospacedDigit())
            }
            .foregroundStyle(app.theme.inkColor.opacity(0.7))
        }
    }

    private var bottomChrome: some View {
        HStack {
            IconButton(systemName: lyricsFull ? "quote.bubble.fill" : "quote.bubble", tooltip: lyricsFull ? "Thu lời" : "Lời bài hát") {
                HapticTap.light()
                withAnimation(.spring(duration: 0.4)) { lyricsFull.toggle() }
            }
            IconButton(systemName: "square.and.arrow.up", tooltip: "Chia sẻ lời") {
                HapticTap.light()
                sharePicks = [activeLine]
                shareOpen = true
            }
            Spacer()
            IconButton(
                systemName: app.inVault(sourceID: sourceID, item: current) ? "bookmark.fill" : "bookmark",
                tooltip: "Kho"
            ) {
                HapticTap.light()
                app.toggleVault(sourceID: sourceID, item: current)
            }
            IconButton(systemName: "timer", tooltip: "Hẹn giờ ngủ") {
                HapticTap.light()
                sleepOpen = true
            }
        }
        .padding(.top, 6)
    }

    private var eqDrawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EQ")
                .font(.headline)
                .foregroundStyle(app.theme.inkColor)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(AudioEQBands.frequencies.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { Double(bands[index]) },
                                set: {
                                    bands[index] = Float($0)
                                    engine.apply(bands: bands, bass: bassBoost)
                                }
                            ),
                            in: -12...12
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 92, height: 36)
                        Text(hzLabel(AudioEQBands.frequencies[index]))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(app.theme.inkColor.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Dải \(Int(AudioEQBands.frequencies[index])) héc")
                }
            }
            .frame(height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text("Bass boost \(Int(bassBoost)) dB")
                    .font(.caption)
                    .foregroundStyle(app.theme.inkColor)
                Slider(
                    value: Binding(
                        get: { Double(bassBoost) },
                        set: {
                            bassBoost = Float($0)
                            engine.apply(bands: bands, bass: bassBoost)
                        }
                    ),
                    in: 0...12
                )
                .tint(app.theme.activeColor)
                .accessibilityLabel("Tăng bass")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Crossfade \(Int(crossfade)) giây")
                    .font(.caption)
                    .foregroundStyle(app.theme.inkColor)
                Slider(value: $crossfade, in: 1...12, step: 1)
                    .tint(app.theme.primaryColor)
                    .accessibilityLabel("Chuyển bài mượt")
            }
        }
        .padding(20)
    }

    private var sleepDrawer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hẹn giờ ngủ")
                .font(.headline)
                .foregroundStyle(app.theme.inkColor)
            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes)") {
                        HapticTap.light()
                        var next = app.sleepTimer
                        next.deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
                        next.endOfTrack = false
                        next.fadeStarted = nil
                        app.sleepTimer = next
                        sleepOpen = false
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("\(minutes) phút")
                }
            }
            Button("Hết bài") {
                HapticTap.light()
                var next = app.sleepTimer
                next.endOfTrack = true
                next.deadline = nil
                next.fadeStarted = nil
                app.sleepTimer = next
                sleepOpen = false
            }
            .buttonStyle(.borderedProminent)
            .tint(app.theme.primaryColor)
            Button("Tắt hẹn giờ") {
                HapticTap.light()
                app.sleepTimer = SleepTimerState(deadline: nil, endOfTrack: false, fadeStarted: nil)
                duck = 1
                sleepOpen = false
            }
            .foregroundStyle(app.theme.inkColor.opacity(0.8))
        }
        .padding(20)
    }

    private var shareSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                cardPreview
                    .frame(width: 180, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: app.theme.corner, style: .continuous))
                ScrollView {
                    VStack(spacing: 8) {
                        if lines.isEmpty {
                            Text("Không có dòng lời để chọn")
                                .foregroundStyle(app.theme.inkColor.opacity(0.7))
                        }
                        ForEach(lines) { line in
                            Button {
                                HapticTap.light()
                                togglePick(line.id)
                            } label: {
                                HStack {
                                    Image(systemName: sharePicks.contains(line.id) ? "checkmark.circle.fill" : "circle")
                                    Text(line.text).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer()
                                }
                                .foregroundStyle(app.theme.inkColor)
                            }
                            .accessibilityLabel("Chọn dòng \(line.id + 1)")
                        }
                    }
                }
                if let shareImage {
                    ShareSheet(items: [shareImage])
                        .frame(height: 72)
                }
            }
            .padding(20)
            .background(app.theme.backgroundColor)
            .navigationTitle("Chia sẻ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { shareOpen = false }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { renderCard() }
        .onChange(of: sharePicks) { _, _ in renderCard() }
    }

    private var cardPreview: some View {
        AudioShareCard(
            title: current.title,
            artist: current.artist ?? current.subtitle,
            lines: pickedLines,
            primary: app.theme.primaryColor,
            active: app.theme.activeColor,
            ink: app.theme.inkColor,
            background: app.theme.backgroundColor
        )
    }

    private var pickedLines: [String] {
        lines.filter { sharePicks.contains($0.id) }.prefix(5).map(\.text)
    }

    private func togglePick(_ id: Int) {
        if sharePicks.contains(id) {
            sharePicks.remove(id)
        } else if sharePicks.count < 5 {
            sharePicks.insert(id)
        } else {
            app.showHUD("Chọn tối đa 5 dòng")
        }
    }

    private func renderCard() {
        let renderer = ImageRenderer(content: cardPreview.frame(width: 360, height: 640))
        renderer.scale = 3
        shareImage = renderer.uiImage
    }

    private func boot() {
        if let series = item.seriesID {
            let found = app.itemsForSeries(series, sourceID: sourceID)
            queue = found.isEmpty ? [item] : found
        } else {
            queue = [item]
        }
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            queueIndex = index
        }
        restore()
        rebuildOrder()
        playCurrent(seek: restoredSeconds)
    }

    private var restoredSeconds: Double {
        guard !restored, let snapshot = app.progress(for: ref(for: current)),
              case .music(let seconds, _, _, _) = snapshot.payload else { return 0 }
        return seconds
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        let ref = app.mediaRef(sourceID: sourceID, item: item)
        guard let snapshot = app.progress(for: ref),
              case .music(_, _, let mode, let shuffled) = snapshot.payload else { return }
        repeatMode = mode
        shuffle = shuffled
    }

    private func rebuildOrder() {
        order = Array(queue.indices)
        if shuffle {
            order.shuffle()
            if let here = order.firstIndex(of: queueIndex), here != 0 {
                order.swapAt(0, here)
            }
        }
    }

    private func playCurrent(seek: Double) {
        engine.play(item: current, seek: seek, bands: bands, bass: bassBoost, duck: duck) { message in
            app.showHUD(message)
        }
    }

    private func advance(automatic: Bool) {
        if repeatMode == .one && automatic {
            playCurrent(seek: 0)
            return
        }
        if app.sleepTimer.endOfTrack && automatic {
            engine.pause()
            app.sleepTimer = SleepTimerState(deadline: nil, endOfTrack: false, fadeStarted: nil)
            persist()
            return
        }
        guard let next = nextIndex(forward: true) else {
            engine.pause()
            persist()
            return
        }
        queueIndex = next
        playCurrent(seek: 0)
    }

    private func skip(_ delta: Int) {
        if delta < 0 && engine.seconds > 3 {
            engine.seek(to: 0)
            return
        }
        guard let next = nextIndex(forward: delta > 0) else { return }
        queueIndex = next
        playCurrent(seek: 0)
    }

    private func nextIndex(forward: Bool) -> Int? {
        guard !queue.isEmpty else { return nil }
        if shuffle {
            guard let pos = order.firstIndex(of: queueIndex) else { return queueIndex }
            let step = forward ? pos + 1 : pos - 1
            if order.indices.contains(step) { return order[step] }
            if repeatMode == .all {
                rebuildOrder()
                return order.first
            }
            return nil
        }
        let step = queueIndex + (forward ? 1 : -1)
        if queue.indices.contains(step) { return step }
        if repeatMode == .all { return forward ? 0 : queue.count - 1 }
        return nil
    }

    private func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    private var repeatSymbol: String {
        switch repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var repeatTip: String {
        switch repeatMode {
        case .off: return "Lặp tắt"
        case .all: return "Lặp tất cả"
        case .one: return "Lặp một bài"
        }
    }

    private func applyPolicy(_ policy: String?) {
        switch policy {
        case "videoExclusive", "ttsSolo":
            engine.pause()
        case "ttsDuckedMusic":
            duck = 0.2
            engine.setDuck(0.2)
        case "music":
            duck = 1
            engine.setDuck(1)
            engine.resume()
        default:
            break
        }
    }

    private func applySleep(now: Date) {
        var timer = app.sleepTimer
        if let deadline = timer.deadline {
            let remaining = deadline.timeIntervalSince(now)
            if remaining <= 0 {
                engine.pause()
                timer.deadline = nil
                timer.fadeStarted = nil
                app.sleepTimer = timer
                duck = 1
                return
            }
            if remaining <= 60, timer.fadeStarted == nil {
                timer.fadeStarted = now
                app.sleepTimer = timer
            }
        }
        let gain = SleepFade.gain(now: now, fadeStarted: app.sleepTimer.fadeStarted)
        engine.setSleepGain(gain)
        if gain <= 0 {
            engine.pause()
        }
    }

    private func sleepLeft(now: Date) -> String? {
        guard let deadline = app.sleepTimer.deadline else {
            return app.sleepTimer.endOfTrack ? "Hết bài" : nil
        }
        let left = max(0, Int(deadline.timeIntervalSince(now)))
        return clock(Double(left))
    }

    private func persist() {
        let snapshot = ProgressSnapshot(
            ref: ref(for: current),
            updatedAt: Date(),
            payload: .music(
                seconds: engine.seconds,
                trackID: current.id,
                repeatMode: repeatMode,
                shuffle: shuffle
            )
        )
        app.saveProgress(snapshot)
    }

    private func ref(for item: CatalogItem) -> MediaRef {
        app.mediaRef(sourceID: sourceID, item: item)
    }

    private func clock(_ value: Double) -> String {
        let total = max(0, Int(value))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func hzLabel(_ hz: Float) -> String {
        hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))"
    }
}

private struct AudioShareCard: View {
    var title: String
    var artist: String
    var lines: [String]
    var primary: Color
    var active: Color
    var ink: Color
    var background: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [primary, background, active.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(ink.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 8)
                .offset(y: -160)
            VStack(alignment: .leading, spacing: 14) {
                Spacer()
                Text(title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(ink)
                Text(artist)
                    .font(.headline)
                    .foregroundStyle(ink.opacity(0.75))
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(ink)
                }
                Spacer()
                Text("Meine")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.6))
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private final class AudioPlaybackEngine {
    var playing = false
    var seconds: Double = 0
    var duration: Double = 180
    var shouldAdvance = false

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var engine: AVAudioEngine?
    private var node: AVAudioPlayerNode?
    private var eq: AVAudioUnitEQ?
    private var file: AVAudioFile?
    private var sampleRate: Double = 44_100
    private var startedAt: Date?
    private var pausedAt: Double = 0
    private var usingEngine = false
    private var duck: Float = 1
    private var sleepGain: Float = 1
    private var userVolume: Float = 1
    private var fading = false

    func play(item: CatalogItem, seek: Double, bands: [Float], bass: Float, duck: Float, hud: (String) -> Void) {
        stop()
        self.duck = duck
        sleepGain = 1
        seconds = seek
        if let remote = remoteURL(item.streamURL) {
            usingEngine = false
            let player = AVPlayer(url: remote)
            self.player = player
            player.play()
            playing = true
            if seek > 0 {
                player.seek(to: CMTime(seconds: seek, preferredTimescale: 600))
            }
            observeEnd(player)
            Task { await loadDuration(player) }
            return
        }
        do {
            try startEngine(item: item, seek: seek, bands: bands, bass: bass)
        } catch {
            hud("Không mở được máy âm, chuyển sang phát thường")
            fallbackPlayer(seek: seek)
        }
    }

    func toggle() {
        if playing { pause() } else { resume() }
    }

    func pause() {
        if usingEngine {
            node?.pause()
            pausedAt = seconds
        } else {
            player?.pause()
        }
        playing = false
    }

    func resume() {
        if usingEngine {
            node?.play()
            startedAt = Date().addingTimeInterval(-pausedAt)
        } else {
            player?.play()
        }
        playing = true
        applyVolume(animated: false)
    }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player?.pause()
        player = nil
        node?.stop()
        engine?.stop()
        engine = nil
        node = nil
        eq = nil
        file = nil
        playing = false
        shouldAdvance = false
        usingEngine = false
    }

    func seek(to value: Double) {
        let target = min(max(0, value), max(duration, 0.1))
        seconds = target
        if usingEngine {
            scheduleEngine(from: target, play: playing)
        } else {
            player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        }
    }

    func apply(bands: [Float], bass: Float) {
        guard let eq else { return }
        for (index, band) in eq.bands.enumerated() where bands.indices.contains(index) {
            band.gain = bands[index]
        }
        eq.globalGain = min(12, max(-12, bass))
    }

    func setDuck(_ value: Float) {
        duck = value
        applyVolume(animated: true)
    }

    func setSleepGain(_ value: Float) {
        sleepGain = value
        applyVolume(animated: false)
    }

    func tick(date: Date, crossfade: Double, duck: Float, sleep: SleepTimerState) {
        self.duck = duck
        if usingEngine {
            if playing, let startedAt {
                seconds = date.timeIntervalSince(startedAt)
            }
            if seconds >= duration {
                shouldAdvance = true
                playing = false
            }
        } else if let item = player?.currentItem {
            let current = item.currentTime().seconds
            if current.isFinite { seconds = current }
            let length = item.duration.seconds
            if length.isFinite, length > 0 { duration = length }
            let remaining = duration - seconds
            if playing, remaining < crossfade, remaining > 0 {
                let ratio = Float(remaining / crossfade)
                userVolume = max(0.05, ratio)
                fading = true
                applyVolume(animated: false)
            } else if fading, remaining >= crossfade {
                userVolume = 1
                fading = false
                applyVolume(animated: false)
            }
        }
        _ = sleep
    }

    private func remoteURL(_ string: String?) -> URL? {
        guard let string, let url = MediaLocator.url(for: string) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private func startEngine(item: CatalogItem, seek: Double, bands: [Float], bass: Float) throws {
        let url = try previewURL(for: item)
        let file = try AVAudioFile(forReading: url)
        let audioEngine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let unit = AVAudioUnitEQ(numberOfBands: AudioEQBands.frequencies.count)
        for (index, frequency) in AudioEQBands.frequencies.enumerated() where unit.bands.indices.contains(index) {
            let band = unit.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1
            band.bypass = false
            band.gain = bands.indices.contains(index) ? bands[index] : 0
        }
        unit.globalGain = bass
        audioEngine.attach(playerNode)
        audioEngine.attach(unit)
        audioEngine.connect(playerNode, to: unit, format: file.processingFormat)
        audioEngine.connect(unit, to: audioEngine.mainMixerNode, format: file.processingFormat)
        try audioEngine.start()
        self.file = file
        self.engine = audioEngine
        self.node = playerNode
        self.eq = unit
        self.usingEngine = true
        sampleRate = file.processingFormat.sampleRate
        let frames = Double(file.length)
        duration = sampleRate > 0 ? frames / sampleRate : 8
        scheduleEngine(from: seek, play: true)
        playing = true
    }

    private func scheduleEngine(from seek: Double, play: Bool) {
        guard let node, let file else { return }
        node.stop()
        let startFrame = AVAudioFramePosition(max(0, seek) * sampleRate)
        let remain = max(1, file.length - startFrame)
        node.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remain), at: nil) { [weak self] in
            Task { @MainActor in
                self?.shouldAdvance = true
                self?.playing = false
            }
        }
        if play {
            node.play()
            startedAt = Date().addingTimeInterval(-seek)
            pausedAt = seek
            seconds = seek
        }
    }

    private func previewURL(for item: CatalogItem) throws -> URL {
        if let string = item.streamURL, let url = MediaLocator.url(for: string), url.isFileURL {
            return url
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = caches.appendingPathComponent("meine-tone-\(item.id).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try ToneSynth.writePreviewWAV(to: url)
        }
        return url
    }

    private func fallbackPlayer(seek: Double) {
        usingEngine = false
        let player = AVPlayer()
        self.player = player
        player.play()
        playing = true
        duration = 30
        seconds = seek
        observeEnd(player)
    }

    private func observeEnd(_ player: AVPlayer) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.shouldAdvance = true
                self?.playing = false
            }
        }
    }

    private func loadDuration(_ player: AVPlayer) async {
        guard let item = player.currentItem else { return }
        let time = try? await item.asset.load(.duration)
        let value = time?.seconds ?? 0
        if value.isFinite, value > 0 { duration = value }
    }

    private func applyVolume(animated: Bool) {
        let value = userVolume * duck * sleepGain
        if usingEngine {
            engine?.mainMixerNode.outputVolume = value
        } else if animated {
            player?.volume = value
        } else {
            player?.volume = value
        }
    }
}
