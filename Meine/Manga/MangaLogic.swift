import CoreGraphics
import Foundation

enum ReadingMode: String, Codable, CaseIterable {
    case webtoon
    case singleVertical
    case singleHorizontalLTR
    case singleHorizontalRTL
    case dualPage

    var isHorizontal: Bool {
        switch self {
        case .singleHorizontalLTR, .singleHorizontalRTL, .dualPage:
            return true
        case .webtoon, .singleVertical:
            return false
        }
    }

    var reversesDirection: Bool {
        self == .singleHorizontalRTL
    }

    var accessibilityName: String {
        switch self {
        case .webtoon: return "Webtoon"
        case .singleVertical: return "Một trang dọc"
        case .singleHorizontalLTR: return "Lật ngang trái sang phải"
        case .singleHorizontalRTL: return "Lật ngang phải sang trái"
        case .dualPage: return "Hai trang"
        }
    }
}

enum TapZonePreset: String, Codable, CaseIterable {
    case leftRight
    case outerEdges
    case lShape
    case kindle

    var accessibilityName: String {
        switch self {
        case .leftRight: return "Trái phải"
        case .outerEdges: return "Hai mép"
        case .lShape: return "Hình chữ L"
        case .kindle: return "Kindle"
        }
    }
}

enum TapZoneAction {
    case previous
    case next
    case menu
}

enum TapZoneMap {
    static func action(
        preset: TapZonePreset,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> TapZoneAction {
        guard width > 0, height > 0 else { return .menu }
        let clampedX = min(max(x, 0), width)
        let clampedY = min(max(y, 0), height)
        switch preset {
        case .kindle:
            if clampedX > width * 0.8 { return .next }
            if clampedX < width * 0.2 { return .previous }
            return .menu
        case .leftRight:
            if clampedX < width * 0.35 { return .previous }
            if clampedX > width * 0.65 { return .next }
            return .menu
        case .outerEdges:
            if clampedX < width * 0.2 { return .previous }
            if clampedX > width * 0.8 { return .next }
            return .menu
        case .lShape:
            if clampedY > height * 0.75 || clampedX > width * 0.7 { return .next }
            if clampedX < width * 0.3 { return .previous }
            return .menu
        }
    }
}

enum MangaAutoCrop {
    static func contentRect(
        width: Int,
        height: Int,
        isWhite: (Int, Int) -> Bool
    ) -> CGRect {
        guard width > 0, height > 0 else { return .zero }
        let lastX = width - 1
        let lastY = height - 1

        var minX = 0
        var foundLeft = false
        while minX < width {
            var columnWhite = true
            var y = 0
            while y < height {
                if !isWhite(minX, y) {
                    columnWhite = false
                    break
                }
                y += 1
            }
            if !columnWhite {
                foundLeft = true
                break
            }
            minX += 1
        }
        if !foundLeft {
            return CGRect(x: 0, y: 0, width: width, height: height)
        }

        var maxX = lastX
        while maxX > minX {
            var columnWhite = true
            var y = 0
            while y < height {
                if !isWhite(maxX, y) {
                    columnWhite = false
                    break
                }
                y += 1
            }
            if !columnWhite { break }
            maxX -= 1
        }

        var minY = 0
        while minY < height {
            var rowWhite = true
            var x = minX
            while x <= maxX {
                if !isWhite(x, minY) {
                    rowWhite = false
                    break
                }
                x += 1
            }
            if !rowWhite { break }
            minY += 1
        }

        var maxY = lastY
        while maxY > minY {
            var rowWhite = true
            var x = minX
            while x <= maxX {
                if !isWhite(x, maxY) {
                    rowWhite = false
                    break
                }
                x += 1
            }
            if !rowWhite { break }
            maxY -= 1
        }

        let cropWidth = max(1, maxX - minX + 1)
        let cropHeight = max(1, maxY - minY + 1)
        return CGRect(x: minX, y: minY, width: cropWidth, height: cropHeight)
    }
}

enum MangaPageSynth {
    static var placeholderCount: Int { 8 }

    static func ink(for index: Int) -> (red: Double, green: Double, blue: Double) {
        let palette: [(Double, Double, Double)] = [
            (0.16, 0.18, 0.24),
            (0.22, 0.16, 0.20),
            (0.14, 0.20, 0.22),
            (0.24, 0.20, 0.14),
            (0.18, 0.16, 0.26),
            (0.12, 0.18, 0.16),
            (0.26, 0.14, 0.16),
            (0.18, 0.22, 0.16)
        ]
        let safe = palette.isEmpty ? (0.2, 0.2, 0.2) : palette[index % palette.count]
        return safe
    }
}

enum MangaOrientationLock: String, CaseIterable, Identifiable {
    case portrait
    case landscape
    case sensor

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .portrait: return "iphone"
        case .landscape: return "iphone.landscape"
        case .sensor: return "gyroscope"
        }
    }

    var accessibilityName: String {
        switch self {
        case .portrait: return "Khóa dọc"
        case .landscape: return "Khóa ngang"
        case .sensor: return "Theo cảm biến"
        }
    }
}

enum MangaAutoscrollStop: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }
    var minutes: Int { rawValue }
}
