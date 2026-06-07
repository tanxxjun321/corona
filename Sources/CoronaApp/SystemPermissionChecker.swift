import AppKit
import ApplicationServices
import CoronaCore
import CoreGraphics

struct SystemPermissionChecker: PermissionChecking {
    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AXIsProcessTrusted() ? .granted : .missing,
            screenRecording: hasScreenRecordingPermission() ? .granted : .missing
        )
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openScreenRecordingSettings() {
        openSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func openSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
