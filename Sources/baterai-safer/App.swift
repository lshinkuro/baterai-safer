import SwiftUI
import Charts
import CSMC
import ServiceManagement

/// One reading per day, kept for good: what a battery limiter is for, measured over months.
struct HealthDay: Codable, Equatable {
    var day: String          // yyyy-MM-dd, local
    var maxCapacity: Int     // mAh
    var designCapacity: Int
    var cycles: Int
    var health: Double { designCapacity > 0 ? Double(maxCapacity) * 100 / Double(designCapacity) : 0 }
    var date: Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
    }
}

/// Health change from the first to the last reading, and the days between; nil until two days are logged.
func healthTrend(_ log: [HealthDay]) -> (change: Double, days: Int)? {
    guard log.count >= 2, let a = log.first, let b = log.last, let d0 = a.date, let d1 = b.date else { return nil }
    return (b.health - a.health, max(1, Int((d1.timeIntervalSince(d0) / 86400).rounded())))
}

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
    @Published var healthLog = load(Model.healthFile, [HealthDay]())
    static let healthFile = Paths.user + "/health.json"
    @Published var error = ""
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        record()
    }

    var helperInstalled: Bool { FileManager.default.fileExists(atPath: Paths.plist) }
    var helperRunning: Bool { Date().timeIntervalSince1970 - status.updated < 30 }
    /// The binary launchd starts for the helper (the plist is world-readable).
    static var helperBinary: String? { (NSDictionary(contentsOfFile: Paths.plist)?["ProgramArguments"] as? [String])?.first }
    /// Installed but pointing at a binary that's gone, e.g. an old Homebrew "Baterai Safer" after moving to the DMG.
    static var helperBroken: Bool { FileManager.default.fileExists(atPath: Paths.plist) && helperBinary.map { !FileManager.default.fileExists(atPath: $0) } == true }
    var helperBroken: Bool { Self.helperBroken }

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
        // Once a day: health, cycles and capacity, for the long-term chart.
        let today = dayKey(Date())
        if battery.designCapacity > 0, healthLog.last?.day != today {
            healthLog.append(HealthDay(day: today, maxCapacity: battery.maxCapacity, designCapacity: battery.designCapacity, cycles: battery.cycles))
            save(healthLog, Model.healthFile)
        }
    }

    // The native limit lives in the user's session, so the app (not the root daemon) sets it.
    func syncNative() {
        guard !SMC.canInhibit, helperInstalled else { return }
        let t = nativeTarget(config, status)
        if native_limit_get() != t && native_limit_set(Int32(t)) != 0 { error = "Gagal set Charge Limit macOS ke \(t)%" }
    }

    func admin(_ cmd: String) {
        error = runAsAdmin(cmd)
        config = load(Paths.config, Config())
        refresh()
    }
}

/// Runs `poni <cmd> <user>` as root through the macOS admin prompt; returns the error, or "".
func runAsAdmin(_ cmd: String) -> String {
    let src = "do shell script \"'\(Daemon.stableBinary())' \(cmd) '\(NSUserName())'\" with administrator privileges"
    var err: NSDictionary?
    NSAppleScript(source: src)?.executeAndReturnError(&err)
    return err?[NSAppleScript.errorMessage] as? String ?? ""
}

