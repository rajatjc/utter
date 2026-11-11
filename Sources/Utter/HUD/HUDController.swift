import UtterCore
import AppKit
import SwiftUI

/// The bar: never takes keyboard focus, so the app you're typing into stays
/// active. In notch style it hangs from the notch and expands below it; in
/// floating style it's a draggable pill. Either way it shows the live transcript
/// while you talk and click-to-talk buttons when hovered.
@MainActor
final class HUDController {
    private let state: AppState
    private var panel: NotchPanel?
    private var hideWork: DispatchWorkItem?
    private var style: Prefs.BarStyle
    /// Floating style: horizontal center plus top or bottom edge of the bar.
    private var anchor: Prefs.BarAnchor?
    private var adjusting = false
    private var observers: [NSObjectProtocol] = []

    init(state: AppState) {
        self.state = state
        style = Prefs.barStyle
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() } // e.g. lid closed onto an external display
        })
    }

    func start() {
        if staysVisibleWhenIdle { show() }
        // Notch style: the idle island is invisible and the pointer disappears
        // under the notch, so hover is detected from the pointer position in a
        // zone around and just below the notch, rather than from the window.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollNotchHover() }
        }
    }

    private var hoverTimer: Timer?
    private var hoverSince: Date?

    private func pollNotchHover() {
        guard style == .notch else { return }
        guard let panel, panel.isVisible else {
            if state.barHovering { setHover(false) }
            return
        }
        let g = NotchGeometry.current()
        let zone = NSRect(
            x: g.centerX - g.width / 2 - 30,
            y: g.screenFrame.maxY - g.bandHeight - 14,
            width: g.width + 60,
            height: g.bandHeight + 14
        )
        let mouse = NSEvent.mouseLocation
        let inside = zone.contains(mouse) || panel.frame.insetBy(dx: -6, dy: -6).contains(mouse)
        if inside {
            if hoverSince == nil { hoverSince = Date() }
            // A short dwell, so a pointer just passing by doesn't open the island.
            if !state.barHovering, Date().timeIntervalSince(hoverSince ?? Date()) >= 0.15 {
                setHover(true)
            }
        } else {
            hoverSince = nil
            if state.barHovering { setHover(false) }
        }
    }

    private func setHover(_ hovering: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            state.barHovering = hovering
        }
    }

    /// Whether the bar stays on screen between sessions (Settings → Shortcuts).
    private var staysVisibleWhenIdle: Bool { Prefs.showBarWhenIdle }

    func show() {
        hideWork?.cancel()
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            place(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    /// A session ended. A bar that lives on screen stays; otherwise fade out.
    func settle(after delay: TimeInterval) {
        guard !staysVisibleWhenIdle else { return }
        hide(after: delay)
    }

    /// Floating style: back to the default spot.
    func resetPosition() {
        anchor = nil
        Prefs.barAnchor = nil
        if let panel { place(panel) }
    }

    private func hide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let panel = self?.panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func applyPreferences() {
        let newStyle = Prefs.barStyle
        if newStyle != style {
            style = newStyle
            state.barStyle = newStyle
            if let panel { configure(panel) }
        }
        if let panel { place(panel) }
        if staysVisibleWhenIdle {
            show()
        } else if case .idle = state.phase {
            hide(after: 0)
        }
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        configure(panel)

        let host = HUDHostingController(state: state)
        host.sizingOptions = [.preferredContentSize]
        panel.contentViewController = host

        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.adjusting else { return }
                self.place(panel)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.adjusting, self.style == .floating else { return }
                let frame = panel.frame
                let screen = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main
                let fromTop = frame.midY > (screen?.frame.midY ?? 0)
                self.anchor = Prefs.BarAnchor(x: frame.midX, y: fromTop ? frame.maxY : frame.minY, fromTop: fromTop)
                Prefs.barAnchor = self.anchor
            }
        })
        return panel
    }

    private func configure(_ panel: NSPanel) {
        switch style {
        case .notch:
            // Above the menu bar, so the island can overlap the band beside the notch.
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            panel.isMovableByWindowBackground = false
        case .floating:
            panel.level = .statusBar
            panel.isMovableByWindowBackground = true
        }
    }

    /// Positions the window after any size change: hanging from the notch, or
    /// centered on the floating anchor.
    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        adjusting = true
        defer { adjusting = false }
        switch style {
        case .notch:
            let g = NotchGeometry.current()
            panel.setFrameOrigin(NSPoint(x: g.centerX - size.width / 2, y: g.screenFrame.maxY - size.height))
        case .floating:
            let anchor = self.anchor ?? defaultAnchor()
            self.anchor = anchor
            panel.setFrameOrigin(NSPoint(
                x: anchor.x - size.width / 2,
                y: anchor.fromTop ? anchor.y - size.height : anchor.y
            ))
        }
    }

    private func defaultAnchor() -> Prefs.BarAnchor {
        if let saved = Prefs.barAnchor,
           NSScreen.screens.contains(where: {
               $0.visibleFrame.insetBy(dx: 40, dy: 0).contains(CGPoint(x: saved.x, y: saved.y))
           }) {
            return saved
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return Prefs.BarAnchor(x: frame.midX, y: frame.maxY - 2, fromTop: true)
    }
}

/// Hosts the SwiftUI bar and reports hover with an always-active tracking area,
/// which works even though the panel never becomes the key window.
private final class HUDHostingController: NSHostingController<HUDRoot> {
    private let state: AppState

    init(state: AppState) {
        self.state = state
        super.init(rootView: HUDRoot(state: state))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    // Floating style only; the notch style tracks the pointer position instead.
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }

    private func setHover(_ hovering: Bool) {
        MainActor.assumeIsolated {
            guard state.barStyle == .floating else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.barHovering = hovering
            }
        }
    }
}

struct HUDRoot: View {
    let state: AppState
    var body: some View { HUDStyleSwitch().environmentObject(state) }
}

private struct HUDStyleSwitch: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if state.barStyle == .notch {
            NotchIslandView()
        } else {
            FloatingBarView()
        }
    }
}

