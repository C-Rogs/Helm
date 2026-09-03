import Foundation

/// Typed wake/companion diagnostic event names for phone + Watch relay.
/// Kept short for ring-buffer / Gemini export readability.
public enum WatchCompanionDiagnosticEvent: String, Sendable {
    // Phone
    case phoneLaunchBegin = "phone.launch.begin"
    case phoneLaunchAttempt = "phone.launch.attempt"
    case phoneLaunchResult = "phone.launch.result"
    case phoneCompanionPush = "phone.companion.push"
    case phoneReachability = "phone.reachability"
    case phoneFirstHeartRate = "phone.hr.first"
    case phoneHeartRateSessionStart = "phone.hr.session.start"
    case phoneHeartRateSessionEnd = "phone.hr.session.end"
    case phoneLiveConfirmTimeout = "phone.liveConfirm.timeout"
    case phoneLiveConfirmOK = "phone.liveConfirm.ok"
    case phoneDiagnosticRelay = "phone.diag.relay"

    // Watch
    case watchHandleBegin = "watch.handle.begin"
    case watchSessionStart = "watch.session.start"
    case watchSessionReady = "watch.session.ready"
    case watchSessionFail = "watch.session.fail"
    case watchCompanionActive = "watch.companion.active"
    case watchBootstrapStart = "watch.bootstrap.start"
    case watchEmergencyStart = "watch.emergency.start"
    case watchEmergencySkip = "watch.emergency.skip"
    case watchEmergencyFail = "watch.emergency.fail"
    case watchHKSessionFail = "watch.hk.session.fail"
    case watchCompanionDeactivated = "watch.companion.deactivated"
}
