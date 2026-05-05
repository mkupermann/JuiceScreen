import AppKit
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        _prefs = State(initialValue: preferences.load())
    }

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: Binding(
                    get: { prefs.startAtLogin },
                    set: { newValue in prefs.startAtLogin = newValue; applyStartAtLogin(newValue); save() }
                ))
                .help("Adds JuiceScreen to login items so it launches when you sign in.")
            } header: { Text("Launch") }

            Section {
                HStack {
                    Text("Save folder")
                    Spacer()
                    Text(prefs.saveDirectory.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseSaveDirectory() }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([prefs.saveDirectory])
                }
            } header: { Text("Save location") }

            Section {
                Picker("Default format", selection: Binding(
                    get: { prefs.defaultStillFormat },
                    set: { newValue in prefs.defaultStillFormat = newValue; save() }
                )) {
                    Text("PNG (lossless)").tag(StillImageFormat.png)
                    Text("JPG (smaller)").tag(StillImageFormat.jpg)
                }
                .pickerStyle(.segmented)
                if prefs.defaultStillFormat == .jpg {
                    HStack {
                        Text("JPG quality")
                        Slider(value: Binding(
                            get: { prefs.jpegQuality },
                            set: { newValue in prefs.jpegQuality = newValue; save() }
                        ), in: 0.5 ... 1.0, step: 0.05)
                        Text(String(format: "%.0f%%", prefs.jpegQuality * 100))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            } header: { Text("Default still format") }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = prefs.saveDirectory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.saveDirectory = url
            save()
        }
    }

    private func applyStartAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLog.logger(category: "Settings").error("Login item toggle failed: \(String(describing: error))")
        }
    }

    private func save() {
        preferences.save(prefs)
    }
}
