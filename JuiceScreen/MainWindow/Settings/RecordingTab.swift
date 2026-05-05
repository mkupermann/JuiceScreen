import SwiftUI

struct RecordingTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                Picker("Target frame rate", selection: Binding(
                    get: { prefs.recordingOptions.targetFps },
                    set: { newValue in prefs.recordingOptions.targetFps = newValue; save() }
                )) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                .help("60 fps gives smoother motion at the cost of larger files. 30 fps is fine for most demos.")
            } header: { Text("Quality") }

            Section {
                Toggle("Capture system audio", isOn: Binding(
                    get: { prefs.recordingOptions.captureSystemAudio },
                    set: { newValue in prefs.recordingOptions.captureSystemAudio = newValue; save() }
                ))
                .help("Mix system audio (anything macOS routes through speakers/headphones) into the recording.")
                Toggle("Capture microphone", isOn: Binding(
                    get: { prefs.recordingOptions.captureMicrophone },
                    set: { newValue in prefs.recordingOptions.captureMicrophone = newValue; save() }
                ))
                .help("Adds a separate microphone track. macOS will prompt for Microphone permission the first time you record with this enabled.")
            } header: { Text("Audio") }

            Section {
                Toggle("Cursor highlight ring", isOn: Binding(
                    get: { prefs.recordingOptions.showCursorHighlight },
                    set: { newValue in prefs.recordingOptions.showCursorHighlight = newValue; save() }
                ))
                .help("Yellow ring around the cursor in the output video. No extra permissions required.")
                Toggle("Click pulse", isOn: Binding(
                    get: { prefs.recordingOptions.showClickPulse },
                    set: { newValue in prefs.recordingOptions.showClickPulse = newValue; save() }
                ))
                .help("Animated pulse at every click. Requires macOS Input Monitoring permission — will prompt the first time you enable.")
                Toggle("Show keystrokes", isOn: Binding(
                    get: { prefs.recordingOptions.showKeystrokes },
                    set: { newValue in prefs.recordingOptions.showKeystrokes = newValue; save() }
                ))
                .help("Last 3 keys typed appear in the bottom-right corner. Requires Input Monitoring.")
            } header: { Text("Overlays") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        preferences.save(prefs)
    }
}
