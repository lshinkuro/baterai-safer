import SwiftUI
import Charts
import CSMC

struct Sample: Codable {
    var t: Double
    var percent: Int
    var temp: Double?
    var watts: Double
}

final class Model: ObservableObject {
    @Published var battery = Battery.read()
    @Published var status = load(Paths.status, Status())
    @Published var config = load(Paths.config, Config()) {
        didSet { if config != oldValue { save(config, Paths.config); syncNative() } }
    }
    @Published var history = load(Paths.history, [Sample]())
    @Published var error = ""
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        record()
    }

    var helperInstalled: Bool { FileManager.default.fileExists(atPath: Paths.plist) }
    var helperRunning: Bool { Date().timeIntervalSince1970 - status.updated < 30 }

    func refresh() {
        battery = Battery.read()
        status = load(Paths.status, Status())
        syncNative()
        record()
    }

    // One sample per minute, last 24 hours, kept in the user's own Application Support.
    func record() {
        let now = Date().timeIntervalSince1970
        guard now - (history.last?.t ?? 0) >= 60 else { return }
        history = history.filter { now - $0.t < 86400 } + [Sample(t: now, percent: battery.percent, temp: battery.temp, watts: battery.watts)]
        try? FileManager.default.createDirectory(atPath: (Paths.history as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        save(history, Paths.history)
    }

    // The native limit lives in the user's session, so the app (not the root daemon) sets it.
    func syncNative() {
        guard !SMC.canInhibit, helperInstalled else { return }
        let t = nativeTarget(config, status)
        if native_limit_get() != t && native_limit_set(Int32(t)) != 0 { error = "Gagal set Charge Limit macOS ke \(t)%" }
    }

    func admin(_ cmd: String) {
        let bin = Daemon.stableBinary()
        let src = "do shell script \"'\(bin)' \(cmd) '\(NSUserName())'\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        error = err?[NSAppleScript.errorMessage] as? String ?? ""
        config = load(Paths.config, Config())
        refresh()
    }
}

struct BateraiApp: App {
    @StateObject private var m = Model()
    @StateObject private var sys = SystemModel()
    @StateObject private var cleaner = CleanerModel()
    @StateObject private var tools = ToolsModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // Before the .app bundle, settings lived in the executable-name domain; carry them over once.
        let d = UserDefaults.standard
        if Bundle.main.bundleIdentifier != nil, !d.bool(forKey: "migratedDomain"), let old = d.persistentDomain(forName: "baterai-safer") {
            // "notch" is skipped: people have been using the island in the bundled app since then.
            for (k, v) in old where d.object(forKey: k) == nil && k != "notch" { d.set(v, forKey: k) }
            d.set(true, forKey: "migratedDomain")
        }
        DispatchQueue.main.async { if UserDefaults.standard.object(forKey: "notch") as? Bool ?? true { Notch.shared.show() } }
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(m: m, sys: sys, cleaner: cleaner, tools: tools)
        } label: {
            Image(systemName: m.status.charging && m.battery.ac ? "battery.100percent.bolt"
                  : m.battery.ac ? "powerplug" : "battery.\(min(100, (m.battery.percent + 12) / 25 * 25))percent")
            Text("\(m.battery.percent)%")
        }
        .menuBarExtraStyle(.window)
    }
}

struct Panel: View {
    @ObservedObject var m: Model
    let sys: SystemModel, cleaner: CleanerModel, tools: ToolsModel
    @AppStorage("tab") private var tab = 0
    @AppStorage(FeatureFlags.key) private var featuresOff = "" // re-render when features change

    var body: some View {
        let theme = (Tab(rawValue: tab) ?? .battery).theme
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconBadge(icon: "bolt.shield.fill", color: Palette.green, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Baterai Safer").font(.system(size: 15, weight: .heavy, design: .rounded))
                    Text("\(m.battery.percent)% · \(m.battery.ac ? "dicas" : "pakai baterai")").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .heavy))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain).help("Keluar")
            }
            .padding(.horizontal, 16).padding(.top, 14)

            TabBar(tab: $tab, tabs: Tab.allCases.filter(\.enabled)).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)

            // Fixed panel size: the menu bar window doesn't resize cleanly between tabs of different heights.
            ScrollView {
                Group {
                    switch Tab(rawValue: tab).flatMap({ $0.enabled ? $0 : nil }) ?? .battery {
                    case .battery: BatteryTab(m: m)
                    case .system: SystemTab(s: sys)
                    case .cleaner: CleanerTab(c: cleaner)
                    case .tools: ToolsTab(t: tools)
                    }
                }
                .padding(16)
            }
            .id(tab) // each tab opens scrolled to the top
            .transition(.opacity)
        }
        .frame(width: 400, height: 620)
        .background(alignment: .top) {
            // The active tab's color glows behind the header.
            RadialGradient(colors: [theme.a.opacity(0.4), theme.b.opacity(0.12), .clear], center: .top, startRadius: 0, endRadius: 330)
                .frame(height: 330)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.4), value: tab)
        }
        .environment(\.accent, theme)
    }
}

