#if SENDMOI_SIRI_PROBE
import AppIntents
import SwiftUI
import WebKit

struct PreviewWithSendMoi: AppIntent {
    static var title: LocalizedStringResource = "Preview with SendMoi"
    static var description = IntentDescription("Preview one article as a SendMoi email. This development build cannot send or queue mail.")
    static var openAppWhenRun: Bool { false }
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Article URL", description: "A complete http or https article URL.")
    var url: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Preview \(\.$url) with SendMoi")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let preview = try await GmailDeliveryService().renderProbe(url: url)
        return .result(value: preview.text)
    }
}

struct SendMoiProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PreviewWithSendMoi(), phrases: [
            "Preview with \(.applicationName)",
            "Preview this with \(.applicationName)"
        ], shortTitle: "Preview Article", systemImageName: "doc.text.magnifyingglass")
    }
}

struct SiriProbeView: View {
    @State private var input = ""
    @State private var preview: ProbePreview?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preview an article").font(.largeTitle.bold())
                Text("A non-sending prototype for Siri and Shortcuts. Paste an article URL to see the email preview.")
                    .foregroundStyle(.secondary)
                TextField("https://…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Article URL")
                Button(isLoading ? "Preparing preview…" : "Preview") {
                    Task { await loadPreview() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let error { Text(error).foregroundStyle(.red) }
                if let preview {
                    if let warning = preview.contentWarning { Text(warning).foregroundStyle(.secondary) }
                    Text("\(preview.elapsedSeconds, specifier: "%.1f") seconds · \(preview.inlineImageCount) images · Model \(preview.modelAvailable ? "available" : "unavailable")")
                        .font(.caption).foregroundStyle(.secondary)
                    ProbeHTMLView(html: preview.html)
                } else {
                    Spacer()
                    Text("In Shortcuts, add “Preview with SendMoi” and provide a URL. Then test whether Siri can supply the current Safari article.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("SendMoi Probe")
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 650)
        #endif
    }

    @MainActor private func loadPreview() async {
        isLoading = true
        error = nil
        preview = nil
        defer { isLoading = false }
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = ProbeError.invalidURL.localizedDescription
            return
        }
        do { preview = try await GmailDeliveryService().renderProbe(url: url) }
        catch { self.error = error.localizedDescription }
    }
}

#if os(macOS)
struct ProbeHTMLView: NSViewRepresentable {
    let html: String
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }
    func makeCoordinator() -> ProbeHTMLState { ProbeHTMLState() }
}
#else
struct ProbeHTMLView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }
    func makeCoordinator() -> ProbeHTMLState { ProbeHTMLState() }
}
#endif

final class ProbeHTMLState {
    var html: String?
}
#endif
