import AppKit
import Foundation

@main struct ProbeChecks {
    static func main() async throws {
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
