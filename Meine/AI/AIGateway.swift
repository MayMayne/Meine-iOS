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
    func setConfig(_ value: AIGatewayConfig) { config = value }
    func setTransport(_ handler: @escaping @Sendable (URLRequest) async throws -> (Int, Data)) {
        transport = handler
    }
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
