import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.backgroundModeKey) private var backgroundMode = false
    @AppStorage(AppSettings.menuBarShowsKey) private var menuBarShows: MenuBarShows = .icon
    @State private var loginState = LoginItem.state
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Run in the background with a menu bar icon", isOn: $backgroundMode)
                Text("Closing the window keeps Sweeply running in the menu bar, so writes per day keep being recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Menu bar shows", selection: $menuBarShows) {
                    Text("Icon only").tag(MenuBarShows.icon)
                    Text("CPU temperature").tag(MenuBarShows.temperature)
                    Text("CPU usage").tag(MenuBarShows.usage)
                }
                .disabled(!backgroundMode)
            }
            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { loginState != .off },
                    set: { setLogin($0) }))
                if backgroundMode {
                    Text("Sweeply starts quietly in the menu bar, without opening its window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if loginState == .needsApproval {
                    HStack {
                        Text("Allow Sweeply in System Settings → General → Login Items.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text("Couldn't change the login item: \(loginError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: backgroundMode) { _, on in
            // Leaving background mode: bring the Dock icon back, so Sweeply can't end up invisible.
            if !on { NSApp.setActivationPolicy(.regular) }
        }
        .onAppear { loginState = LoginItem.state }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginState = LoginItem.state
    }
}
