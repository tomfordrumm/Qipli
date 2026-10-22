import Foundation

/// Rate-limits failed rebuilds without permanently abandoning global input.
struct EventTapRecoveryPolicy {
    private(set) var recoveryAttempts = 0
    mutating func nextRetryDelay() -> TimeInterval {
        let delay = min(5, 0.25 * pow(2, Double(min(recoveryAttempts, 5))))
        recoveryAttempts = min(recoveryAttempts + 1, 6)
        return delay
    }

    mutating func recordHealthyEvent() {
        recoveryAttempts = 0
    }
}
