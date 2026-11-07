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

    init() { NSApplication.shared.setActivationPolicy(.accessory) }

    var body: some Scene {
        MenuBarExtra {
            Panel(m: m)
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
        if !s.adapter { return "Discharge (charger diabaikan)" }
        return s.charging ? "Mengisi" : "Ditahan — pakai daya charger"
    }

    var tint: Color {
        let b = m.battery
        if b.percent <= 20 && !b.ac { return .red }
        if m.status.charging && b.ac { return .green }
        return b.ac ? .blue : .orange
    }

    var timeText: String? {
        guard let t = m.battery.minutesLeft else { return nil }
        let d = "\(t / 60)j \(t % 60)m"
        return m.battery.charging ? "Penuh dalam \(d)" : "Sisa \(d)"
    }

    var body: some View {
        let b = m.battery
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Ring(percent: b.percent, limit: m.helperInstalled && m.config.enabled ? m.config.limit : nil, color: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baterai Safer").font(.headline)
                    Label(stateText, systemImage: "circle.fill")
                        .font(.callout).foregroundStyle(tint).labelStyle(Dot())
                    if let t = timeText { Text(t).font(.caption).foregroundStyle(.secondary) }
                    if let a = b.adapterName { Label(a, systemImage: "powerplug").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Tile(icon: "heart", title: "Kondisi", value: "\(b.health)%", help: "\(b.maxCapacity)/\(b.designCapacity) mAh")
                Tile(icon: "arrow.triangle.2.circlepath", title: "Siklus", value: "\(b.cycles)")
                Tile(icon: "thermometer.medium", title: "Suhu", value: b.temp.map { String(format: "%.1f°", $0) } ?? "–")
                Tile(icon: "bolt", title: "Daya", value: String(format: "%+.1fW", b.watts))
            }

            Card(title: "Riwayat") {
                HistoryChart(samples: m.history, limit: m.helperInstalled && m.config.enabled ? m.config.limit : nil)
            }

            if !m.helperInstalled {
                Card(title: "Helper") {
                    Text("Helper (root) diperlukan untuk mengontrol pengisian.").font(.caption).foregroundStyle(.secondary)
                    Button("Install helper…") { m.admin("install-daemon") }.buttonStyle(.borderedProminent)
                }
            } else {
                Card(title: "Pengisian") {
                    Switch("Aktifkan limiter", "battery.100percent", $m.config.enabled)
                    HStack {
                        Text("Batas")
                        Slider(value: Binding(get: { Double(m.config.limit) }, set: { m.config.limit = Int($0) }),
                               in: SMC.canInhibit ? 50...100 : 80...100, step: 5)
                        Text("\(m.config.limit)%").monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                    if SMC.canInhibit {
                        Stepper("Sailing: \(m.config.limit - m.config.sailing)–\(m.config.limit)%", value: $m.config.sailing, in: 0...20)
                    } else {
                        Text("macOS 27: pakai Charge Limit bawaan (80–100%)").font(.caption).foregroundStyle(.secondary)
                    }
                    Switch("Top up ke 100% (sementara)", "arrow.up.to.line", $m.config.topUp)
                    Switch("Auto discharge ke batas", "arrow.down.to.line", $m.config.autoDischarge)
                }
                Card(title: "Proteksi") {
                    Switch(SMC.canInhibit ? "Heat protection" : "Heat protection (putus charger)", "flame", $m.config.heatProtection)
                    if m.config.heatProtection {
                        Stepper(String(format: "Berhenti di ≥ %.0f °C", m.config.maxTemp), value: $m.config.maxTemp, in: 30...45)
                    }
                    Switch("Hentikan pengisian saat sleep", "moon", $m.config.stopOnSleep)
                    HStack {
                        Label("Kalibrasi 100 → 10 → 100%", systemImage: "gauge.with.needle")
                        Spacer()
                        if m.status.calibration == 0 {
                            Button("Mulai") { m.config.calibrateAt = Date().timeIntervalSince1970 }
                        } else {
                            Button("Batalkan") { m.config.calibrateAt = 0 }
                        }
                    }
                }
            }

            if !m.error.isEmpty { Text(m.error).font(.caption).foregroundStyle(.red) }

            HStack {
                if m.helperInstalled { Button("Uninstall helper") { m.admin("uninstall-daemon") } }
                Spacer()
                Button("Keluar") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { m.refresh() }
    }
}

struct Ring: View {
    let percent: Int
    let limit: Int?
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 9)
            Circle().trim(from: 0, to: Double(percent) / 100)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let limit {
                // tick at the charge limit
                Capsule().fill(.primary).frame(width: 3, height: 13)
                    .offset(y: -38).rotationEffect(.degrees(Double(limit) * 3.6))
            }
            Text("\(percent)%").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .frame(width: 76, height: 76)
        .animation(.easeInOut, value: percent)
    }
}

struct Tile: View {
    let icon: String, title: String, value: String
    var help = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .help(help)
    }
}

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Switch: View {
    let title: String, icon: String
    @Binding var on: Bool
    init(_ title: String, _ icon: String, _ on: Binding<Bool>) { self.title = title; self.icon = icon; _on = on }

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Toggle(title, isOn: $on).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct Dot: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 7)); configuration.title.foregroundStyle(.primary) }
    }
}

struct HistoryChart: View {
    let samples: [Sample]
    let limit: Int?
    @State private var metric = 0
    @State private var hours = 6

    let metrics = [("Baterai", "%", Color.green), ("Suhu", "°C", Color.orange), ("Daya", "W", Color.blue)]

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

        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $metric) { ForEach(0..<3, id: \.self) { Text(metrics[$0].0).tag($0) } }
                Picker("", selection: $hours) { Text("1j").tag(1); Text("6j").tag(6); Text("24j").tag(24) }
                    .frame(width: 120)
            }
            .pickerStyle(.segmented).labelsHidden()

            Chart {
                ForEach(pts, id: \.date) { p in
                    if metric == 0 {
                        AreaMark(x: .value("Waktu", p.date), y: .value(name, p.v))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Waktu", p.date), y: .value(name, p.v))
                        .foregroundStyle(color).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
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
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))\(unit)") }
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
