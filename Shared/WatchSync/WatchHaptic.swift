#if os(watchOS)
import WatchKit

/// Maps `Docs/HAPTICS.md` moments onto WatchKit. Watch has no Core Haptics.
enum WatchHaptic {
    case sessionStart
    case sessionPause
    case sessionEnd
    case setLogged
    case setAck
    case restCountIn
    case restDone
    case restSkip
    case restAdjust
    case selection
    case failure

    func play() {
        WKInterfaceDevice.current().play(wkType)
    }

    static func playPause(isPaused: Bool) {
        (isPaused ? sessionStart : sessionPause).play()
    }

    private var wkType: WKHapticType {
        switch self {
        case .sessionStart: .start
        case .sessionPause, .sessionEnd: .stop
        case .setLogged, .restCountIn, .restAdjust, .selection: .click
        case .setAck: .success
        case .restDone: .failure
        case .restSkip: .directionUp
        case .failure: .failure
        }
    }
}
#endif
