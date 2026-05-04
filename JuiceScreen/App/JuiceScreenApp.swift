import SwiftUI

@main
struct JuiceScreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Empty scene — UI is owned by AppDelegate (menu bar + on-demand windows).
        // Settings { EmptyView() } would show a Settings menu item in a regular app;
        // we use a custom SettingsWindow instead, so we use an empty Settings scene.
        Settings { EmptyView() }
    }
}
