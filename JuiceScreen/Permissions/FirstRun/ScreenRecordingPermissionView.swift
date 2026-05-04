import SwiftUI

struct ScreenRecordingPermissionView: View {

    let onGrant: () -> Void
    let onOpenSettings: () -> Void
    var onSkip: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Screen Recording permission needed")
                .font(.title3).fontWeight(.semibold)

            Text("JuiceScreen captures your screen using Apple's Screen Recording API. macOS requires you to grant permission once. After granting, you may need to relaunch the app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            HStack {
                Button("Open System Settings") { onOpenSettings() }
                Button("Grant Permission") { onGrant() }
                    .keyboardShortcut(.defaultAction)
            }

            if let onSkip {
                Button("Continue without (capture will not work)") { onSkip() }
                    .buttonStyle(.link)
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(width: 520, height: 320)
    }
}