struct BatteryTab: View {
    @ObservedObject var m: Model

    var stateText: String {
        let b = m.battery, s = m.status
        if !m.helperRunning { return "Helper belum aktif" }
        switch s.calibration {
        case 1: return "Kalibrasi: isi ke 100%"
        case 2: return "Kalibrasi: turunkan ke 10%"
        case 3: return "Kalibrasi: isi lagi ke 100%"
        default: break
        }
        if !b.ac { return "Pakai baterai" }
        if !s.adapter { return "Discharge" }
        return s.charging ? "Mengisi" : "Ditahan di batas"
    }

    var heroTheme: Theme {
        let b = m.battery
        if b.percent <= 20 && !b.ac { return .rose }
        if m.status.charging && b.ac { return .mint }
        return b.ac ? .electric : .amber
    }

    var limit: Int? { m.helperInstalled && m.config.enabled ? m.config.limit : nil }

    var body: some View {
        let b = m.battery
        VStack(spacing: 12) {
            Hero(theme: heroTheme) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        StatusPill(text: stateText)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(b.percent)").font(.system(size: 62, weight: .heavy, design: .rounded)).monospacedDigit()
                            Text("%").font(.system(size: 26, weight: .heavy, design: .rounded)).opacity(0.75)
                        }
                        .contentTransition(.numericText())
                        Group {
                            if let t = b.minutesLeft {
                                Text("\(t / 60)j \(t % 60)m \(b.charging ? "sampai penuh" : "tersisa")")
                            } else {
                                Text("\(b.maxCapacity * b.percent / 100) mAh tersimpan")
                            }
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded)).opacity(0.9)
                        if let a = b.adapterName {
                            Label(a, systemImage: "powerplug.fill").font(.system(size: 11, weight: .semibold)).opacity(0.75).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    BatteryGlyph(level: Double(b.percent) / 100, limit: limit.map { Double($0) / 100 }, charging: m.status.charging && b.ac)
                        .padding(.trailing, 10)
                }
            }

            HStack(spacing: 8) {
                Tile(icon: "heart.fill", title: "Kondisi", value: "\(b.health)%", color: Palette.pink, help: "\(b.maxCapacity)/\(b.designCapacity) mAh")
                Tile(icon: "arrow.triangle.2.circlepath", title: "Siklus", value: "\(b.cycles)", color: Palette.blue)
                Tile(icon: "thermometer.medium", title: "Suhu", value: b.temp.map { String(format: "%.1f°", $0) } ?? "–", color: Palette.orange)
                Tile(icon: "bolt.fill", title: "Daya", value: String(format: "%+.1fW", b.watts), color: Palette.amber)
            }

            Card(title: "Riwayat", icon: "chart.xyaxis.line") {
                HistoryChart(samples: m.history, limit: limit)
            }

            if !m.helperInstalled {
                Card(title: "Helper", icon: "lock.shield") {
                    Text("Helper (root) diperlukan untuk mengontrol pengisian.").font(.callout).foregroundStyle(.secondary)
                    Button("Install helper…") { m.admin("install-daemon") }.buttonStyle(.borderedProminent)
                }
            } else {
                Card(title: "Pengisian", icon: "bolt.batteryblock") {
                    Switch("Aktifkan limiter", "battery.100percent", $m.config.enabled, color: Palette.green)
                    HStack(spacing: 10) {
                        IconBadge(icon: "slider.horizontal.3", color: Palette.blue)
                        Text("Batas")
                        Slider(value: Binding(get: { Double(m.config.limit) }, set: { m.config.limit = Int($0) }),
                               in: SMC.canInhibit ? 50...100 : 80...100, step: 5)
                            .controlSize(.small)
                        Text("\(m.config.limit)%").font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    if SMC.canInhibit {
                        HStack(spacing: 10) {
                            IconBadge(icon: "water.waves", color: Palette.teal)
                            Stepper("Sailing \(m.config.limit - m.config.sailing)–\(m.config.limit)%", value: $m.config.sailing, in: 0...20)
                        }
                    } else {
                        Text("macOS 27: memakai Charge Limit bawaan (80–100%)").font(.caption).foregroundStyle(.secondary)
                    }
                    Switch("Top up ke 100% (sementara)", "arrow.up.to.line", $m.config.topUp, color: Palette.teal)
                    Switch("Auto discharge ke batas", "arrow.down.to.line", $m.config.autoDischarge, color: Palette.violet)
                }
                Card(title: "Proteksi", icon: "shield.lefthalf.filled") {
                    Switch(SMC.canInhibit ? "Heat protection" : "Heat protection (putus charger)", "flame.fill", $m.config.heatProtection, color: Palette.red)
                    if m.config.heatProtection {
                        HStack(spacing: 10) {
                            IconBadge(icon: "thermometer.high", color: Palette.orange)
                            Stepper(String(format: "Berhenti di ≥ %.0f °C", m.config.maxTemp), value: $m.config.maxTemp, in: 30...45)
                        }
                    }
                    Switch("Hentikan pengisian saat sleep", "moon.fill", $m.config.stopOnSleep, color: Palette.indigo)
                    HStack(spacing: 10) {
                        IconBadge(icon: "gauge.with.needle", color: Palette.slate)
                        Text("Kalibrasi 100 → 10 → 100%")
                        Spacer()
                        if m.status.calibration == 0 {
                            Button("Mulai") { m.config.calibrateAt = Date().timeIntervalSince1970 }.controlSize(.small)
                        } else {
                            Button("Batalkan") { m.config.calibrateAt = 0 }.controlSize(.small)
                        }
                    }
                }
            }

            if !m.error.isEmpty { Text(m.error).font(.caption).foregroundStyle(.red) }

            if m.helperInstalled {
                Button("Uninstall helper") { m.admin("uninstall-daemon") }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear { m.refresh() }
    }
}

