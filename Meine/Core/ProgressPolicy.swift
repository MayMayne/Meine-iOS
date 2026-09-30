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
