import Core
import Foundation

enum ProactiveCoachPreferences {
    private enum Key {
        static let peek = "helm.proactive.peek"
        static let banner = "helm.proactive.banner"
        static let autoChat = "helm.proactive.autoChat"
        static let push = "helm.proactive.push"
    }

    static var peekEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.peek) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.peek) }
    }

    static var bannerEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.banner) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.banner) }
    }

    static var autoChatEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.autoChat) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoChat) }
    }

    static var pushEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.push) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.push) }
    }
}
