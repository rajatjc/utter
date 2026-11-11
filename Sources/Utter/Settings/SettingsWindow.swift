import UtterCore
import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case setup, claude, vocabulary, history, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: "Get started"
        case .claude: "AI & dictation"
        case .vocabulary: "Vocabulary"
        case .history: "History"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .setup: "sparkles"
        case .claude: "brain"
        case .vocabulary: "character.book.closed"
        case .history: "clock.arrow.circlepath"
        case .shortcuts: "keyboard"
        }
    }
}

final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var page: SettingsPage = .setup
}

/// A plain window: SwiftUI's Settings scene is unreliable in menu-bar-only apps.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(page: SettingsPage? = nil) {
        if let page { SettingsRouter.shared.page = page }
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Utter"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView().environmentObject(AppState.shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
                .background(VisualEffect(material: .sidebar))
            ScrollView {
                SettingsPageView(page: router.page)
                    .padding(.horizontal, 32)
                    .padding(.top, 40)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 780, height: 560)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Orb(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Utter").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("v0.1 draft").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 8)
            .padding(.top, 48)
            .padding(.bottom, 18)

            ForEach(SettingsPage.allCases) { item in
                SidebarItem(page: item, selected: router.page == item, badge: badge(for: item)) {
                    router.page = item
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private func badge(for page: SettingsPage) -> String? {
        page == .setup && state.setupStepsDone < 4 ? "\(state.setupStepsDone)/4" : nil
    }
}

/// The content of one settings page (also rendered on its own by Snapshots).
struct SettingsPageView: View {
    let page: SettingsPage

    var body: some View {
        switch page {
        case .setup: SetupPage()
        case .claude: AIPage()
        case .vocabulary: VocabularyPage()
        case .history: HistoryPage()
        case .shortcuts: ShortcutsPage()
        }
    }
}

private struct SidebarItem: View {
    let page: SettingsPage
    let selected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                Text(page.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Theme.magenta.opacity(0.2)))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.magenta))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.violet, Theme.magenta], startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 6)
    }
}

