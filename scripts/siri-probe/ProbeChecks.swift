import AppKit
import Foundation

@main struct ProbeChecks {
    static func main() async throws {
        let trace = ProbeTrace()
        let span = trace.begin("model")
        try await Task.sleep(for: .milliseconds(10))
        let frozen = trace.finish() // A timeout can freeze a still-running phase.
        precondition(frozen.phaseSeconds["model", default: 0] > 0)
        trace.end(span)
        trace.recordSource("model", path: "body") // Late work must not change evidence.
        precondition(trace.finish().summarySource == "none")
        precondition(trace.finish().phaseSeconds == frozen.phaseSeconds)
        precondition(frozen.budgetSeconds == 8 && frozen.modelBudgetSeconds == 3)
        print("PASS: timeout retains partial timings and freezes late updates")
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
        if let input = CommandLine.arguments.dropFirst().first, let url = URL(string: input) {
            let trace = ProbeTrace()
            do { _ = try await service.renderProbe(url: url, trace: trace) }
            catch { print("SMOKE OUTCOME: \(error.localizedDescription)") }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(trace.finish()), as: UTF8.self))
        }
    }
}