struct HistoryChart: View {
    let samples: [Sample]
    let limit: Int?
    @Local private var metric = 0
    @Local private var hours = 6

    let metrics = [("Baterai", "%", Palette.green), ("Suhu", "°", Palette.orange), ("Daya", "W", Palette.blue)]

    func value(_ s: Sample) -> Double? { [Double(s.percent), s.temp, s.watts][metric] }

    var body: some View {
        let from = Date().addingTimeInterval(-Double(hours) * 3600)
        let pts = samples.filter { $0.t >= from.timeIntervalSince1970 }
            .compactMap { s in value(s).map { (date: Date(timeIntervalSince1970: s.t), v: $0) } }
        let vs = pts.map(\.v)
        let (name, unit, color) = metrics[metric]
        // percent is fixed 0–100; temp/power zoom to their range, power always includes 0
        let domain = metric == 0 ? 0...100.0
            : metric == 2 ? min(vs.min() ?? 0, 0) - 1...max(vs.max() ?? 0, 0) + 1
            : (vs.min() ?? 25) - 2...(vs.max() ?? 40) + 2

        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $metric) { ForEach(0..<3, id: \.self) { Text(metrics[$0].0).tag($0) } }
                Picker("", selection: $hours) { Text("1j").tag(1); Text("6j").tag(6); Text("24j").tag(24) }
                    .frame(width: 110)
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)

            Chart {
                ForEach(pts, id: \.date) { p in
                    AreaMark(x: .value("Waktu", p.date), yStart: .value(name, domain.lowerBound), yEnd: .value(name, p.v))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Waktu", p.date), y: .value(name, p.v))
                        .foregroundStyle(color).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if metric == 0, let limit {
                    RuleMark(y: .value("Batas", limit))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .leading) { Text("Batas \(limit)%").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .chartXScale(domain: from...Date())
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))\(unit)").font(.system(size: 9)) }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9))
                }
            }
            .frame(height: 130)
            .overlay {
                if pts.count < 2 {
                    Text("Mengumpulkan data… (1 titik per menit)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
