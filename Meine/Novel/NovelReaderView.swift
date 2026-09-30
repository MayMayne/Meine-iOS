import AVFoundation
import SwiftUI
import Translation

struct NovelReaderView: View {
    let sourceID: SourceID
    let item: CatalogItem

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var chapters: [TextChapter] = []
    @State private var chapterIndex = 0
    @State private var paragraphIndex = 0
    @State private var bodies: [String] = []
    @State private var fontScale: Double = 18
    @State private var lineSpacing: Double = 8
    @State private var pageMode = false
    @State private var showChapters = false
    @State private var showDisplay = false
    @State private var showTranslate = false
    @State private var engine: NovelEngine = .ai
    @State private var showAppleSheet = false
    @State private var appleText = ""
    @State private var translatedOpacity: Double = 1
    @State private var cacheKeys: Set<String> = []
    @State private var isTranslating = false
    @State private var glossaryTerm = ""
    @State private var glossaryMeaning = ""
    @State private var negativeDraft = ""
    @State private var speech = AVSpeechSynthesizer()
    @State private var anchorID: String?
    @State private var didRestore = false

    init(sourceID: SourceID, item: CatalogItem) {
        self.sourceID = sourceID
        self.item = item
    }

    var body: some View {
        ZStack(alignment: .top) {
            app.theme.backgroundColor.ignoresSafeArea()
            reader
            bar
        }
        .toolbar(.hidden, for: .navigationBar)
        .contextualDrawer(isPresented: $showChapters) { chapterDrawer }
        .contextualDrawer(isPresented: $showDisplay) { displayDrawer }
        .contextualDrawer(isPresented: $showTranslate) { translateDrawer }
        .translationPresentation(isPresented: $showAppleSheet, text: appleText)
        .onAppear(perform: restore)
        .onChange(of: chapterIndex) { _, _ in
            guard didRestore else { return }
            anchorID = NovelParagraphID.make(paragraphIndex)
            persist()
        }
        .onChange(of: paragraphIndex) { _, newValue in
            guard didRestore else { return }
            anchorID = NovelParagraphID.make(newValue)
            persist()
        }
        .onDisappear {
            speech.stopSpeaking(at: .immediate)
            persist()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("meine.audio.policy"))) { note in
            let raw = note.object as? String ?? note.userInfo?["policy"] as? String
            if raw == "videoExclusive" || raw == "music" {
                speech.stopSpeaking(at: .immediate)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 18) {
            NovelGlyph(systemName: "chevron.backward", label: "Quay lại") { dismiss() }
            Spacer(minLength: 8)
            NovelGlyph(systemName: "list.bullet", label: "Mục lục") { showChapters = true }
            NovelGlyph(systemName: "textformat", label: "Hiển thị") { showDisplay = true }
            NovelGlyph(systemName: "character.book.closed", label: "Dịch") { showTranslate = true }
            NovelGlyph(systemName: "speaker.wave.2", label: "Đọc thành tiếng") { speakCurrent() }
            NovelGlyph(
                systemName: app.inVault(sourceID: sourceID, item: item) ? "bookmark.fill" : "bookmark",
                label: "Đánh dấu"
            ) {
                app.toggleVault(sourceID: sourceID, item: item)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var reader: some View {
        if chapters.isEmpty {
            emptyState
        } else if currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && chapters.count <= 1 {
            emptyState
        } else if pageMode {
            pageReader
        } else {
            scrollReader
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Image(systemName: "book.closed")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(app.theme.inkColor.opacity(0.55))
                .accessibilityLabel("Chưa có nội dung")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrollReader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Color.clear.frame(height: 64)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.system(size: fontScale, weight: .regular, design: .serif))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(app.theme.inkColor)
                        .opacity(translatedOpacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(NovelParagraphID.make(index))
                        .onTapGesture { paragraphIndex = index }
                }
                Color.clear.frame(height: 48)
            }
            .padding(.horizontal, 24)
        }
        .scrollPosition(id: $anchorID, anchor: .top)
    }

    private var pageReader: some View {
        TabView(selection: $paragraphIndex) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                VStack(alignment: .leading, spacing: 16) {
                    Spacer(minLength: 72)
                    Text(paragraph)
                        .font(.system(size: fontScale, weight: .regular, design: .serif))
                        .lineSpacing(lineSpacing)
                        .foregroundStyle(app.theme.inkColor)
                        .opacity(translatedOpacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var chapterDrawer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        HapticTap.light()
                        chapterIndex = index
                        paragraphIndex = 0
                        showChapters = false
                        persist()
                    } label: {
                        HStack {
                            Text(chapter.title)
                                .font(.system(size: 15, weight: index == chapterIndex ? .semibold : .regular, design: .serif))
                                .foregroundStyle(index == chapterIndex ? app.theme.activeColor : app.theme.inkColor)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            index == chapterIndex ? app.theme.primaryColor.opacity(0.16) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chapter.title)
                }
            }
            .padding(16)
        }
    }

