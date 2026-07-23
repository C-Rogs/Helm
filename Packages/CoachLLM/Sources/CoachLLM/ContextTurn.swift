/// Whether the coach is opening a thread or continuing one.
public enum ContextTurn: Sendable, Equatable {
    case initial
    case followUp
}
