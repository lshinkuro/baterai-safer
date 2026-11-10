import SwiftUI
import IOKit.pwr_mgt
import UniformTypeIdentifiers

func finderBool(_ key: String, _ fallback: Bool) -> Bool {
    UserDefaults(suiteName: "com.apple.finder")?.object(forKey: key) as? Bool ?? fallback
}

final class ToolsModel: ObservableObject {
    static let shared = ToolsModel() // menu bar and the notch's Lainnya tab share one sleep assertion
    @Published var notch = UserDefaults.standard.object(forKey: "notch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notch, forKey: "notch"); notch ? Notch.shared.show() : Notch.shared.hide() }
    }
    @Published var awake = false { didSet { if awake != oldValue { setAwake() } } }
    @Published var awakeUntil: Date?        // nil while awake = until turned off
    private var awakeTimer: Timer?
    @Published var hiddenFiles = finderBool("AppleShowAllFiles", false) { didSet { setFinder("AppleShowAllFiles", hiddenFiles) } }
    @Published var desktopIcons = finderBool("CreateDesktop", true) { didSet { setFinder("CreateDesktop", desktopIcons) } }
    private var assertion = IOPMAssertionID(0)

    /// Keep awake for `minutes`, until `until`, or (both nil) until turned off; ends on its own.
    func keepAwake(minutes: Int? = nil, until: Date? = nil) {
        awakeTimer?.invalidate()
        awakeUntil = until ?? minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        awake = true
        if let end = awakeUntil {
            awakeTimer = Timer.scheduledTimer(withTimeInterval: max(1, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                self?.awake = false
                Notch.shared.flash("Mode tetap menyala selesai")
            }
        }
    }

    private func setAwake() {
        if !awake { awakeTimer?.invalidate(); awakeUntil = nil }
        if awake {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Poni: tetap menyala" as CFString, &assertion)
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
    @AppStorage(FeatureFlags.key) private var featuresOff = ""
    @AppStorage("notchClick") private var notchClick = true
    @AppStorage(NTab.orderKey) private var tabOrder = ""
    @Local private var draggingTab: NTab?
    @AppStorage("accent") private var accentID = "mint"

    func feature(_ id: String) -> Binding<Bool> {
        Binding(get: { FeatureFlags.isOn(id) }, set: { FeatureFlags.set(id, $0); Notch.shared.applyFeatures() })
    }

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ToggleTile(title: "Notch", icon: "rectangle.topthird.inset.filled", on: $t.notch)
                ToggleTile(title: "Tetap menyala", icon: "cup.and.saucer.fill", on: $t.awake)
                if !Lite.on {
                    ToggleTile(title: "File tersembunyi", icon: "eye.fill", on: $t.hiddenFiles)
                    ToggleTile(title: "Ikon desktop", icon: "menubar.dock.rectangle", on: $t.desktopIcons)
                }
            }
            Card(title: "Tampilan", icon: "paintpalette") {
                HStack(spacing: 10) {
                    ForEach(Palette.accents, id: \.id) { a in
                        Button { Palette.setAccent(a.id); accentID = a.id } label: {
                            Circle().fill(a.color).frame(width: 26, height: 26)
                                .overlay { if a.id == accentID { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.onAccent) } }
                                .padding(3)
                                .overlay(Circle().strokeBorder(a.id == accentID ? Color.primary.opacity(0.5) : .clear, lineWidth: 1.5))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain).tip(a.name)
                    }
                }
                HuePicker(current: Palette.customHue(accentID)) { h in
                    let id = String(format: "hue:%.3f", h)
                    Palette.setAccent(id); accentID = id
                }
                Text("Warna aksen untuk tab aktif, tombol, toggle, dan grafik.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Card(title: "Fitur", icon: "switch.2") {
                Text("Matikan yang tidak dipakai: tab-nya hilang dan proses latarnya berhenti.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Notch").font(.system(size: 11, weight: .bold))
                HStack {
                    Text("Buka notch").font(.system(size: 11))
                    Spacer()
                    Picker("", selection: $notchClick) { Text("Hover").tag(false); Text("Klik").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(NTab.ordered, id: \.self) { tab in
                        FeatureChip(title: tab.title, icon: tab.icon, on: feature("\(tab)"))
                            .onDrag { draggingTab = tab; return NSItemProvider(object: "\(tab)" as NSString) }
                            .onDrop(of: [.plainText], delegate: TabDrop(target: tab, dragging: $draggingTab))
                            .accessibilityAction(named: tr("Geser ke kiri")) { tab.move(by: -1) } // VoiceOver can't drag
                            .accessibilityAction(named: tr("Geser ke kanan")) { tab.move(by: 1) }
                    }
                    FeatureChip(title: "Join rapat", icon: "video.fill", on: feature("meeting"))
                    if !Lite.on { FeatureChip(title: "Token AI β", icon: "chart.bar.fill", on: feature("ailab")) }
                }
                .disabled(!t.notch).opacity(t.notch ? 1 : 0.45)
                Text("Seret untuk mengatur urutan tab").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Menu bar").font(.system(size: 11, weight: .bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    if !Lite.on {
                        FeatureChip(title: "Sistem", icon: Tab.system.icon, on: feature("panel.system"))
                        FeatureChip(title: "Cleaner", icon: Tab.cleaner.icon, on: feature("panel.cleaner"))
                    }
                    FeatureChip(title: "Persen", icon: "percent", on: feature("menuPercent"))
                }
            }
            Card(title: "Aksi cepat", icon: "bolt.fill") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    if !Lite.on { // these run system tools the sandbox blocks
                        Action(title: "Gelap / Terang", icon: "circle.lefthalf.filled") { t.toggleDarkMode() }
                        Action(title: "Matikan layar", icon: "display") { t.sleepDisplay() }
                        Action(title: "Tangkapan layar", icon: "camera.viewfinder") { t.screenshot() }
                        Action(title: "Teks dari layar", icon: "text.viewfinder") { Notch.shared.ocr() }
                    }
                    Action(title: "Panduan awal", icon: "sparkles") { Onboarding.show() }
                    Action(title: "Activity Monitor", icon: "waveform.path.ecg") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                }
            }
            if !Lite.on { UpdateCard() }
        }
    }
}