    private var displayDrawer: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cỡ chữ")
                    .font(.caption)
                    .foregroundStyle(app.theme.inkColor.opacity(0.7))
                Slider(value: $fontScale, in: 16...28, step: 1)
                    .tint(app.theme.primaryColor)
                    .accessibilityLabel("Cỡ chữ")
            }
            HStack {
                Text("Giãn dòng")
                    .foregroundStyle(app.theme.inkColor)
                Spacer()
                Stepper(value: $lineSpacing, in: 2...20, step: 1) {
                    Text("\(Int(lineSpacing))")
                        .foregroundStyle(app.theme.inkColor)
                }
                .accessibilityLabel("Giãn dòng")
            }
            Toggle(isOn: $pageMode) {
                Text(pageMode ? "Trang" : "Cuộn")
                    .foregroundStyle(app.theme.inkColor)
            }
            .tint(app.theme.primaryColor)
            .accessibilityLabel("Chế độ cuộn hoặc trang")
            Text("Nền dùng màu chủ đề toàn cục")
                .font(.caption)
                .foregroundStyle(app.theme.inkColor.opacity(0.65))
        }
        .padding(22)
    }

    private var translateDrawer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Máy dịch", selection: $engine) {
                    Text("Apple").tag(NovelEngine.apple)
                    Text("AI").tag(NovelEngine.ai)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Máy dịch")

                HStack(spacing: 12) {
                    Button {
                        HapticTap.light()
                        translateCurrent()
                    } label: {
                        Image(systemName: "character.book.closed")
                            .accessibilityLabel("Dịch đoạn")
                            .frame(width: 48, height: 48)
                            .background(app.theme.primaryColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTranslating)

                    Button {
                        HapticTap.light()
                        continueRemaining()
                    } label: {
                        Image(systemName: "arrow.forward.circle")
                            .accessibilityLabel("Dịch tiếp")
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTranslating)

                    Button {
                        HapticTap.light()
                        translateAll()
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                            .accessibilityLabel("Dịch tất cả")
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isTranslating)
                }

                glossaryEditor
                genreRow
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ràng buộc loại trừ")
                        .font(.caption)
                        .foregroundStyle(app.theme.inkColor.opacity(0.7))
                    TextField("Không dùng…", text: $negativeDraft, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveContext)
                }
            }
            .padding(22)
        }
        .onAppear {
            let ctx = app.context(for: item.id)
            negativeDraft = ctx.negative.joined(separator: ", ")
        }
    }

    private var glossaryEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thuật ngữ")
                .font(.caption)
                .foregroundStyle(app.theme.inkColor.opacity(0.7))
            TextField("Gốc", text: $glossaryTerm)
                .textFieldStyle(.roundedBorder)
            TextField("Nghĩa", text: $glossaryMeaning)
                .textFieldStyle(.roundedBorder)
            Button {
                HapticTap.light()
                addGlossary()
            } label: {
                Image(systemName: "plus")
                    .accessibilityLabel("Thêm thuật ngữ")
                    .frame(width: 44, height: 44)
                    .background(app.theme.primaryColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            let glossary = app.context(for: item.id).glossary
            ForEach(glossary.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key)
                    Spacer()
                    Text(glossary[key] ?? "")
                        .foregroundStyle(app.theme.inkColor.opacity(0.7))
                }
                .font(.footnote)
            }
        }
    }

    private var genreRow: some View {
        HStack(spacing: 10) {
            ForEach(NovelGenrePresets.genrePresets, id: \.self) { name in
                Button {
                    HapticTap.light()
                    var ctx = app.context(for: item.id)
                    ctx.genrePrompt = name
                    app.updateContext(ctx)
                } label: {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(app.theme.inkColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name)
            }
        }
    }

    private var paragraphs: [String] {
        let body = currentBody
        let parts = body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [body] : parts
    }

    private var currentBody: String {
        guard chapters.indices.contains(chapterIndex) else { return "" }
        if bodies.indices.contains(chapterIndex) { return bodies[chapterIndex] }
        return chapters[chapterIndex].body
    }

    private func restore() {
        let loaded: [TextChapter]
        if !item.chapters.isEmpty {
            loaded = item.chapters
        } else if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            loaded = HeuristicChapterSplitter.split(item.subtitle)
        } else {
            loaded = []
        }
        chapters = loaded
        bodies = loaded.map(\.body)
        let ref = app.mediaRef(sourceID: sourceID, item: item)
        if let snap = app.progress(for: ref), case .novel(let chapterID, let savedParagraph, _) = snap.payload {
            if let found = loaded.firstIndex(where: { $0.id == chapterID }) {
                chapterIndex = found
                paragraphIndex = savedParagraph
            }
        }
        let clamped = paragraphs.indices.contains(paragraphIndex) ? paragraphIndex : 0
        paragraphIndex = clamped
        anchorID = NovelParagraphID.make(clamped)
        fontScale = 18
        didRestore = true
    }

    private func persist() {
        guard chapters.indices.contains(chapterIndex) else { return }
        let count = max(chapters.count, 1)
        let percent = Double(chapterIndex) / Double(count)
        let payload = ProgressPayload.novel(
            chapterID: chapters[chapterIndex].id,
            paragraphIndex: paragraphIndex,
            workPercent: percent
        )
        let ref = app.mediaRef(sourceID: sourceID, item: item)
        app.saveProgress(ProgressSnapshot(ref: ref, updatedAt: Date(), payload: payload))
    }

    private func translateCurrent() {
        guard paragraphs.indices.contains(paragraphIndex) else { return }
        let original = paragraphs[paragraphIndex]
        if engine == .apple {
            appleText = original
            showAppleSheet = true
            return
        }
        let chapterID = chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].id : item.id
        if TranslationContinue.shouldSkip(storyID: item.id, chapterID: chapterID, original: original, cacheKeys: cacheKeys) {
            return
        }
        Task { await runAI(segments: [original], chapterID: chapterID, replaceParagraph: true) }
    }

    private func continueRemaining() {
        guard chapters.indices.contains(chapterIndex) else { return }
        let pending = Array(chapters[chapterIndex...])
        Task { await translateChapters(pending, skipCached: true) }
    }

    private func translateAll() {
        Task { await translateChapters(chapters, skipCached: false) }
    }

    private func translateChapters(_ list: [TextChapter], skipCached: Bool) async {
        for chapter in list {
            let source = chapterBody(chapter)
            if skipCached && TranslationContinue.shouldSkip(storyID: item.id, chapterID: chapter.id, original: source, cacheKeys: cacheKeys) {
                continue
            }
            let segments = NovelParagraphs.split(source)
            let payload = segments.isEmpty ? [source] : segments
            let ok = await runAI(segments: payload, chapterID: chapter.id, replaceParagraph: false)
            if !ok { return }
        }
    }

    private func chapterBody(_ chapter: TextChapter) -> String {
        if let index = chapters.firstIndex(where: { $0.id == chapter.id }), bodies.indices.contains(index) {
            return bodies[index]
        }
        return chapter.body
    }

    @discardableResult
    private func runAI(segments: [String], chapterID: String, replaceParagraph: Bool) async -> Bool {
        isTranslating = true
        defer { isTranslating = false }
        let ctx = app.context(for: item.id)
        do {
            let translated = try await AIGatewayClient.shared.translate(segments: segments, context: ctx)
            let joined = translated.joined(separator: "\n\n")
            withAnimation(.easeInOut(duration: 0.2)) {
                translatedOpacity = 0.35
            }
            if let index = chapters.firstIndex(where: { $0.id == chapterID }), bodies.indices.contains(index) {
                if replaceParagraph {
                    var lines = NovelParagraphs.split(bodies[index])
                    if lines.isEmpty { lines = [bodies[index]] }
                    let slot = min(max(paragraphIndex, 0), max(lines.count - 1, 0))
                    if lines.indices.contains(slot), let first = translated.first {
                        lines[slot] = first
                        bodies[index] = lines.joined(separator: "\n\n")
                    }
                } else if !joined.isEmpty {
                    bodies[index] = joined
                }
            }
            let keySource = segments.joined(separator: "\n")
            cacheKeys.insert(TranslationContinue.cacheKey(chapterID: chapterID, original: keySource))
            withAnimation(.easeInOut(duration: 0.2)) {
                translatedOpacity = 1
            }
            persist()
            return true
        } catch let error as AIGatewayError {
            app.showHUD(error.hudText)
            return false
        } catch {
            app.showHUD("Không dịch được")
            return false
        }
    }

    private func addGlossary() {
        let term = glossaryTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = glossaryMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !meaning.isEmpty else { return }
        var ctx = app.context(for: item.id)
        ctx.glossary[term] = meaning
        app.updateContext(ctx)
        glossaryTerm = ""
        glossaryMeaning = ""
    }

    private func saveContext() {
        var ctx = app.context(for: item.id)
        ctx.negative = negativeDraft
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        app.updateContext(ctx)
    }

    private func speakCurrent() {
        guard paragraphs.indices.contains(paragraphIndex) else { return }
        let raw = paragraphs[paragraphIndex]
        let spoken = PhoneticMiddleware.rewrite(raw)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: spoken)
        if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("vi") }) {
            utterance.voice = voice
        }
        utterance.rate = NovelSpeechRate.rate(for: raw)
        speech.speak(utterance)
    }
}

private enum NovelEngine: String, Hashable {
    case apple
    case ai
}

private enum NovelParagraphs {
    static func split(_ body: String) -> [String] {
        body
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private enum NovelParagraphID {
    static func make(_ index: Int) -> String { "p-\(index)" }
}

private enum NovelSpeechRate {
    static func rate(for line: String) -> Float {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = [("«", "»"), ("\"", "\""), ("“", "”"), ("「", "」")]
        let dialogue = pairs.contains { trimmed.hasPrefix($0.0) && trimmed.hasSuffix($0.1) && trimmed.count > 1 }
        return dialogue ? AVSpeechUtteranceDefaultSpeechRate * 0.86 : AVSpeechUtteranceDefaultSpeechRate
    }
}

private struct NovelGlyph: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticTap.light()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 28, height: 28)
                .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
    }
}
