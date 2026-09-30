import CoreGraphics
import Foundation

enum AspectFitCalculator {
    static func fittedRect(video: CGSize, container: CGSize) -> CGRect {
        guard video.width > 0, video.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / video.width, container.height / video.height)
        let size = CGSize(width: video.width * scale, height: video.height * scale)
        let origin = CGPoint(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}

struct SubtitleCue: Identifiable, Hashable {
    var id: Int
    var start: Double
    var end: Double
    var text: String
}

enum SubtitleParser {
    static func parse(_ raw: String) -> [SubtitleCue] {
        let normalized = raw
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        cues.reserveCapacity(blocks.count)
        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: "-->")
            guard parts.count >= 2 else { continue }
            guard let start = stamp(parts[0]), let end = stamp(parts[1]), end > start else { continue }
            let body = lines.dropFirst(timingIndex + 1)
                .filter { !$0.isEmpty && !$0.hasPrefix("NOTE") && !$0.hasPrefix("WEBVTT") }
                .joined(separator: "\n")
            let cleaned = stripTags(body).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            cues.append(SubtitleCue(id: cues.count, start: start, end: end, text: cleaned))
        }
        return cues
    }

    static func stamp(_ raw: String) -> Double? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let space = token.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            token = String(token[..<space])
        }
        guard !token.isEmpty else { return nil }
        var fraction = 0.0
        if let mark = token.firstIndex(where: { $0 == "," || $0 == "." }) {
            let digits = token[token.index(after: mark)...].prefix(3)
            if let value = Double("0.\(digits)") { fraction = value }
            token = String(token[..<mark])
        }
        let pieces = token.split(separator: ":").compactMap { Double($0) }
        let seconds: Double
        switch pieces.count {
        case 3: seconds = pieces[0] * 3600 + pieces[1] * 60 + pieces[2]
        case 2: seconds = pieces[0] * 60 + pieces[1]
        case 1: seconds = pieces[0]
        default: return nil
        }
        guard seconds.isFinite else { return nil }
        return seconds + fraction
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

enum IntroOutroHint {
    static func showIntroSkip(current: Double) -> Bool {
        current < 90 && current > 1
    }

    static func inCredits(current: Double, duration: Double) -> Bool {
        guard duration > 1, current >= 0, current < duration else { return false }
        let remaining = duration - current
        return remaining <= duration * 0.08 || remaining <= 40
    }
}
