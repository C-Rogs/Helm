import Foundation
import Network

/// Gates Open Food Facts calls when the device has no usable network path.
public protocol NetworkGating: Sendable {
    func isOnline() async -> Bool
}

public final class LiveNetworkGate: NetworkGating, @unchecked Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var isConnected = true
    private let monitor: NWPathMonitor

    public init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.withLock {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.cameronro.helm.network-gate"))
    }

    deinit {
        monitor.cancel()
    }

    public func isOnline() async -> Bool {
        lock.withLock { isConnected }
    }
}

public struct FixedNetworkGate: NetworkGating, Sendable {
    private let online: Bool

    public init(online: Bool) {
        self.online = online
    }

    public func isOnline() async -> Bool {
        online
    }
}
