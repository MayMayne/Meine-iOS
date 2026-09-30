import Foundation

struct LyricLine: Identifiable, Hashable {
    var id: Int
    var time: Double
    var text: String
    var words: [LyricWord]
}

struct LyricWord: Hashable {
    var time: Double
    var text: String
}

enum LyricParser {
    static func parse(_ raw: String) -> [LyricLine] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains("<tt") || trimmed.contains("<p ") || trimmed.contains("<p>") {
            let ttml = parseTTML(trimmed)
            if !ttml.isEmpty { return ttml }
        }
        if trimmed.contains("-->") {
            let srt = parseSRT(trimmed)
            if !srt.isEmpty { return srt }
        }
        return parseLRC(trimmed)
    }

    private static func parseLRC(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = regex?.matches(in: line, range: range) ?? []
            guard let last = matches.last else { continue }
            let textStart = last.range.location + last.range.length
            let text = ns.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for match in matches {
                let minutes = double(ns.substring(with: match.range(at: 1)))
                let seconds = double(ns.substring(with: match.range(at: 2)))
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let frac = ns.substring(with: match.range(at: 3))
                    let scale = pow(10.0, Double(frac.count))
                    fraction = double(frac) / scale
                }
                let time = minutes * 60 + seconds + fraction
                lines.append(LyricLine(id: lines.count, time: time, text: text, words: wordTimings(in: text, lineTime: time)))
            }
        }
        return lines.sorted { $0.time < $1.time }.enumerated().map { index, line in
            LyricLine(id: index, time: line.time, text: line.text, words: line.words)
        }
    }

    private static func parseSRT(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let blocks = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let rows = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let arrow = rows.firstIndex(where: { $0.contains("-->") }) else { continue }
            let stamp = rows[arrow]
            let parts = stamp.components(separatedBy: "-->")
            guard let start = parts.first else { continue }
            let time = srtTime(start)
            let text = rows.dropFirst(arrow + 1).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(LyricLine(id: lines.count, time: time, text: stripTags(text), words: []))
        }
        return lines
    }

    private static func parseTTML(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let pattern = #"<p\b[^>]*\bbegin\s*=\s*["']([^"']+)["'][^>]*>(.*?)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let begin = ns.substring(with: match.range(at: 1))
            let body = stripTags(ns.substring(with: match.range(at: 2)))
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let time = clockTime(begin)
            var words: [LyricWord] = []
            let wordPattern = #"<span\b[^>]*\bbegin\s*=\s*["']([^"']+)["'][^>]*>(.*?)</span>"#
            if let wordRegex = try? NSRegularExpression(pattern: wordPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) {
                let bodyNS = ns.substring(with: match.range(at: 2)) as NSString
                let wordMatches = wordRegex.matches(in: bodyNS as String, range: NSRange(location: 0, length: bodyNS.length))
                for wordMatch in wordMatches {
                    let wordBegin = bodyNS.substring(with: wordMatch.range(at: 1))
                    let wordText = stripTags(bodyNS.substring(with: wordMatch.range(at: 2))).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !wordText.isEmpty {
                        words.append(LyricWord(time: clockTime(wordBegin), text: wordText))
                    }
                }
            }
            lines.append(LyricLine(id: lines.count, time: time, text: text, words: words))
        }
        return lines.sorted { $0.time < $1.time }.enumerated().map { index, line in
            LyricLine(id: index, time: line.time, text: line.text, words: line.words)
        }
    }

    private static func wordTimings(in text: String, lineTime: Double) -> [LyricWord] {
        let parts = text.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return [] }
        return parts.enumerated().map { index, word in
            LyricWord(time: lineTime + Double(index) * 0.35, text: word)
        }
    }

    private static func srtTime(_ raw: String) -> Double {
        let cleaned = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return clockTime(cleaned)
    }

    private static func clockTime(_ raw: String) -> Double {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix("s"), let value = Double(cleaned.dropLast()) {
            return value
        }
        let pieces = cleaned.split(separator: ":").map(String.init)
        if pieces.count == 3 {
            return double(pieces[0]) * 3600 + double(pieces[1]) * 60 + double(pieces[2])
        }
        if pieces.count == 2 {
            return double(pieces[0]) * 60 + double(pieces[1])
        }
        return double(cleaned)
    }

    private static func double(_ raw: String) -> Double {
        Double(raw.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

enum AudioEQBands {
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
}

enum SleepFade {
    static func gain(now: Date, fadeStarted: Date?, window: TimeInterval = 60) -> Float {
        guard let fadeStarted else { return 1 }
        let elapsed = now.timeIntervalSince(fadeStarted)
        if elapsed <= 0 { return 1 }
        if elapsed >= window { return 0 }
        return Float(1 - elapsed / window)
    }
}
