import AppKit
import Foundation
import WebKit

struct Corpus: Decodable { let articles: [Article] }
struct Article: Codable { let id: String; let url: URL; let imageGate: Bool }
struct BrowserBaseline: Codable {
    let url: String
    let title: String
    let excerpt: String
    let selectedText: String
    let imageURL: String?
    let bodyText: String
}
struct ArticleResult: Codable {
    let article: Article
    var baseline: BrowserBaseline?
    var baselineError: String?
    var urlOnly: ProbePreview?
    var urlOnlyError: String?
    var urlOnlyMetrics: ProbeMetrics?
    var browserContext: ProbePreview?
    var browserContextError: String?
    var browserContextMetrics: ProbeMetrics?
}

@MainActor final class BaselineBrowser: NSObject, WKNavigationDelegate {
    let view: WKWebView
    var continuation: CheckedContinuation<Void, Error>?
    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        super.init()
        view.navigationDelegate = self
    }
    func capture(url: URL, preprocessor: String) async throws -> BrowserBaseline {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.load(URLRequest(url: url, timeoutInterval: 12))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                if let pending = self.continuation {
                    self.continuation = nil
                    self.view.stopLoading()
                    pending.resume(throwing: URLError(.timedOut))
                }
            }
        }
        try await Task.sleep(for: .seconds(1))
        let js = """
        (() => {
          \(preprocessor)
          let result;
          ExtensionPreprocessingJS.run({completionFunction: value => result = value});
          result.imageURL = document.querySelector('meta[property="og:image"],meta[name="twitter:image"]')?.content || null;
          result.bodyText = (document.querySelector('article,main') || document.body).innerText;
          return JSON.stringify(result);
        })()
        """
        guard let json = try await view.evaluateJavaScript(js) as? String else { throw URLError(.cannotParseResponse) }
        return try JSONDecoder().decode(BrowserBaseline.self, from: Data(json.utf8))
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
    private func finish(_ error: Error?) {
        let pending = continuation
        continuation = nil
        if let error { pending?.resume(throwing: error) } else { pending?.resume() }
    }
}

@main struct ProbeHarness {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let args = CommandLine.arguments
        guard args.count == 4 else {
            print("Usage: probe-harness corpus.json SafariPreprocessor.js output-directory")
            return
        }
        let corpusData = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let corpus = try JSONDecoder().decode(Corpus.self, from: corpusData)
        let preprocessor = try String(contentsOfFile: args[2], encoding: .utf8)
        let output = URL(fileURLWithPath: args[3], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try corpusData.write(to: output.appendingPathComponent("corpus.json"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var results: [ArticleResult] = []
        for article in corpus.articles {
            print("Testing \(article.id)")
            fflush(stdout)
            var result = ArticleResult(article: article)
            // URL-only first, before browser context, with production metadata cache bypassed.
            let urlTrace = ProbeTrace()
            do { result.urlOnly = try await GmailDeliveryService().renderProbe(url: article.url, trace: urlTrace) }
            catch { result.urlOnlyError = error.localizedDescription }
            result.urlOnlyMetrics = urlTrace.finish()
            let browser = BaselineBrowser()
            do {
                let baseline = try await browser.capture(url: article.url, preprocessor: preprocessor)
                result.baseline = baseline
                let contextTrace = ProbeTrace()
                do {
                    result.browserContext = try await GmailDeliveryService().renderProbe(
                        url: URL(string: baseline.url) ?? article.url, title: baseline.title,
                        excerpt: baseline.excerpt, imageURL: baseline.imageURL, trace: contextTrace)
                } catch { result.browserContextError = error.localizedDescription }
                result.browserContextMetrics = contextTrace.finish()
            } catch { result.baselineError = error.localizedDescription }
            for (label, preview) in [("url", result.urlOnly), ("browser", result.browserContext)] {
                if let preview {
                    try preview.html.write(to: output.appendingPathComponent(article.id + "-" + label + ".html"), atomically: true, encoding: .utf8)
                }
            }
            // Full local evidence includes article text for assessment; keep under ignored build/.
            try encoder.encode(result).write(to: output.appendingPathComponent(article.id + ".json"))
            results.append(result)
            print("  URL: \(result.urlOnly == nil ? result.urlOnlyError ?? "failed" : "preview") · browser: \(result.baseline == nil ? "failed" : "captured")")
            fflush(stdout)
        }
        try encoder.encode(results).write(to: output.appendingPathComponent("results.json"))
    }
}