struct BateraiApp: App {
    @StateObject private var m = Model()
    @StateObject private var sys = SystemModel()
    @StateObject private var cleaner = CleanerModel()
    @StateObject private var tools = ToolsModel.shared

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // Before the .app bundle, settings lived in the executable-name domain; carry them over once.
        let d = UserDefaults.standard
        if Bundle.main.bundleIdentifier != nil, !d.bool(forKey: "migratedDomain"), let old = d.persistentDomain(forName: "baterai-safer") {
            // "notch" is skipped: people have been using the island in the bundled app since then.
            for (k, v) in old where d.object(forKey: k) == nil && k != "notch" { d.set(v, forKey: k) }
            d.set(true, forKey: "migratedDomain")
        }
        // DMG installs have no `brew services`; start at login once (user can turn it off in Login Items).
        let homebrew = URL(fileURLWithPath: Bundle.main.bundlePath).resolvingSymlinksInPath().path.contains("/Cellar/")
        if Bundle.main.bundleIdentifier != nil, !homebrew, !d.bool(forKey: "loginItemRegistered") {
            try? SMAppService.mainApp.register()
            d.set(true, forKey: "loginItemRegistered")
        }
        DispatchQueue.main.async { if UserDefaults.standard.object(forKey: "notch") as? Bool ?? true { Notch.shared.show() } }
        DispatchQueue.main.async { Onboarding.showIfNeeded() }
        DispatchQueue.main.async { SelfCare.shared.start() } // idle until a reminder is switched on
        DispatchQueue.main.async { Updater.shared.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            Panel(m: m, sys: sys, cleaner: cleaner, tools: tools)
        } label: {
            MenuLabel(m: m)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var m: Model
    @AppStorage(FeatureFlags.key) private var featuresOff = "" // re-render when the percent switch changes

    var body: some View {
        Image(nsImage: .poni)
        if FeatureFlags.isOn("menuPercent") { Text("\(m.battery.percent)%") }
    }
}

struct Panel: View {
    @ObservedObject var m: Model
    let sys: SystemModel, cleaner: CleanerModel, tools: ToolsModel
    @AppStorage("tab") private var tab = 0
    @AppStorage(FeatureFlags.key) private var featuresOff = "" // re-render when features change
    @AppStorage("accent") private var accentID = "mint"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Poni").font(.system(size: 15, weight: .semibold))
                    Text("\(m.battery.percent)% · \(tr(m.battery.ac ? "dicas" : "pakai baterai"))").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { if confirm("Keluar dari Poni?", "Notch dan menu bar ditutup. Batas pengisian tetap berjalan lewat helper.", "Keluar") { NSApp.terminate(nil) } } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain).tip("Keluar")
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
        .id(accentID) // rebuild everything in the new accent
        .frame(width: 400, height: 620)
        .background(alignment: .top) {
            // A faint accent wash behind the header.
            RadialGradient(colors: [Palette.accent.opacity(0.1), .clear], center: .top, startRadius: 0, endRadius: 330)
                .frame(height: 330)
                .allowsHitTesting(false)
        }
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

    /// Mint when healthy or charging, amber when getting low, red when critical.
    var tone: Color {
        let b = m.battery
        if b.ac || b.percent > 40 { return Palette.accent }
        return b.percent > 20 ? Palette.amber : Palette.red
    }

    var limit: Int? { m.helperInstalled && m.config.enabled ? m.config.limit : nil }

    var helperProblem: String {
        let since = m.status.updated > 0 ? Date(timeIntervalSince1970: m.status.updated).formatted(.dateTime.day().month(.wide).hour().minute().locale(appLocale)) : "?"
        let cause = m.helperBroken
            ? String(format: tr("Sejak %@ helper menunjuk ke Poni versi lama yang sudah dihapus."), since)
            : String(format: tr("Helper tidak merespons sejak %@."), since)
        // macOS 27+: the app sets the native Charge Limit itself, so the limit holds; only helper features stop.
        let effect = SMC.canInhibit
            ? tr("Baterai diisi tanpa batas.")
            : String(format: tr("Charge Limit macOS masih menahan di %@%%, tapi auto discharge, kalibrasi, proteksi panas, dan berhenti saat sleep tidak berjalan."), "\(nativeTarget(m.config, m.status))")
        return cause + " " + effect + " " + tr("Pasang ulang helper supaya memakai versi ini (minta password admin).")
    }

