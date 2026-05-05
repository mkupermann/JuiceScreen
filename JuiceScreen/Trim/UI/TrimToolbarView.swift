import SwiftUI

struct TrimToolbarView: View {

    @Bindable var vm: TrimViewModel
    let onSaveTrim: () -> Void
    let onSaveTrimAs: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { vm.togglePlay() }) {
                Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help(vm.isPlaying ? "Pause" : "Play")

            Button(action: { vm.resetRange() }) {
                Label("Reset", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .help("Reset trim handles to full duration")

            Spacer()

            Text(rangeLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onSaveTrim) {
                Label("Save Trim", systemImage: "scissors")
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(vm.isExporting || !vm.range.isValid)

            Button(action: onSaveTrimAs) {
                Label("Save Trim As…", systemImage: "scissors.badge.ellipsis")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .buttonStyle(.bordered)
            .disabled(vm.isExporting || !vm.range.isValid)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rangeLabel: String {
        let start = formatTime(vm.range.start.seconds)
        let end = formatTime(vm.range.end.seconds)
        let dur = formatTime(vm.range.durationSeconds)
        return "\(start) → \(end)  •  \(dur)"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        let ms = Int((seconds - Double(total)) * 100)
        return String(format: "%02d:%02d.%02d", m, s, max(0, min(99, ms)))
    }
}
