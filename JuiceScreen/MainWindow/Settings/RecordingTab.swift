import SwiftUI

struct RecordingTab: View {
    @State private var captureSystemAudio = VideoRecordingOptions.defaults.captureSystemAudio
    @State private var captureMicrophone = VideoRecordingOptions.defaults.captureMicrophone
    @State private var showCursorHighlight = VideoRecordingOptions.defaults.showCursorHighlight
    @State private var showClickPulse = VideoRecordingOptions.defaults.showClickPulse
    @State private var showKeystrokes = VideoRecordingOptions.defaults.showKeystrokes

    var body: some View {
        Form {
            Section {
                Toggle("Capture system audio", isOn: $captureSystemAudio)
                    .help("Mix system audio (anything macOS routes through speakers/headphones) into the recording.")
                Toggle("Capture microphone", isOn: $captureMicrophone)
                    .help("Adds a separate microphone track. macOS will prompt for Microphone permission the first time you record with this enabled.")
            } header: { Text("Audio") }
            Section {
                Toggle("Cursor highlight ring", isOn: $showCursorHighlight)
                    .help("Yellow ring around the cursor in the output video. No extra permissions required.")
                Toggle("Click pulse", isOn: $showClickPulse)
                    .help("Animated pulse at every click. Requires macOS Input Monitoring permission — will prompt the first time you enable.")
                Toggle("Show keystrokes", isOn: $showKeystrokes)
                    .help("Last 3 keys typed appear in the bottom-right corner. Requires Input Monitoring.")
            } header: { Text("Overlays") }
            Section {
                Text("Defaults shown above. User-configurable persistence is wired in v0.9 (settings completion). v0.6 always uses these defaults.")
                    .font(.footnote).foregroundStyle(.tertiary)
            } footer: { EmptyView() }
        }
        .formStyle(.grouped)
        .padding()
    }
}