    var body: some View {
        let b = m.battery
        VStack(spacing: 12) {
            Hero(theme: Theme(a: tone, b: tone)) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        if m.helperInstalled && !m.helperRunning {
                            Button { m.admin("install-daemon") } label: {
                                StatusPill(text: m.helperBroken ? "Helper perlu dipasang ulang" : "Helper mati · Jalankan ulang", color: Palette.red)
                            }
                            .buttonStyle(.plain).help("Pasang ulang helper (minta password admin)")
                        } else {
                            StatusPill(text: stateText)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(b.percent)").font(.system(size: 62, weight: .semibold)).monospacedDigit()
                            Text("%").font(.system(size: 26, weight: .semibold)).foregroundStyle(tone)
                        }
                        .contentTransition(.numericText())
                        Group {
                            if let t = b.minutesLeft {
                                Text(b.charging ? "\(t / 60)j \(t % 60)m sampai penuh" : "\(t / 60)j \(t % 60)m tersisa")
                            } else {
                                Text("\(b.maxCapacity * b.percent / 100) mAh tersimpan")
                            }
                        }
                        .font(.system(size: 13, weight: .bold)).opacity(0.9)
                        if let a = b.adapterName {
                            Label(a, systemImage: "powerplug.fill").font(.system(size: 11, weight: .semibold)).opacity(0.75).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    BatteryGlyph(level: Double(b.percent) / 100, limit: limit.map { Double($0) / 100 }, charging: m.status.charging && b.ac, color: tone)
                        .padding(.trailing, 10)
                }
            }

            if m.helperInstalled && !m.helperRunning {
                Card(title: SMC.canInhibit ? "Batas pengisian tidak berjalan" : "Helper tidak berjalan", icon: "exclamationmark.triangle.fill") {
                    Text(helperProblem).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Pasang ulang helper…") { m.admin("install-daemon") }.buttonStyle(.borderedProminent).tint(Palette.accent)
                }
            }

            HStack(spacing: 8) {
                Tile(icon: "heart.fill", title: "Kondisi", value: "\(b.health)%", tone: b.health >= 80 ? Palette.accent : b.health >= 60 ? Palette.amber : Palette.red, fraction: Double(b.health) / 100, help: "\(b.maxCapacity)/\(b.designCapacity) mAh")
                Tile(icon: "arrow.triangle.2.circlepath", title: "Siklus", value: "\(b.cycles)", tone: b.cycles < 800 ? Palette.accent : Palette.amber,
                     fraction: Double(b.cycles) / 1000, help: "Baterai Mac dirancang untuk 1000 siklus")
                Tile(icon: "thermometer.medium", title: "Suhu", value: b.temp.map { String(format: "%.1f°", $0) } ?? "–",
                     tone: b.temp.map { $0 < 35 ? Palette.accent : $0 < 40 ? Palette.amber : Palette.red }, fraction: b.temp.map { ($0 - 20) / 25 })
                Tile(icon: "bolt.fill", title: b.watts < 0 ? "Daya keluar" : "Daya masuk", value: String(format: "%.1f W", abs(b.watts)), tone: b.watts < 0 ? Palette.amber : Palette.accent,
                     fraction: abs(b.watts) / 60, help: "Bar: 0–60 W")
            }

            Card(title: "Riwayat", icon: "chart.xyaxis.line") {
                HistoryChart(samples: m.history, limit: limit)
            }

            Card(title: "Kesehatan jangka panjang", icon: "heart.text.square") {
                HealthChart(log: m.healthLog)
            }

            if !m.helperInstalled {
                Card(title: "Helper", icon: "lock.shield") {
                    Text("Helper (root) diperlukan untuk mengontrol pengisian.").font(.callout).foregroundStyle(.secondary)
                    Button("Install helper…") { m.admin("install-daemon") }.buttonStyle(.borderedProminent)
                }
            } else {
                Card(title: "Pengisian", icon: "bolt.batteryblock") {
                    Switch("Aktifkan limiter", "battery.100percent", $m.config.enabled)
                    HStack(spacing: 10) {
                        IconBadge(icon: "slider.horizontal.3")
                        Text("Batas")
                        Slider(value: Binding(get: { Double(m.config.limit) }, set: { m.config.limit = Int($0) }),
                               in: SMC.canInhibit ? 50...100 : 80...100, step: 5)
                            .controlSize(.small)
                        Text("\(m.config.limit)%").font(.system(.body).weight(.semibold)).monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    if SMC.canInhibit {
                        HStack(spacing: 10) {
                            IconBadge(icon: "water.waves")
                            Stepper("Sailing \(m.config.limit - m.config.sailing)–\(m.config.limit)%", value: $m.config.sailing, in: 0...20)
                        }
                    } else {
                        Text("macOS 27: memakai Charge Limit bawaan (80–100%)").font(.caption).foregroundStyle(.secondary)
                    }
                    Switch("Top up ke 100% (sementara)", "arrow.up.to.line", $m.config.topUp)
                    Switch("Auto discharge ke batas", "arrow.down.to.line", $m.config.autoDischarge)
                }
                Card(title: "Proteksi", icon: "shield.lefthalf.filled") {
                    if SMC.canInhibit {
                        Switch("Heat protection", "flame.fill", $m.config.heatProtection)
                    }
                    if SMC.canInhibit && m.config.heatProtection {
                        HStack(spacing: 10) {
                            IconBadge(icon: "thermometer.high")
                            Stepper(String(format: "Berhenti di ≥ %.0f °C", m.config.maxTemp), value: $m.config.maxTemp, in: 30...45)
                        }
                    }
                    Switch("Hentikan pengisian saat sleep", "moon.fill", $m.config.stopOnSleep)
                    HStack(spacing: 10) {
                        IconBadge(icon: "gauge.with.needle")
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

            if !m.error.isEmpty { Text(m.error).font(.caption).foregroundStyle(Palette.red) }

            if m.helperInstalled {
                Button("Uninstall helper") { m.admin("uninstall-daemon") }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onAppear { m.refresh() }
    }
}

struct HealthChart: View {
    let log: [HealthDay]

    var body: some View {
        if log.count < 2 {
            Text(tr("Kesehatan baterai dicatat sekali sehari mulai hari ini. Grafiknya muncul besok dan makin berguna setelah beberapa minggu."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } else {
            let hs = log.map(\.health), low = (hs.min() ?? 80).rounded(.down)
            VStack(alignment: .leading, spacing: 8) {
                if let t = healthTrend(log), let first = log.first, let last = log.last {
                    // Tone by how fast it drops: about 0.5%/month or less is normal wear.
                    let perMonth = -t.change / Double(t.days) * 30
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f%%", last.health)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        Text(String(format: tr("%@ dalam %@ hari · %@ siklus"), String(format: "%+.1f%%", t.change), "\(t.days)", "\(last.cycles - first.cycles)"))
                            .font(.system(size: 11)).foregroundStyle(perMonth > 1.5 ? Palette.amber : .secondary)
                    }
                }
                Chart(log.compactMap { d in d.date.map { (date: $0, health: d.health) } }, id: \.date) { d in
                    LineMark(x: .value("Hari", d.date), y: .value("%", d.health))
                        .foregroundStyle(Palette.accent).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                .chartYScale(domain: max(0, low - 2)...100)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(appLocale)).font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))%").font(.system(size: 9)) }
                    }
                }
                .frame(height: 110)
            }
        }
    }
}

struct HistoryChart: View {
    let samples: [Sample]
    let limit: Int?
    @Local private var metric = 0
    @Local private var hours = 6

    let metrics = [("Baterai", "%"), ("Suhu", "°"), ("Daya", "W")]

    /// Vertical color scale over the plot: battery is good high, temperature good low, power mint when charging.
    func scale(_ domain: ClosedRange<Double>) -> LinearGradient {
        let at = { (v: Double) in min(max((v - domain.lowerBound) / (domain.upperBound - domain.lowerBound), 0), 1) }
        let stops: [(Color, Double)] = switch metric {
        case 0: [(Palette.red, 0), (Palette.red, at(20)), (Palette.amber, at(30)), (Palette.amber, at(40)), (Palette.accent, at(55)), (Palette.accent, 1)]
        case 1: [(Palette.accent, 0), (Palette.accent, at(34)), (Palette.amber, at(37)), (Palette.red, at(42)), (Palette.red, 1)]
        default: [(Palette.amber, 0), (Palette.amber, at(0)), (Palette.accent, at(0)), (Palette.accent, 1)]
        }
        return LinearGradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) }, startPoint: .bottom, endPoint: .top)
    }

    func value(_ s: Sample) -> Double? { [Double(s.percent), s.temp, s.watts][metric] }

    var body: some View {
        let from = Date().addingTimeInterval(-Double(hours) * 3600)
        let pts = samples.filter { $0.t >= from.timeIntervalSince1970 }
            .compactMap { s in value(s).map { (date: Date(timeIntervalSince1970: s.t), v: $0) } }
        let vs = pts.map(\.v)
        let (name, unit) = metrics[metric]
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
                        .foregroundStyle(scale(domain)).opacity(0.16)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Waktu", p.date), y: .value(name, p.v))
                        .foregroundStyle(scale(domain)).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                if metric == 0, let limit {
                    RuleMark(y: .value("Batas", limit))
                        .foregroundStyle(Color.gray).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
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
