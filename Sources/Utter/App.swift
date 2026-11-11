import UtterCore
import AppKit
import SwiftUI

@main
struct UtterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item is an AppKit status item (StatusItemController), which
    // supports right-click. SwiftUI still needs a scene: a menu bar extra that is
    // never inserted shows nothing. (An empty Settings scene would open a blank
    // "Utter Settings" window at launch on macOS 27.)
    var body: some Scene {
        MenuBarExtra("Utter", isInserted: .constant(false)) { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            #if DEBUG
            // Developer tools (debug builds only): --snapshot <dir>, --probe-speech <file>,
            // --probe-whisper-stream <file>, --probe-parakeet <file>.
            if Snapshots.runIfRequested() {
                NSApp.terminate(nil)
                return
            }
            if SpeechProbe.runIfRequested() { return } // exits when done
            if StreamProbe.runIfRequested() { return } // exits when done
            if ParakeetProbe.runIfRequested() { return } // exits when done
            #endif
            AppState.shared.start()
            StatusItemController.shared.install(state: AppState.shared)
            // Menu bar apps are easy to miss: show the setup window until setup is done.
            // (The Claude API key is optional, so it isn't part of this.)
            if AppState.shared.setupStepsDone < 4 {
                SettingsWindow.show(page: .setup)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { WhisperSidecar.shared.stop() }
    }

    /// Opening the app again (double-click, `open`, Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { SettingsWindow.show() }
        return true
    }
}
