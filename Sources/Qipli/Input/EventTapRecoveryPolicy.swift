import Foundation

/// Bounds event-tap recovery so repeated system disables cannot create a busy loop.
struct EventTapRecoveryPolicy {
    let maximumAttempts: Int
    private(set) var recoveryAttempts = 0

    init(maximumAttempts: Int) {
        precondition(maximumAttempts > 0)
        self.maximumAttempts = maximumAttempts
    }

    mutating func permitsRecovery() -> Bool {
        guard recoveryAttempts < maximumAttempts else { return false }
        recoveryAttempts += 1
        return true
    }

    mutating func recordHealthyEvent() {
        recoveryAttempts = 0
    }
}
