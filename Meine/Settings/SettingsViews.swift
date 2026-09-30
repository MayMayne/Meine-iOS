import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsRootView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Meine")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(app.theme.inkColor)
                    .padding(.top, 24)
                settingsLink("antenna.radiowaves.left.and.right", "Nguồn") { SourceManagerView() }
                settingsLink("sparkles", "AI Gateway") { AIGatewaySettingsView() }
                settingsLink("internaldrive", "Bộ nhớ đệm") { CacheQuotaView() }
                settingsLink("archivebox", "Sao lưu") { BackupRestoreView() }
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(app.theme.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
        }
    }

    private func settingsLink<Dest: View>(_ symbol: String, _ tip: String, @ViewBuilder dest: () -> Dest) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(app.theme.primaryColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tip)
    }
}

struct SourceManagerView: View {
    @Environment(AppModel.self) private var app
    @State private var showImport = false
    var body: some View {
        List {
            ForEach(app.sources, id: \.id) { source in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(source.name).font(.headline)
                        Spacer()
                        if source.passwordProtected {
                            Image(systemName: app.unlocked.contains(source.id.rawValue) ? "lock.open" : "lock")
                                .accessibilityLabel(app.unlocked.contains(source.id.rawValue) ? "Đã mở khóa" : "Đang khóa")
                        }
                    }
                    Text(source.id.rawValue).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Đặt mật khẩu") { passwordPrompt(source.id) }
                        if source.passwordProtected {
                            Button(app.unlocked.contains(source.id.rawValue) ? "Khóa" : "Mở") {
                                if app.unlocked.contains(source.id.rawValue) {
                                    app.lock(source.id)
                                } else {
                                    passwordPrompt(source.id, unlock: true)
                                }
                            }
                        }
                        Button("Xóa", role: .destructive) { app.removeSource(source.id) }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 6)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IconButton(systemName: "plus", tooltip: "Nạp nguồn") { showImport = true }
            }
        }
        .sheet(isPresented: $showImport) { SourceImportSheet() }
        .navigationTitle("Nguồn")
    }

    private func passwordPrompt(_ id: SourceID, unlock: Bool = false) {
        // UIAlert via a tiny presenter keeps the list free of extra text fields in the chrome.
        let alert = UIAlertController(title: unlock ? "Mở nguồn" : "Mật khẩu nguồn", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { _ in
            let text = alert.textFields?.first?.text ?? ""
            if unlock {
                let ok = app.unlock(sourceID: id, password: text)
                if !ok { app.showHUD("Sai mật khẩu") }
            } else if !text.isEmpty {
                app.setPassword(text, sourceID: id)
                app.showHUD("Đã khóa nguồn")
            }
        })
        present(alert)
    }

    private func present(_ alert: UIAlertController) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController else { return }
        root.present(alert, animated: true)
    }
}

struct SourceImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var jsonText = ""
    @State private var showFile = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("URL") {
                    TextField("https://…/source.json", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Tải") { Task { await loadURL() } }
                        .disabled(busy || urlText.isEmpty)
                }
                Section("JSON") {
                    TextEditor(text: $jsonText).frame(minHeight: 140)
                    Button("Nạp JSON") { importJSON() }
                }
                Section {
                    Button("Chọn tệp") { showFile = true }
                    Button("Dán clipboard") { paste() }
                }
            }
            .navigationTitle("Nạp nguồn")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .sheet(isPresented: $showFile) {
                DocumentPicker { url in
                    if let manifest = try? SourceImporter.importFile(url) {
                        app.importManifest(manifest)
                        dismiss()
                    } else {
                        app.showHUD("Tệp không phải nguồn Meine")
                    }
                }
            }
        }
    }

    private func importJSON() {
        do {
            let manifest = try SourceImporter.importRawJSON(jsonText)
            app.importManifest(manifest)
            dismiss()
        } catch {
            app.showHUD("JSON nguồn không hợp lệ")
        }
    }

    private func paste() {
        guard let text = UIPasteboard.general.string else { return }
        jsonText = text
        if let manifest = ClipboardSourceDetector.detect(text) ?? (try? SourceImporter.importRawJSON(text)) {
            app.importManifest(manifest)
            dismiss()
        }
    }

    private func loadURL() async {
        guard let url = URL(string: urlText) else {
            app.showHUD("URL không hợp lệ")
            return
        }
        busy = true
        defer { busy = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code), let text = String(data: data, encoding: .utf8) else {
                app.showHUD("Không tải được nguồn")
                return
            }
            let manifest = try SourceImporter.importRawJSON(text)
            app.importManifest(manifest)
            dismiss()
        } catch {
            app.showHUD("Không tải được nguồn")
        }
    }
}

