#!/usr/bin/env python3
"""Run isolated Swift regression checks. No app container, credentials, or email sends."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
service = (root / 'SendMoi/Services/GmailDeliveryService.swift').read_text()
# Compile the production deadline helper without the Gmail/UI dependencies.
start = service.index('    static func resultWithinDeadline<T: Sendable>')
end = service.index('    private static func summarizeWithFoundationModels', start)
state_start = service.index('private final class DeadlineRaceState:')
state_end = service.index('private extension URLSession', state_start)
deadline = 'enum Deadline {\n' + service[start:end] + '}\n' + service[state_start:state_end]
harness = r'''
import Foundation

struct QueuedEmail: Codable {
    var id = UUID()
    var lastError: String?
}
enum SharedContainer {
    static func appDirectoryURL() throws -> URL {
        URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }
}

@main struct QueueRegressionTests {
    static func main() async throws {
        if CommandLine.arguments.count > 2 {
            for _ in 0..<25 { try QueueStore.append(QueuedEmail()) }
            return
        }
        let first = QueuedEmail()
        let second = QueuedEmail()
        try QueueStore.append(first)
        try QueueStore.append(first)
        assert(try QueueStore.load().count == 1, "same queue identity must not be appended twice")
        try QueueStore.append(second)
        try QueueStore.remove(ids: [first.id])
        assert(try QueueStore.load().map(\.id) == [second.id], "removing sent item must preserve a new append")
        try QueueStore.markFailure(id: second.id, message: "temporary failure")
        assert(try QueueStore.load().first?.lastError == "temporary failure")
        try QueueStore.remove(ids: [second.id])
        assert(try !QueueStore.replace(second), "late enrichment must not resurrect a sent item")

        let owner = try QueueStore.acquireDeliveryLock()!
        assert(try QueueStore.acquireDeliveryLock() == nil, "only one queue sender at a time")
        QueueStore.releaseDeliveryLock(owner)
        let nextOwner = try QueueStore.acquireDeliveryLock()!
        QueueStore.releaseDeliveryLock(nextOwner)

        var children: [Process] = []
        for _ in 0..<4 {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [CommandLine.arguments[1], "append"]
            try child.run()
            children.append(child)
        }
        for child in children {
            child.waitUntilExit()
            assert(child.terminationStatus == 0)
        }
        assert(try QueueStore.load().count == 100, "concurrent processes must preserve every item")

        let preview = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        let start = Date()
        let timedOut = await Deadline.resultWithinDeadline(nanoseconds: 20_000_000) {
            await preview.value // Awaiting an unstructured task ignores waiter cancellation.
            return true
        }
        assert(timedOut == nil)
        assert(Date().timeIntervalSince(start) < 0.25, "preview deadline must not wait for the loser")
        await preview.value // Exercise late completion without double-resuming the continuation.
        let completed = await Deadline.resultWithinDeadline(nanoseconds: 100_000_000) { 42 }
        assert(completed == 42)
        print("PASS: queue identity, concurrent mutations, delivery lock, preview deadline and late completion")
    }
}
'''
# Swift assert autoclosures cannot throw. Evaluate throwing expressions first.
harness = harness.replace('assert(try ', 'try check(')
harness += '\nfunc check(_ value: Bool, _ message: String = "check failed") throws { assert(value, message) }\n'
with tempfile.TemporaryDirectory(prefix='sendmoi-queue-tests-') as directory:
    base = Path(directory)
    (base / 'Harness.swift').write_text(harness)
    (base / 'Deadline.swift').write_text('import Foundation\n' + deadline)
    binary = base / 'queue-tests'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(root / 'SendMoi/Services/QueueStore.swift'),
                    str(base / 'Deadline.swift'), str(base / 'Harness.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), directory], check=True)
