import Foundation

enum ContrastInk: Equatable, Sendable {
    case dark
    case light
    var hex: String { self == .dark ? "1E1E1E" : "F5F5F7" }
}

enum Palette12 {
    static let allHex: [String] = [
        "#FF0000", "#FF8000", "#FFFF00", "#00FF00", "#0000FF", "#4B0082",
        "#800080", "#FFC0CB", "#8B4513", "#000000", "#FFFFFF", "#808080"
    ]
}

struct HSBColor: Equatable, Codable, Sendable {
    var baseHex: String
    var saturation: Double
    var brightness: Double

    func resolvedRGB() -> (r: Double, g: Double, b: Double) {
        let rgb = HexColor.parse(baseHex)
        let hsv = RGBHSB.rgbToHSV(r: rgb.r, g: rgb.g, b: rgb.b)
        let sat = min(max(saturation, 0), 1)
        let bri = min(max(brightness, 0), 1)
        return RGBHSB.hsvToRGB(h: hsv.h, s: sat, v: bri)
    }
}

enum HexColor {
    static func parse(_ raw: String) -> (r: Double, g: Double, b: Double) {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = Int(hex, radix: 16) else {
            return (1, 1, 1)
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return (r, g, b)
    }

    static func format(r: Double, g: Double, b: Double) -> String {
        let ri = Int((min(max(r, 0), 1) * 255).rounded())
        let gi = Int((min(max(g, 0), 1) * 255).rounded())
        let bi = Int((min(max(b, 0), 1) * 255).rounded())
        return String(format: "%02X%02X%02X", ri, gi, bi)
    }
}

enum RGBHSB {
    static func rgbToHSV(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV
        var h = 0.0
        if delta > 0.00001 {
            if maxV == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxV == g {
                h = ((b - r) / delta) + 2
            } else {
                h = ((r - g) / delta) + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxV == 0 ? 0 : delta / maxV
        return (h, s, maxV)
    }

    static func hsvToRGB(h: Double, s: Double, v: Double) -> (r: Double, g: Double, b: Double) {
        let sat = min(max(s, 0), 1)
        let val = min(max(v, 0), 1)
        let hue = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        let i = Int(hue * 6)
        let f = hue * 6 - Double(i)
        let p = val * (1 - sat)
        let q = val * (1 - f * sat)
        let t = val * (1 - (1 - f) * sat)
        switch i % 6 {
        case 0: return (val, t, p)
        case 1: return (q, val, p)
        case 2: return (p, val, t)
        case 3: return (p, q, val)
        case 4: return (t, p, val)
        default: return (val, p, q)
        }
    }
}

enum RelativeLuminance {
    public static func value(r: Double, g: Double, b: Double) -> Double {
        func f(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
    }

    public static func ink(luminance L: Double) -> ContrastInk {
        L > 0.5 ? .dark : .light
    }

    static func ink(for color: HSBColor) -> ContrastInk {
        let rgb = color.resolvedRGB()
        return ink(luminance: value(r: rgb.r, g: rgb.g, b: rgb.b))
    }
}