struct AIGatewaySettingsView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var app = app
        Form {
            Picker("Nhà cung cấp", selection: $app.aiConfig.provider) {
                ForEach(ProviderKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            TextField("Base URL", text: $app.aiConfig.baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Model", text: $app.aiConfig.model)
                .textInputAutocapitalization(.never)
            SecureField("API key", text: $app.aiConfig.apiKey)
            Text("Meine không tự đổi nhà cung cấp khi lỗi. 429 và 401 dừng ngay.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Lưu vào Keychain") {
                app.applyAIConfig()
                app.showHUD("Đã lưu AI Gateway")
            }
        }
        .navigationTitle("AI Gateway")
    }
}

struct CacheQuotaView: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        @Bindable var app = app
        Form {
            Stepper(value: $app.cacheQuotaGB, in: 0.5...32, step: 0.5) {
                Text("Hạn mức \(app.cacheQuotaGB, specifier: "%.1f") GB")
            }
            .onChange(of: app.cacheQuotaGB) { _, _ in app.persistSoon() }
            Toggle("Cho phép dịch hàng loạt chạy ngầm", isOn: $app.allowBackgroundTranslate)
                .onChange(of: app.allowBackgroundTranslate) { _, on in
                    app.persistSoon()
                    app.showHUD(on ? "Đã bật dịch ngầm" : "Đã tắt dịch ngầm")
                }
            ThemeEditor()
        }
        .navigationTitle("Bộ nhớ đệm")
    }
}

struct ThemeEditor: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        Section("Nền") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(Palette12.allHex, id: \.self) { hex in
                    Button {
                        app.theme.background.baseHex = hex
                        app.persistSoon()
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if app.theme.background.baseHex == hex {
                                    Image(systemName: "checkmark").font(.caption2.bold())
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
            }
            Slider(value: saturation, in: 0...1) { Text("Bão hòa") }
            Slider(value: brightness, in: 0...1) { Text("Sáng") }
        }
    }

    private var saturation: Binding<Double> {
        Binding(get: { app.theme.background.saturation }, set: {
            app.theme.background.saturation = $0
            app.persistSoon()
        })
    }
    private var brightness: Binding<Double> {
        Binding(get: { app.theme.background.brightness }, set: {
            app.theme.background.brightness = $0
            app.persistSoon()
        })
    }
}

extension Color {
    init(hex: String) {
        let rgb = HexColor.parse(hex)
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

struct BackupRestoreView: View {
    @Environment(AppModel.self) private var app
    @State private var pin = ""
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var showImport = false
    @State private var incoming: Data?
    var body: some View {
        Form {
            SecureField("PIN sao lưu", text: $pin)
            Toggle("Kèm API key", isOn: Bindable(app).includeSecretsInBackup)
            Button("Xuất .meinebackup") { exportNow() }
            Button("Nhập tệp") { showImport = true }
        }
        .navigationTitle("Sao lưu")
        .sheet(isPresented: $showShare) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker { url in
                incoming = try? Data(contentsOf: url)
                askMerge()
            }
        }
    }

    private func exportNow() {
        guard pin.count >= 4 else {
            app.showHUD("PIN tối thiểu 4 ký tự")
            return
        }
        do {
            let data = try app.makeBackup(pin: pin)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Meine-\(Int(Date().timeIntervalSince1970)).meinebackup")
            try data.write(to: url)
            exportURL = url
            showShare = true
        } catch {
            app.showHUD("Không xuất được bản sao")
        }
    }

    private func askMerge() {
        guard let incoming else { return }
        let alert = UIAlertController(title: "Khôi phục", message: "Gộp hay thay thư viện?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Gộp", style: .default) { _ in restore(incoming, merge: true) })
        alert.addAction(UIAlertAction(title: "Thay", style: .destructive) { _ in restore(incoming, merge: false) })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let root = scene.keyWindow?.rootViewController ?? scene.windows.first?.rootViewController {
            root.present(alert, animated: true)
        }
    }

    private func restore(_ data: Data, merge: Bool) {
        do {
            try app.restoreBackup(data, pin: pin, merge: merge)
            app.showHUD("Đã khôi phục")
        } catch {
            app.showHUD("PIN sai hoặc tệp hỏng")
        }
    }
}
