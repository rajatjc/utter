import UtterCore
import AppKit
import ApplicationServices
import AVFoundation
import Speech

enum Permissions {
    struct Status: Equatable {
        var microphone = false
        var speech = false
        var accessibility = false
        var allGranted: Bool { microphone && speech && accessibility }
    }

    static func current() -> Status {
        Status(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speech: SFSpeechRecognizer.authorizationStatus() == .authorized,
            accessibility: AXIsProcessTrusted()
        )
    }

    /// Asks for anything not yet decided. Accessibility can't be granted from a
    /// prompt; macOS shows a dialog pointing to System Settings.
    static func requestAll(completion: @escaping @MainActor () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { completion() } }
            }
        }
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case speech = "Privacy_SpeechRecognition"
        case accessibility = "Privacy_Accessibility"
    }

    static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
