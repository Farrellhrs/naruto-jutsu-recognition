import UIKit

/// Centralized haptic feedback so game events feel physical.
/// Generators are prepared once and reused; all calls are main-thread safe.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    /// A hand sign was committed / sequence advanced.
    static func signCommitted() {
        light.impactOccurred(intensity: 0.7)
    }

    /// A jutsu fired.
    static func jutsuTriggered() {
        heavy.impactOccurred()
    }

    /// Successful block / perfect defense.
    static func defenseSuccess() {
        notification.notificationOccurred(.success)
    }

    /// Player took damage.
    static func playerHit() {
        notification.notificationOccurred(.error)
    }

    /// Enemy took damage.
    static func enemyHit() {
        medium.impactOccurred(intensity: 0.9)
    }

    /// UI selection (menu taps).
    static func select() {
        light.impactOccurred(intensity: 0.5)
    }
}
