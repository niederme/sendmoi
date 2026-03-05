import Foundation
import Network

final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "SendMoi.NetworkMonitor")

    var onStatusChange: (@Sendable (Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onStatusChange?(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
