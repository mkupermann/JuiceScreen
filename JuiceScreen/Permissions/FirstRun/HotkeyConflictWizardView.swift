import SwiftUI

struct HotkeyConflictWizardView: View {

    let onOpenKeyboardSettings: () -> Void
    let onUseAlternativeDefaults: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Hotkey conflict with macOS")
                .font(.title3).fontWeight(.semibold)

            Text("JuiceScreen wants to use ⌘⇧3, ⌘⇧4, and ⌘⇧5 for its capture and record shortcuts. macOS already uses these for the built-in screenshot tool.")
                .foregroundStyle(.secondary)

            Text("To let JuiceScreen claim them, open Keyboard Settings → Shortcuts → Screenshots and uncheck the conflicting items. You can also keep the alternative defaults below — JuiceScreen will use a different combo and the system shortcuts continue to work.")
                .foregroundStyle(.secondary)

            HStack {
                Button("Skip") { onSkip() }
                Spacer()
                Button("Use alternative defaults") { onUseAlternativeDefaults() }
                Button("Open Keyboard Settings") { onOpenKeyboardSettings() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 560)
    }
}
