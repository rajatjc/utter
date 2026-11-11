import UtterCore
import AppKit
import Combine
import SwiftUI

/// The menu bar item. Left-click opens the Utter panel (a popover that sizes
/// itself to its content); right-click or Control-click shows a menu with
/// Settings, Mute and Quit, like other menu bar apps.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    func install(state: AppState) {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Utter"
        }

        let host = NSHostingController(rootView: MenuContent().environmentObject(state))
        host.sizingOptions = [.preferredContentSize] // the popover follows the content's height
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        updateIcon(state)
        observation = state.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the change: read the new value next turn.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.updateIcon(state) }
            }
        }
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func updateIcon(_ state: AppState) {
        let image: NSImage?
        if case .idle = state.phase, !state.isMuted {
            image = MenuBarIcon.image
        } else {
            image = NSImage(systemSymbolName: state.menuBarSymbol, accessibilityDescription: "Utter")
            image?.isTemplate = true
        }
        if item?.button?.image !== image { item?.button?.image = image }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        AppState.shared.refreshPermissions()
        NSApp.activate(ignoringOtherApps: true) // so a click elsewhere closes it
        AppState.shared.menuPanelOpen = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.menuPanelOpen = false }
    }

    private func showMenu(from button: NSStatusBarButton) {
        closePopover()
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            menu.addItem(entry)
        }
        add("Open Utter", #selector(openPanel))
        add("Settings…", #selector(openSettings), ",")
        add(AppState.shared.isMuted ? "Unmute" : "Mute", #selector(toggleMute))
        menu.addItem(.separator())
        add("Quit Utter", #selector(quit), "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openPanel() {
        if let button = item?.button { togglePopover(from: button) }
    }

    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func toggleMute() { AppState.shared.toggleMute() }
    @objc private func quit() { NSApp.terminate(nil) }
}
