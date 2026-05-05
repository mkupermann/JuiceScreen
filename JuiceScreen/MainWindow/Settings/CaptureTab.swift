import SwiftUI

struct CaptureTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                Picker("Image scale", selection: Binding(
                    get: { prefs.imageScale },
                    set: { newValue in prefs.imageScale = newValue; save() }
                )) {
                    Text("Native (Retina)").tag(ImageScale.retina)
                    Text("1× (smaller files)").tag(ImageScale.oneToOne)
                }
                .pickerStyle(.segmented)
                .help("Native preserves Retina resolution (typically 2× pixels). 1× downsamples to logical points.")
            } header: { Text("Resolution") }

            Section {
                Toggle("Include cursor in still captures", isOn: Binding(
                    get: { prefs.includeCursorInStills },
                    set: { newValue in prefs.includeCursorInStills = newValue; save() }
                ))
                .help("When on, the macOS cursor appears in PNG/JPG/PDF captures at the location it was when you triggered the capture. Off by default since cursors clutter screenshots.")
            } header: { Text("Cursor") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func save() {
        preferences.save(prefs)
    }
}