/// Dropping onto a chip in the feature list: the dragged tab takes its place as the pointer passes.
struct TabDrop: DropDelegate {
    let target: NTab
    @Binding var dragging: NTab?

    func validateDrop(info: DropInfo) -> Bool { dragging != nil } // text dragged in from elsewhere isn't a tab
    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        withAnimation(Motion.snap) { d.place(at: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// Compact on/off pill for a feature.
struct FeatureChip: View {
    let title: String, icon: String
    @Binding var on: Bool

    var body: some View {
        Button { withAnimation(Motion.ease) { on.toggle() } } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(tr(title)).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark" : "xmark").font(.system(size: 9, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(on ? Palette.onAccent : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(0.05)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(on ? "Klik untuk mematikan \(title)" : "Klik untuk menyalakan \(title)")
    }
}

/// Any hue as the accent. Commits when the drag ends: changing the accent rebuilds the views, which would cancel the drag.
struct HuePicker: View {
    let current: Double?
    let pick: (Double) -> Void
    @Local private var dragging: Double?

    var body: some View {
        let hue = dragging ?? current
        HStack(spacing: 10) {
            Text("Kustom").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            GeometryReader { geo in
                let spot = { (x: CGFloat) in Double(min(1, max(0, x / geo.size.width))) }
                Capsule().fill(LinearGradient(colors: stride(from: 0.0, through: 1, by: 1.0 / 12).map(Palette.custom), startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10).frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        if let hue {
                            Circle().fill(Palette.custom(hue)).frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5))
                                .offset(x: CGFloat(hue) * (geo.size.width - 20))
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragging = spot($0.location.x) }
                        .onEnded { pick(spot($0.location.x)); dragging = nil })
            }
            .frame(height: 20)
        }
        .accessibilityElement()
        .accessibilityLabel(tr("Warna kustom"))
        .accessibilityValue(hue.map { "\(Int($0 * 360))°" } ?? "")
        .accessibilityAdjustableAction { d in
            let step = d == .increment ? 0.05 : -0.05
            pick(min(1, max(0, (current ?? 0) + step)))
        }
    }
}
