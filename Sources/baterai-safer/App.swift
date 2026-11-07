import SwiftUI
import CSMC

final class Model: ObservableObject {
    @Published var battery = Battery.read()
    @Published var status = load(Paths.status, Status())
    @Published var config = load(Paths.config, Config()) {
        didSet { if config != oldValue { save(config, Paths.config); syncNative() } }
    }
    @Published var error = ""
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    var helperInstalled: Bool { FileManager.default.fileExists(atPath: Paths.plist) }
    var helperRunning: Bool { Date().timeIntervalSince1970 - status.updated < 30 }

    func refresh() {
        battery = Battery.read()
        status = load(Paths.status, Status())
        syncNative()
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
            Image(systemName: m.status.charging && m.battery.ac ? "battery.100percent.bolt" : m.battery.ac ? "powerplug" : "battery.75percent")
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
        return s.charging ? "Mengisi" : "Tidak mengisi — pakai daya charger"
    }

    var body: some View {
        let b = m.battery
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(b.percent)%").font(.system(size: 28, weight: .semibold))
                Spacer()
                Text(stateText).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow { Text("Kesehatan"); Text("\(b.health)% (\(b.maxCapacity)/\(b.designCapacity) mAh)") }
                GridRow { Text("Siklus"); Text("\(b.cycles)") }
                GridRow { Text("Suhu"); Text(b.temp.map { String(format: "%.1f °C", $0) } ?? "–") }
            }
            .font(.caption).foregroundStyle(.secondary)

            Divider()

            if !m.helperInstalled {
                Text("Helper (root) diperlukan untuk mengontrol pengisian.").font(.caption)
                Button("Install helper…") { m.admin("install-daemon") }
            } else {
                Toggle("Aktifkan limiter", isOn: $m.config.enabled)
                VStack(alignment: .leading) {
                    Text("Batas pengisian: \(m.config.limit)%")
                    Slider(value: Binding(get: { Double(m.config.limit) }, set: { m.config.limit = Int($0) }), in: SMC.canInhibit ? 50...100 : 80...100, step: 5)
                }
                if SMC.canInhibit {
                    Stepper("Sailing: \(m.config.limit - m.config.sailing)–\(m.config.limit)%", value: $m.config.sailing, in: 0...20)
                } else {
                    Text("macOS 27: pakai Charge Limit bawaan (80–100%)").font(.caption).foregroundStyle(.secondary)
                }
                Toggle(SMC.canInhibit ? "Heat protection" : "Heat protection (putus charger)", isOn: $m.config.heatProtection)
                if m.config.heatProtection {
                    Stepper(String(format: "Berhenti di ≥ %.0f °C", m.config.maxTemp), value: $m.config.maxTemp, in: 30...45)
                }
                Toggle("Auto discharge ke batas", isOn: $m.config.autoDischarge)
                Toggle("Top up ke 100% (sementara)", isOn: $m.config.topUp)
                Toggle("Hentikan pengisian saat sleep", isOn: $m.config.stopOnSleep)
                if m.status.calibration == 0 {
                    Button("Mulai kalibrasi (100 → 10 → 100%)") { m.config.calibrateAt = Date().timeIntervalSince1970 }
                } else {
                    Button("Batalkan kalibrasi") { m.config.calibrateAt = 0 }
                }
            }

            if !m.error.isEmpty { Text(m.error).font(.caption).foregroundStyle(.red) }

            Divider()
            HStack {
                if m.helperInstalled { Button("Uninstall helper") { m.admin("uninstall-daemon") } }
                Spacer()
                Button("Keluar") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear { m.refresh() }
    }
}
