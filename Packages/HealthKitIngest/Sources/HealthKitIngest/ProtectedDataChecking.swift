import Foundation
#if canImport(UIKit)
import UIKit
#endif

public protocol ProtectedDataChecking: Sendable {
    var isProtectedDataAvailable: Bool { get }
}

public struct LiveProtectedDataChecker: ProtectedDataChecking {
    public init() {}

    public var isProtectedDataAvailable: Bool {
        #if canImport(UIKit)
        if Thread.isMainThread {
            return MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { UIApplication.shared.isProtectedDataAvailable }
        }
        #else
        return true
        #endif
    }
}

public struct FixedProtectedDataChecker: ProtectedDataChecking {
    public let isProtectedDataAvailable: Bool

    public init(isAvailable: Bool) {
        isProtectedDataAvailable = isAvailable
    }
}
