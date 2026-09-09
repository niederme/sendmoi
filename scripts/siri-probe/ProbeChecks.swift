import AppKit
import Foundation

@main struct ProbeChecks {
    static func main() async throws {
        // A long sidebar must not beat a substantive semantic article. Resources,
        // captions and code blocks must not become summary text.
        let prose = "Researchers followed the trees through autumn and measured how the leaves changed as days grew shorter. Their observations showed that changes in light and temperature affected the timing of the colors across the forest. The team compared several species over multiple seasons to distinguish a consistent pattern from ordinary variation. The results help explain why neighboring trees can show different colors on the same day. The findings also give visitors a clearer understanding of the seasonal changes they see outdoors."
        let html = "<body><article><nav>Contents: introduction results discussion</nav><h2>A misleading table of contents heading</h2><p>Note to editors: Download the press kit here.</p><p>\(prose)</p><figure><img src='http://127.0.0.1:9/never-load'><figcaption>Courtesy of a photographer.</figcaption></figure><pre>const scriptNoise = {}; console.log(scriptNoise);</pre></article><aside>\(String(repeating: "Promotional sidebar sentence. ", count: 200))</aside></body>"
        let extracted = GmailDeliveryService.probeArticleText(html: html)
        precondition(extracted == prose, "Article extraction retained chrome: \(extracted)")
        let entities = GmailDeliveryService.probeArticleText(html: "<p>Fish &amp; chips cost &#163;5 &mdash; today.</p>")
        precondition(entities == "Fish & chips cost £5 — today.", "Entity decoding changed: \(entities)")
        let longSentence = String(repeating: "word ", count: 120)
        let summary = GmailDeliveryService.probeExtractiveSummary(longSentence, maxWords: 40)!
        precondition(summary.split(whereSeparator: \.isWhitespace).count == 40)
        precondition(GmailDeliveryService.probeIsChallenge("<html><title>Client Challenge</title></html>"))
        precondition(!GmailDeliveryService.probeIsChallenge("<html><title>Understanding the client challenge protocol</title></html>"))
        print("PASS: article isolation, resource/chrome removal, entities, summary bounds, challenge detection")
        let service = GmailDeliveryService()
        for value in ["file:///tmp/article", "ftp://example.com/a", "https://user:password@example.com/a"] {
            do {
                _ = try await service.renderProbe(url: URL(string: value)!)
                fatalError("Invalid URL accepted: \(value)")
            } catch ProbeError.invalidURL { }
        }
        print("PASS: non-web and credential-bearing URLs rejected")
        let session = GmailSession(accessToken: "test-only", refreshToken: "test-only", expiryDate: .distantFuture, emailAddress: nil)
        do {
            try await service.sendEmail(using: session, item: QueuedEmail(toEmail: "", title: "", excerpt: "", urlString: ""))
            fatalError("Probe allowed email delivery")
        } catch ProbeError.sendingDisabled { }
        print("PASS: sending is disabled before any transport or queue access")
        let cancelled = Task {
            try Task.checkCancellation()
            return try await service.renderProbe(url: URL(string: "https://example.com")!)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled probe completed") }
        catch is CancellationError { }
        print("PASS: cancellation is propagated")
    }
}
