import AVFoundation
import UIKit
import Foundation

final class ShortsPlayerPool {
    static let shared = ShortsPlayerPool()

    private var player: AVPlayer
    var count: Int { 1 }

    func currentTime() -> Double {
        let value = player.currentTime().seconds
        return value.isFinite ? max(0, value) : 0
    }

    func knownDuration() -> Double {
        let value = player.currentItem?.duration.seconds ?? 0
        return value.isFinite && value > 0 ? value : 0
    }

    func isPlaying() -> Bool {
        player.timeControlStatus == .playing
    }

    func bind(_ canvas: ShortsPlayerCanvas) {
        canvas.playerLayer.player = player
        canvas.playerLayer.videoGravity = .resizeAspectFill
        canvas.backgroundColor = .black
    }

    init() {
        player = AVPlayer()
        player.actionAtItemEnd = .pause
    }

    func attach(url: URL?) {
        guard let url else {
            player.replaceCurrentItem(with: nil)
            return
        }
        if let asset = player.currentItem?.asset as? AVURLAsset, asset.url == url {
            return
        }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(_ seconds: Double) {
        let safe = seconds.isFinite ? max(0, seconds) : 0
        player.seek(to: CMTime(seconds: safe, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    var seconds: Double { currentTime() }
}

enum ShortsPreloader {
    static let byteBudget = 2_000_000

    static func cacheKey(_ id: String) -> String {
        "shorts:\(id)"
    }

    static func preload(url: URL, key: String) async {
        guard !url.isFileURL else { return }
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(byteBudget - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let clipped = data.prefix(byteBudget)
            guard !clipped.isEmpty else { return }
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let folder = base.appendingPathComponent("MeineShorts", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = key.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
            try clipped.write(to: folder.appendingPathComponent(safe), options: .atomic)
        } catch {
            return
        }
    }
}

final class ShortsPlayerCanvas: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else { return AVPlayerLayer() }
        return layer
    }
}
