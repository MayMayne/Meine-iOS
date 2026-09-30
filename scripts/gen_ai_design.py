#!/usr/bin/env python3
from pathlib import Path
ROOT = Path("/var/minis/workspace/Meine-iOS/Meine")

def put(rel, text):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n")
    print("wrote", rel, path.stat().st_size)

put("AI/AIGateway.swift", r'''
import Foundation

enum ProviderKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case openAICompatible, gemini, claude, elevenLabs, azureSpeech, localPiper, localKokoro, localXTTS
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .elevenLabs: return "ElevenLabs"
        case .azureSpeech: return "Azure Speech"
        case .localPiper: return "Piper"
        case .localKokoro: return "Kokoro"
        case .localXTTS: return "XTTS"
        }
    }
    var isLocal: Bool {
        switch self {
        case .localPiper, .localKokoro, .localXTTS: return true
        default: return false
        }
    }
}

enum AIGatewayError: Error, Equatable {
    case rateLimited(http: Int)
    case unauthorized
    case localhostUnreachable(url: URL)
    case transport(String)

    var hudText: String {
        switch self {
        case .rateLimited:
            return "Hết hạn ngạch API (HTTP 429). Đổi nhà cung cấp thủ công hoặc kiểm tra hạn mức."
        case .unauthorized:
            return "API key không hợp lệ (HTTP 401)."
        case .localhostUnreachable(let url):
            return "Không kết nối được Localhost \(url.absoluteString)."
        case .transport(let message):
            return message
        }
    }
}

struct AIGatewayConfig: Codable, Equatable, Sendable {
    var provider: ProviderKind
    var baseURL: String
    var model: String
    var apiKey: String

    static let empty = AIGatewayConfig(provider: .openAICompatible, baseURL: "https://api.openai.com", model: "gpt-4o-mini", apiKey: "")
}

enum AIRequestBuilder {
    static func translateBody(segments: [String], context: StoryAIContext, model: String) -> [String: JSONValue] {
        let glossary = context.glossary.map { "\($0.key) = \($0.value)" }.sorted().joined(separator: "; ")
        let negative = context.negative.joined(separator: ", ")
        let system = """
        Dịch sang tiếng Việt, giữ nguyên số đoạn. Thể loại: \(context.genrePrompt). \
        Ghi chú: \(context.customPrompt). Bảng thuật ngữ: \(glossary). Không dùng: \(negative).
        """
        let joined = segments.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n")
        return [
            "model": .string(model),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(system)]),
                .object(["role": .string("user"), "content": .string(joined)])
            ])
        ]
    }

    static func splitTranslated(_ text: String, expected: Int) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.count == 1, expected > 1 {
            lines = text.components(separatedBy: "\n\n")
        }
        if lines.count < expected {
            lines += Array(repeating: "", count: expected - lines.count)
        }
        if lines.count > expected {
            let head = Array(lines.prefix(expected - 1))
            let tail = lines.dropFirst(expected - 1).joined(separator: "\n")
            lines = head + [tail]
        }
        return lines.map { line in
            if let range = line.range(of: #"^\[\d+\]\s*"#, options: .regularExpression) {
                return String(line[range.upperBound...])
            }
            return line
        }
    }
}

actor AIGatewayClient {
    static let shared = AIGatewayClient()

    var config = AIGatewayConfig.empty
    var transport: (@Sendable (URLRequest) async throws -> (Int, Data)) = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (code, data)
    }
    private var hostsCalled: [String] = []

    func hostsTouched() -> [String] { hostsCalled }

    func resetTrace() { hostsCalled = [] }

    func translate(segments: [String], context: StoryAIContext) async throws -> [String] {
        if segments.isEmpty { return [] }
        let url = try endpoint()
        hostsCalled.append(url.host ?? url.absoluteString)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = AIRequestBuilder.translateBody(segments: segments, context: context, model: config.model)
        request.httpBody = try JSONEncoder().encode(body)
        let code: Int
        let data: Data
        do {
            (code, data) = try await transport(request)
        } catch {
            if config.provider.isLocal {
                throw AIGatewayError.localhostUnreachable(url: url)
            }
            throw AIGatewayError.transport("Không gửi được yêu cầu.")
        }
        if code == 429 { throw AIGatewayError.rateLimited(http: 429) }
        if code == 401 || code == 403 { throw AIGatewayError.unauthorized }
        if !(200..<300).contains(code) {
            throw AIGatewayError.transport("Máy chủ trả HTTP \(code).")
        }
        let text = extractText(data) ?? String(data: data, encoding: .utf8) ?? ""
        return AIRequestBuilder.splitTranslated(text, expected: segments.count)
    }

    private func endpoint() throws -> URL {
        let raw = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw), components.scheme != nil else {
            throw AIGatewayError.transport("URL AI không hợp lệ.")
        }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        switch config.provider {
        case .gemini:
            let model = config.model.isEmpty ? "gemini-2.0-flash" : config.model
            path += "/v1beta/models/\(model):generateContent"
        case .claude:
            path += "/v1/messages"
        default:
            if !path.hasSuffix("/v1/chat/completions") {
                path += "/v1/chat/completions"
            }
        }
        components.path = path
        guard let url = components.url else { throw AIGatewayError.transport("URL AI không hợp lệ.") }
        return url
    }

    private func extractText(_ data: Data) -> String? {
        guard let object = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        if let content = object["choices"]?[0]?["message"]?["content"]?.string { return content }
        if let content = object["content"]?[0]?["text"]?.string { return content }
        if let content = object["candidates"]?[0]?["content"]?["parts"]?[0]?["text"]?.string { return content }
        return nil
    }
}

private extension JSONValue {
    subscript(index: Int) -> JSONValue? {
        if case .array(let values) = self, values.indices.contains(index) { return values[index] }
        return nil
    }
}
''')

