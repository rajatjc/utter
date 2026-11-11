import UtterCore
import AppKit
import SwiftUI

// MARK: - Derived display state

extension AppState {
    var hudIsIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    var hudIsListening: Bool {
        if case .listening = phase { return true }
        return false
    }

    var hudPhaseKey: String {
        switch phase {
        case .idle: "idle"
        case .listening(let m): "listening-\(m)"
        case .processing(let m): "processing-\(m)"
        case .done: "done"
        case .failed: "failed"
        case .notice: "notice"
        case .confirm: "confirm"
        }
    }

    var hudColors: [Color] {
        switch phase {
        case .listening(let m), .processing(let m): Theme.colors(for: m)
        case .done: [Theme.mint, Color(red: 0.25, green: 0.75, blue: 0.85)]
        case .failed, .notice: [Theme.amber, Theme.coral]
        case .confirm: [Theme.violet, Theme.amber]
        case .idle: Theme.brandColors
        }
    }

    var hudSymbol: String {
        switch phase {
        case .listening(.dictation): "mic.fill"
        case .listening(.command): "sparkles"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .notice: "mic.slash.fill"
        case .confirm: "terminal.fill"
        default: "waveform"
        }
    }

    var hudIsConfirming: Bool {
        if case .confirm = phase { return true }
        return false
    }

    var hudTitle: String {
        switch phase {
        case .listening(.dictation):
            handsFree ? "LISTENING · ✓ OR \(Prefs.hotkey(for: .dictation).label.uppercased()) TO FINISH" : "LISTENING"
        case .listening(.command):
            handsFree ? "COMMAND · ✓ OR \(Prefs.hotkey(for: .command).label.uppercased()) WHEN DONE" : "COMMAND"
        case .processing(.dictation): "POLISHING"
        case .processing(.command): "WORKING"
        case .done: "DONE"
        case .failed: "HMM"
        case .notice: "MUTED"
        case .confirm: confirmPurpose.isEmpty ? "RUN IN TERMINAL?" : "RUN IN TERMINAL? · \(confirmPurpose.uppercased())"
        case .idle: ""
        }
    }

    var hudIsPlaceholder: Bool {
        if case .listening = phase { return liveTranscript.isEmpty }
        return false
    }

    /// Voice-only sessions: no live text, just the waveform and a timer.
    var hudVoiceOnly: Bool { hudIsListening && !livePreview }

    var hudDetail: String {
        switch phase {
        case .listening(.dictation) where !livePreview:
            handsFree ? "Click ✓ when you're done" : "Release to insert"
        case .listening(.command) where !livePreview:
            handsFree ? "Say what to do, then click ✓" : "Say what to do, then release"
        case .listening(.command) where liveTranscript.isEmpty:
            "Try “open Slack” or “make this friendlier”"
        case .listening:
            liveTranscript.isEmpty ? "Start talking…" : liveTranscript
        case .processing:
            step.isEmpty ? liveTranscript : step
        case .done(let message), .failed(let message), .notice(let message), .confirm(let message):
            message
        case .idle:
            ""
        }
    }
}

