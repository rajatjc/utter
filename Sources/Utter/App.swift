import UtterCore
import AppKit
import SwiftUI

@main
struct UtterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            if case .idle = state.phase, !state.isMuted {
                Image(nsImage: MenuBarIcon.image)
            } else {
                Image(systemName: state.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no app menu.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            #if DEBUG
            // Developer tools (debug builds only): --snapshot <dir>, --probe-speech <file>.
            if Snapshots.runIfRequested() {
                NSApp.terminate(nil)
                return
            }
            if SpeechProbe.runIfRequested() { return } // exits when done
            #endif
            AppState.shared.start()
            // Menu bar apps are easy to miss: show the setup window until everything is ready.
            if !Permissions.current().allGranted || Keychain.apiKey() == nil {
                SettingsWindow.show()
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