put("Design/DesignSystem.swift", r'''
import SwiftUI
import UIKit

@MainActor
@Observable
final class ThemeStore {
    var background: HSBColor
    var fontScale: Double

    init(background: HSBColor = HSBColor(baseHex: "#FFFFFF", saturation: 0, brightness: 1), fontScale: Double = 18) {
        self.background = background
        self.fontScale = fontScale
    }

    var ink: ContrastInk { RelativeLuminance.ink(for: background) }
    var cornerSmall: CGFloat { 18 }
    var cornerLarge: CGFloat { 28 }
    var corner: CGFloat { 22 }
    var defaultPrimaryHex: String { "8ECAE6" }
    var defaultActiveHex: String { "219EBC" }

    var backgroundColor: Color {
        let rgb = background.resolvedRGB()
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    var inkColor: Color {
        ink == .dark ? Color(red: 0x1E/255, green: 0x1E/255, blue: 0x1E/255) : Color(red: 0xF5/255, green: 0xF5/255, blue: 0xF7/255)
    }

    var primaryColor: Color {
        let rgb = HexColor.parse(defaultPrimaryHex)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    var activeColor: Color {
        let rgb = HexColor.parse(defaultActiveHex)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

enum HapticTap {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct IconButton: View {
    var systemName: String
    var tooltip: String
    var hierarchical: Bool = true
    var action: () -> Void
    @State private var showTip = false

    var body: some View {
        Button {
            HapticTap.light()
            action()
        } label: {
            Image(systemName: systemName)
                .symbolRenderingMode(hierarchical ? .hierarchical : .monochrome)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tooltip)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                showTip = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    showTip = false
                }
            }
        )
        .overlay(alignment: .top) {
            if showTip {
                Text(tooltip)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .offset(y: -36)
                    .transition(.opacity)
            }
        }
    }
}

struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(.ultraThinMaterial)
    }
}

extension View {
    func contextualDrawer<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        sheet(isPresented: isPresented) {
            DrawerChrome(content: content)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

private struct DrawerChrome<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        ScrollView {
            content()
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data, .item], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}

struct QRScannerSheet: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var onCode: ((String) -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            addChild(picker)
            picker.view.frame = view.bounds
            view.addSubview(picker.view)
            picker.didMove(toParent: self)
        }
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        dismiss(animated: true)
    }
}

enum MediaLocator {
    static func url(for string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        if let bundled = Bundle.main.url(forResource: trimmed, withExtension: nil) {
            return bundled
        }
        return URL(string: trimmed)
    }
}

enum ToneSynth {
    static func writePreviewWAV(to url: URL) throws {
        let sampleRate = 22_050
        let seconds = 8
        let count = sampleRate * seconds
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            let envelope = min(1, t * 8) * (t > 7.2 ? max(0, (8 - t) / 0.8) : 1)
            let tone = sin(2 * .pi * 220 * t) * 0.35 + sin(2 * .pi * 330 * t) * 0.18 + sin(2 * .pi * 440 * t) * 0.08
            samples[index] = Int16(max(-1, min(1, tone * envelope)) * 32000)
        }
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try writeWAV(samples: data, sampleRate: sampleRate, to: url)
    }

    private static func writeWAV(samples: Data, sampleRate: Int, to url: URL) throws {
        let byteRate = sampleRate * 2
        var header = Data()
        func ascii(_ value: String) { header.append(contentsOf: value.utf8) }
        func le32(_ value: UInt32) { var v = value.littleEndian; header.append(Data(bytes: &v, count: 4)) }
        func le16(_ value: UInt16) { var v = value.littleEndian; header.append(Data(bytes: &v, count: 2)) }
        ascii("RIFF")
        le32(UInt32(36 + samples.count))
        ascii("WAVE")
        ascii("fmt ")
        le32(16)
        le16(1)
        le16(1)
        le32(UInt32(sampleRate))
        le32(UInt32(byteRate))
        le16(2)
        le16(16)
        ascii("data")
        le32(UInt32(samples.count))
        header.append(samples)
        try header.write(to: url, options: .atomic)
    }
}
''')

print("ai+design done")
