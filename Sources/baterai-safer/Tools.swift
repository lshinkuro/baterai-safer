import SwiftUI
import IOKit.pwr_mgt

func finderBool(_ key: String, _ fallback: Bool) -> Bool {
    UserDefaults(suiteName: "com.apple.finder")?.object(forKey: key) as? Bool ?? fallback
}

final class ToolsModel: ObservableObject {
    @Published var notch = UserDefaults.standard.object(forKey: "notch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notch, forKey: "notch"); notch ? Notch.shared.show() : Notch.shared.hide() }
    }
    @Published var awake = false { didSet { if awake != oldValue { setAwake() } } }
    @Published var hiddenFiles = finderBool("AppleShowAllFiles", false) { didSet { setFinder("AppleShowAllFiles", hiddenFiles) } }
    @Published var desktopIcons = finderBool("CreateDesktop", true) { didSet { setFinder("CreateDesktop", desktopIcons) } }
    private var assertion = IOPMAssertionID(0)

    private func setAwake() {
        if awake {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Baterai Safer: tetap menyala" as CFString, &assertion)
        } else {
            IOPMAssertionRelease(assertion)
        }
    }

    private func setFinder(_ key: String, _ on: Bool) {
        sh("/usr/bin/defaults", "write", "com.apple.finder", key, "-bool", on ? "true" : "false")
        sh("/usr/bin/killall", "Finder")
    }

    func toggleDarkMode() {
        sh("/usr/bin/osascript", "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
    }

    func sleepDisplay() { sh("/usr/bin/pmset", "displaysleepnow") }

    func screenshot() {
        // Interactive area capture to the clipboard; runs off the main thread while the user selects.
        DispatchQueue.global().async { sh("/usr/sbin/screencapture", "-ic") }
    }
}

struct ToolsTab: View {
    @ObservedObject var t: ToolsModel

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Mode", icon: "switch.2") {
                HStack(spacing: 8) {
                    ToggleTile(title: "Notch", icon: "rectangle.topthird.inset.filled", color: .purple, on: $t.notch)
                    ToggleTile(title: "Tetap menyala", icon: "cup.and.saucer.fill", color: .orange, on: $t.awake)
                    ToggleTile(title: "File tersembunyi", icon: "eye.fill", color: .blue, on: $t.hiddenFiles)
                    ToggleTile(title: "Ikon desktop", icon: "menubar.dock.rectangle", color: .green, on: $t.desktopIcons)
                }
            }
            Card(title: "Shortcut notch", icon: "keyboard") {
                ForEach(HotKeys.bindings, id: \.1) { b in
                    HStack {
                        Text(b.2?.title ?? "Buka / tutup notch")
                        Spacer()
                        Text(b.1).font(.system(.callout, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Text("Esc menutup notch.").font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "Aksi cepat", icon: "bolt") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    Action(title: "Dark / Light", icon: "circle.lefthalf.filled", color: .indigo) { t.toggleDarkMode() }
                    Action(title: "Matikan layar", icon: "display", color: .gray) { t.sleepDisplay() }
                    Action(title: "Screenshot area", icon: "camera.viewfinder", color: .pink) { t.screenshot() }
                    Action(title: "Activity Monitor", icon: "waveform.path.ecg", color: .green) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                }
            }
        }
    }
}
