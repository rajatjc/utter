import UtterCore
import AppKit
import SwiftUI

#if DEBUG
/// Developer aid: `Utter.app/Contents/MacOS/Utter --snapshot <dir>` renders every
/// screen to PNGs with sample data and exits, so the UI can be reviewed without
/// screen recording. Not used in normal launches.
@MainActor
enum Snapshots {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return false }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let state = AppState.shared
        state.frozenPermissions = true
        state.history = sampleHistory

        // Menu bar panel: before and after setup.
        state.permissions = Permissions.Status(microphone: true, speech: true, accessibility: false)
        state.hasAPIKey = false
        StatsStore.shared.useDemoData()
        render(MenuContent().environmentObject(state), to: dir, "menu-setup")
        state.permissions = Permissions.Status(microphone: true, speech: true, accessibility: true)
        state.hasAPIKey = true
        render(MenuContent().environmentObject(state), to: dir, "menu-ready")

        // Settings: the shell (sidebar) once, then each page's content on its own,
        // because the offscreen renderer can't draw scroll views or blur materials.
        state.permissions = Permissions.Status(microphone: true, speech: true, accessibility: false)
        state.hasAPIKey = false
        render(SettingsView().environmentObject(state).background(Color(nsColor: .windowBackgroundColor)),
               to: dir, "settings-shell")
        func page(_ page: SettingsPage, _ name: String) {
            render(
                SettingsPageView(page: page)
                    .environmentObject(state)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(width: 570, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor)),
                to: dir, name
            )
        }
        for item in SettingsPage.allCases { page(item, "page-\(item.rawValue)") }
        state.permissions = Permissions.Status(microphone: true, speech: true, accessibility: true)
        state.hasAPIKey = true
        page(.setup, "page-setup-done")

        // The bar in each state, on a light backdrop so the dark shapes are visible:
        // the notch island (with the real notch width) and the floating pill.
        let notch = NotchGeometry(screenFrame: NSRect(x: 0, y: 0, width: 1728, height: 1117),
                                  centerX: 864, width: 185, bandHeight: 32, hasNotch: true)
        func bar(_ name: String) {
            render(NotchIslandView(geometry: notch).environmentObject(state)
                .padding(.horizontal, 40).padding(.bottom, 30)
                .background(Color(white: 0.92)), to: dir, "notch-\(name)")
            render(FloatingBarView().environmentObject(state).padding(30).background(Color(white: 0.92)),
                   to: dir, "bar-\(name)")
        }
        state.phase = .idle
        bar("idle")
        state.barHovering = true
        bar("idle-hover")
        state.barHovering = false
        state.isMuted = true
        bar("idle-muted")
        state.isMuted = false
        state.phase = .listening(.dictation)
        state.liveTranscript = ""
        state.livePreview = false
        state.sessionMode = .dictation
        state.listeningSince = Date().addingTimeInterval(-7)
        state.level = 0.6
        bar("listening-voice-only")
        state.livePreview = true
        state.level = 0
        bar("listening-empty")
        state.liveTranscript = "so I was thinking we could meet at four tomorrow to go over the roadmap"
        state.level = 0.7
        bar("listening-dictation")
        state.handsFree = true
        bar("listening-handsfree")
        state.handsFree = false
        state.phase = .listening(.command)
        state.liveTranscript = ""
        bar("listening-command")
        // Voice-only dictation: listening → polishing → done, all one size.
        state.sessionMode = .dictation
        state.livePreview = false
        state.phase = .processing(.dictation)
        state.step = "Polishing…"
        bar("dictation-polishing")
        state.phase = .done("Inserted 12 words")
        state.phaseSince = Date().addingTimeInterval(-1)
        bar("dictation-done")
        // Voice-only command: the same footprint as dictation, error included.
        state.sessionMode = .command
        state.phase = .listening(.command)
        state.level = 0.6
        bar("command-voice-only-listening")
        state.phase = .processing(.command)
        state.step = "Searching for flights to Lisbon in March…"
        bar("command-voice-only-working")
        state.phase = .done("Opened Slack and searched for flights to Lisbon.")
        state.phaseSince = Date().addingTimeInterval(-1)
        bar("command-voice-only-done")
        state.phase = .failed("Commands need a Claude API key: Settings → AI.")
        bar("command-voice-only-failed")
        state.sessionMode = .command
        state.livePreview = true
        state.phase = .processing(.command)
        state.step = "Opening Slack…"
        bar("processing")
        state.confirmPurpose = "Deploy the website"
        state.phase = .confirm("cd ~/code/website && ./deploy.sh")
        bar("confirm")
        state.phase = .done("Opened Slack and searched for flights to Lisbon.")
        state.phaseSince = Date().addingTimeInterval(-1) // completion animation finished
        bar("done")
        state.phase = .failed("Didn't catch that.")
        bar("failed")

        // The island as it looks in use: hanging from the menu bar over a desktop,
        // for the README and the portfolio.
        func onDesktop(_ name: String) {
            render(ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.09, green: 0.08, blue: 0.18),
                                        Color(red: 0.22, green: 0.12, blue: 0.30),
                                        Color(red: 0.40, green: 0.18, blue: 0.26)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.35), .clear],
                               center: UnitPoint(x: 0.8, y: 1.1), startRadius: 0, endRadius: 420)
                Rectangle().fill(Color.black.opacity(0.28)).frame(height: notch.bandHeight)
                NotchIslandView(geometry: notch).environmentObject(state)
            }
            .frame(width: 540, height: 140)
            .environment(\.colorScheme, .dark), to: dir, "desktop-\(name)")
        }
        state.phase = .idle
        state.barHovering = true
        onDesktop("controls")
        state.barHovering = false
        state.sessionMode = .dictation
        state.livePreview = false
        state.phase = .listening(.dictation)
        state.level = 0.7
        onDesktop("listening")
        state.phase = .processing(.dictation)
        state.step = "Polishing…"
        onDesktop("polishing")
        state.phase = .done("Inserted 12 words")
        state.phaseSince = Date().addingTimeInterval(-1)
        onDesktop("done")
        state.sessionMode = .command
        state.livePreview = true
        state.confirmPurpose = "Deploy the website"
        state.phase = .confirm("cd ~/code/website && ./deploy.sh")
        onDesktop("confirm")

        // The island at the notch widths of different display scalings:
        // "Larger Text" (≈150 pt), default (185 pt) and "More Space" (≈230 pt).
        func island(width: CGFloat, band: CGFloat) -> some View {
            NotchIslandView(geometry: NotchGeometry(screenFrame: .zero, centerX: 0, width: width,
                                                    bandHeight: band, hasNotch: true))
                .environmentObject(state)
        }
        func sizes(_ name: String) {
            render(HStack(alignment: .top, spacing: 24) {
                island(width: 150, band: 28)
                island(width: 185, band: 32)
                island(width: 230, band: 38)
            }.padding(24).background(Color(white: 0.92)), to: dir, "sizes-\(name)")
        }
        state.phase = .idle
        state.barHovering = true
        sizes("controls")
        state.barHovering = false
        state.sessionMode = .dictation
        state.livePreview = false
        state.phase = .listening(.dictation)
        state.level = 0.6
        sizes("listening")
        state.phase = .done("Inserted 12 words")
        state.phaseSince = Date().addingTimeInterval(-1)
        sizes("done")
        state.sessionMode = .command
        state.livePreview = true
        state.phase = .done("Opened Slack and searched for flights to Lisbon.")
        sizes("command-result")

        // The blob at a large size across its morph: quiet (top) and speaking (bottom).
        func strip(_ level: Double) -> some View {
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { i in
                    AIOrb(mood: .listening, level: Float(level), colors: Theme.colors(for: .dictation), since: Date(),
                          size: 180, preview: (flow: Double(i) * 1.1, drift: Double(i) * 0.5, level: level))
                }
            }
        }
        render(VStack(spacing: 0) { strip(0); strip(0.8) }.padding(20).background(Color(white: 0.04)),
               to: dir, "blob-morph")

        print("Snapshots written to \(dir.path)")
        return true
    }

    private static func render<V: View>(_ view: V, to dir: URL, _ name: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("Could not render \(name)")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private static var sampleHistory: [HistoryItem] {
        [
            HistoryItem(mode: .dictation,
                        transcript: "hey sam can you send me the q3 numbers by friday also um what time is the standup",
                        output: "Hey Sam, can you send me the Q3 numbers by Friday? Also, what time is the standup?",
                        app: "Slack"),
            HistoryItem(mode: .command,
                        transcript: "remind me tomorrow at nine to call the landlord",
                        output: "Added a reminder for tomorrow at 9:00 AM to call the landlord.",
                        app: "Safari"),
            HistoryItem(mode: .dictation,
                        transcript: "the deploy failed because the env file was missing",
                        output: "The deploy failed because the env file was missing.",
                        app: "Cursor"),
        ]
    }
}
#endif
