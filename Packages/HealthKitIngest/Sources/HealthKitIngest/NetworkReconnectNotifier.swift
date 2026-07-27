import Foundation
import Network

/// Fires when network path becomes satisfied (e.g. after offline barcode queue).
public final class NetworkReconnectNotifier: @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let lock = NSLock()
    private nonisolated(unsafe) var wasSatisfied = true
    private nonisolated(unsafe) var handler: (@Sendable () -> Void)?

    public init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            let shouldNotify: Bool = self.lock.withLock {
                let notify = !self.wasSatisfied && satisfied
                self.wasSatisfied = satisfied
                return notify
            }
            if shouldNotify {
                self.lock.withLock { self.handler?() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.cameronro.helm.network-reconnect"))
    }

    deinit {
        monitor.cancel()
    }

    public func setHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.handler = handler
            wasSatisfied = true
        }
    }
}
