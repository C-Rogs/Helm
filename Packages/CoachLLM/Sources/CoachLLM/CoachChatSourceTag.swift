import Foundation

    public struct CoachChatSourceTag: Equatable, Sendable, Identifiable {
        public var id: String { rawID }

        public let rawID: String
        public let display: String
        public let kind: Kind

        public enum Kind: String, Sendable, Equatable {
            case evidence
            case topic
            case engine
        }

        public init(rawID: String, display: String, kind: Kind) {
            self.rawID = rawID
            self.display = display
            self.kind = kind
        }
    }
