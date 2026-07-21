/// Weekly hard-set volume landmarks for a single muscle (RP-style MEV/MRV).
public struct VolumeLandmarks: Sendable, Hashable, Codable {
    /// Minimum effective volume: weekly hard sets below this under-stimulate.
    public let mev: Int
    /// Maximum recoverable volume: weekly hard sets above this exceed recovery capacity.
    public let mrv: Int

    public init(mev: Int, mrv: Int) {
        precondition(mev > 0, "MEV must be positive")
        precondition(mrv >= mev, "MRV must be at least MEV")
        self.mev = mev
        self.mrv = mrv
    }
}
