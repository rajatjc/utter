import UtterCore
import AppKit
import SwiftUI

#if DEBUG
/// Developer aid: `Utter --orb-bench [orb|wave|both] [seconds]` shows the voice-only
/// listening row (orb and/or waveform, at real size) in a window, fed a simulated
/// voice at 20 updates a second like the microphone, then quits. Measure the
/// process's CPU while it runs to see what the animation costs.
@MainActor
enum OrbBench {
    final class Feed: ObservableObject {
        @Published var level: Float = 0
    }

    struct Row: View {
        @ObservedObject var feed: Feed
        let parts: String

        var body: some View {
            HStack(spacing: 10) {
                if parts != "wave" {
                    AIOrb(mood: .listening, level: feed.level, colors: Theme.colors(for: .dictation), since: Date())
                }
                if parts != "orb" {
                    Waveform(level: feed.level, colors: Theme.colors(for: .dictation), bars: 28)
                        .frame(width: 150, height: 28)
                }
            }
            .padding(14)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        }
    }

    private static var window: NSWindow?

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--orb-bench") else { return false }
        let parts = args.count > i + 1 ? args[i + 1] : "both"
        let seconds = args.count > i + 2 ? Double(args[i + 2]) ?? 20 : 20

        let feed = Feed()
        let host = NSHostingView(rootView: Row(feed: feed, parts: parts))
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 200, y: 200), size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.level = .floating
        window.orderFrontRegardless()
        self.window = window

        // Talk for 3.5 s, pause for 1.5 s, repeat: covers steady speech and the jolt.
        let start = Date()
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let t = Date().timeIntervalSince(start)
                let talking = t.truncatingRemainder(dividingBy: 5) < 3.5
                let syllable = max(0, sin(t * 9 + sin(t * 2.3) * 2))
                feed.level = talking ? Float(min(1, 0.25 + 0.65 * syllable + 0.1 * Double.random(in: 0...1))) : 0.02
                if t > seconds { NSApp.terminate(nil) }
            }
        }
        print("orb-bench: \(parts) for \(Int(seconds)) s, pid \(ProcessInfo.processInfo.processIdentifier)")
        return true
    }
}
#endif
