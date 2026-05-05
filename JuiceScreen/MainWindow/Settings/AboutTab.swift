import SwiftUI

struct AboutTab: View {
    private let preferences: PreferencesStore
    @State private var prefs: Preferences
    @State private var lastCheckedDisplay: String

    private let updater: SparkleUpdater

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        let initial = preferences.load()
        _prefs = State(initialValue: initial)
        _lastCheckedDisplay = State(initialValue: Self.format(initial.updateLastCheckedAt))
        self.updater = SparkleUpdater(preferences: preferences)
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("JuiceScreen")
                .font(.title)
                .fontWeight(.semibold)

            Text("Version \(version) (\(build))")
                .foregroundStyle(.secondary)

            Text("Open-source, 100% local screen capture for macOS.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/mkupermann/JuiceScreen")!)
                Link("MIT License", destination: URL(string: "https://github.com/mkupermann/JuiceScreen/blob/main/LICENSE")!)
            }
            .padding(.top, 8)

            Divider().padding(.vertical, 8)

            VStack(spacing: 8) {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { prefs.updateAutoCheckEnabled },
                    set: { newValue in
                        prefs.updateAutoCheckEnabled = newValue
                        preferences.save(prefs)
                        updater.isAutomaticChecksEnabled = newValue
                    }
                ))
                .toggleStyle(.switch)

                Button("Check for Updates Now") {
                    updater.checkNow()
                    // Refresh display after Sparkle's UI dismisses.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        prefs = preferences.load()
                        lastCheckedDisplay = Self.format(prefs.updateLastCheckedAt)
                    }
                }
                .controlSize(.large)

                Text("Last checked: \(lastCheckedDisplay)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 360)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
