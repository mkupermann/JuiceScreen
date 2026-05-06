import SwiftUI
import AppKit

@MainActor
public final class SettingsWindow {

    private static var window: NSWindow?

    public static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JuiceScreen Settings"
        window.contentView = NSHostingView(rootView: SettingsContainer())
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.window = window
    }
}

/// Plain HStack: List sidebar on the left, the selected tab's body on the right.
/// Avoids `NavigationSplitView` and `TabView` (both rendered blank in some macOS
/// configurations when used outside the SwiftUI Settings scene).
private struct SettingsContainer: View {
    @State private var selection: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(.regularMaterial)

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SidebarRow(tab: tab, isSelected: tab == selection) {
                    selection = tab
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:   GeneralTab()
        case .capture:   CaptureTab()
        case .recording: RecordingTab()
        case .hotkeys:   HotkeysTab()
        case .storage:   StorageTab()
        case .about:     AboutTab()
        }
    }
}

private struct SidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Text(tab.title)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered  { return Color.primary.opacity(0.06) }
        return .clear
    }
}
