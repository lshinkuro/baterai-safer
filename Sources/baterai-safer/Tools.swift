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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ToggleTile(title: "Notch", icon: "rectangle.topthird.inset.filled", theme: .violet, on: $t.notch)
                ToggleTile(title: "Tetap menyala", icon: "cup.and.saucer.fill", theme: .amber, on: $t.awake)
                ToggleTile(title: "File tersembunyi", icon: "eye.fill", theme: .electric, on: $t.hiddenFiles)
                ToggleTile(title: "Ikon desktop", icon: "menubar.dock.rectangle", theme: .mint, on: $t.desktopIcons)
            }
            Card(title: "Aksi cepat", icon: "bolt.fill") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    Action(title: "Dark / Light", icon: "circle.lefthalf.filled", color: Palette.indigo) { t.toggleDarkMode() }
                    Action(title: "Matikan layar", icon: "display", color: Palette.slate) { t.sleepDisplay() }
                    Action(title: "Screenshot", icon: "camera.viewfinder", color: Palette.pink) { t.screenshot() }
                    Action(title: "Activity Monitor", icon: "waveform.path.ecg", color: Palette.green) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                }
            }
            Card(title: "Shortcut notch", icon: "command") {
                ForEach(Array(HotKeys.bindings.enumerated()), id: \.offset) { i, b in
                    HStack {
                        Circle().fill(Palette.cycle[i % Palette.cycle.count]).frame(width: 7, height: 7)
                        Text(b.2?.title ?? "Buka / tutup notch").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Keycap(b.1)
                    }
                }
                Text("Esc menutup notch").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct Keycap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 12, weight: .bold, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.12)).frame(height: 2).padding(.horizontal, 1)
            }
    }
}
