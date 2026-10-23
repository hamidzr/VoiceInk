import ApplicationServices
import Foundation
import os

// Fork-only. Shortcut monitors install their event taps when they start, so an
// Accessibility grant made while VoiceInk runs leaves shortcuts dead until restart.
// Kept in its own file so upstream merges stay conflict-free.
@MainActor
final class AccessibilityGrantShortcutRefresher {
    static let shared = AccessibilityGrantShortcutRefresher()

    // posted by the system whenever the Accessibility client list changes
    private static let accessibilityDidChange = Notification.Name("com.apple.accessibility.api")

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AccessibilityGrantShortcutRefresher")
    private var observer: NSObjectProtocol?
    private var wasTrusted = false

    private init() {}

    func start() {
        guard observer == nil else { return }
        wasTrusted = AXIsProcessTrusted()

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.accessibilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // trust state settles shortly after the notification
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self?.refreshIfNewlyTrusted()
            }
        }
    }

    private func refreshIfNewlyTrusted() {
        let isTrusted = AXIsProcessTrusted()
        defer { wasTrusted = isTrusted }
        guard isTrusted, !wasTrusted else { return }

        logger.notice("Accessibility granted; reinstalling shortcut event taps")
        NotificationCenter.default.post(name: ShortcutStore.shortcutDidChange, object: nil)
        NotificationCenter.default.post(name: .modeShortcutAvailabilityDidChange, object: nil)
    }
}
