import Semalot

/// Global gate that limits how many crawlers can have an HTTP call in flight at once. The ticket
/// pool is sized to the user's "Simultaneous calls" setting and rebuilt whenever that value changes.
/// A limit of `0` means unlimited, in which case no gating is applied.
final actor RequestGate {
    static let shared = RequestGate()

    private var limit: UInt = 0
    private var semalot: Semalot?

    /// Returns the lock to gate a single HTTP call, or `nil` when calls are unlimited. Callers must
    /// keep the returned reference for the matching `returnTicket()` so that a concurrency change
    /// mid-call cannot unbalance ticket accounting.
    func lock(for limit: UInt) -> Semalot? {
        guard limit > 0 else {
            self.limit = 0
            semalot = nil
            return nil
        }
        if limit != self.limit || semalot == nil {
            self.limit = limit
            semalot = Semalot(tickets: limit)
        }
        return semalot
    }
}
