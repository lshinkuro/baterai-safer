import SwiftUI
import Charts

/// Like `sh`, but returns stdout.
func capture(_ args: String...) -> String {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let d = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: d, as: UTF8.self)
}

struct Proc: Identifiable, Equatable {
    var pid: Int32
    var cpu: Double
    var mb: Double
    var user: String
    var name: String
    var id: Int32 { pid }
}

/// Parses `ps -Aceo pid=,pcpu=,rss=,user=,comm=` (rss in KB; comm may contain spaces).
func parsePS(_ s: String) -> [Proc] {
    s.split(separator: "\n").compactMap { line in
        let f = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard f.count == 5, let pid = Int32(f[0]), let cpu = Double(f[1]), let kb = Double(f[2]) else { return nil }
        var name = f[4].trimmingCharacters(in: .whitespaces)
        if name == "baterai-safer" { name = f[3] == "root" ? "Poni helper" : "Poni" } // executable kept its old name
        return Proc(pid: pid, cpu: cpu, mb: kb / 1024, user: String(f[3]), name: name)
    }
}

final class SystemModel: ObservableObject {
    @Published var memUsed = 0.0
    @Published var swapUsed = 0.0
    let memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var cpu = 0.0
    @Published var diskFree = 0.0
    @Published var diskTotal = 0.0
    @Published var procs: [Proc] = []
    @Published var live: [(t: Date, cpu: Double, mem: Double)] = [] // last ~3 minutes
    private var lastTicks: [UInt32] = []
    private var timer: Timer?

    // Only polls while the Sistem tab is visible.
    func start() { stop(); refresh(); timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() } }
    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        let page = Double(vm_kernel_page_size)
        var vm = vm_statistics64(), n = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        if withUnsafeMutablePointer(to: &vm, { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &n) } }) == KERN_SUCCESS {
            // Same formula as Activity Monitor's "Memory Used": app + wired + compressed
            memUsed = Double(UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * page
        }
        var swap = xsw_usage(), size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 { swapUsed = Double(swap.xsu_used) }

        var load = host_cpu_load_info(), cn = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        if withUnsafeMutablePointer(to: &load, { $0.withMemoryRebound(to: integer_t.self, capacity: Int(cn)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cn) } }) == KERN_SUCCESS {
            let t = [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3] // user, system, idle, nice
            if lastTicks.count == 4 {
                let d = zip(t, lastTicks).map { Double($0 &- $1) }, total = d.reduce(0, +)
                if total > 0 { cpu = (total - d[2]) / total }
            }
            lastTicks = t
        }

        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
            diskTotal = Double(v.volumeTotalCapacity ?? 0)
        }

        live = live.suffix(59) + [(Date(), cpu, memUsed / memTotal)]
        procs = parsePS(capture("/bin/ps", "-Aceo", "pid=,pcpu=,rss=,user=,comm="))
    }

    /// Apps quit gracefully (they can ask to save); other own processes get SIGTERM.
    func quit(_ p: Proc) {
        if let app = NSRunningApplication(processIdentifier: p.pid) { app.terminate() } else { kill(p.pid, SIGTERM) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }
}

func bytes(_ b: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory) }

struct SystemTab: View {
    @ObservedObject var s: SystemModel
    @Local private var byMemory = false

    var body: some View {
        let mem = s.memUsed / s.memTotal, disk = s.diskTotal > 0 ? 1 - s.diskFree / s.diskTotal : 0
        let top = (byMemory ? s.procs.sorted { $0.mb > $1.mb } : s.procs.sorted { $0.cpu > $1.cpu }).prefix(8)
        VStack(spacing: 12) {
            Hero(theme: mem > 0.85 ? .rose : .accent) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Memori", systemImage: "memorychip.fill").font(.system(size: 12, weight: .bold)).opacity(0.85)
                        Spacer()
                        Text("\(Int(mem * 100))% terpakai").font(.system(size: 11, weight: .bold)).opacity(0.85)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(bytes(s.memTotal - s.memUsed)).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                        Text("tersisa").font(.system(size: 14, weight: .bold)).opacity(0.8)
                    }
                    Meter(value: mem, color: .white)
                    if s.swapUsed > 0 {
                        Label("Swap \(bytes(s.swapUsed)) — RAM penuh, tutup aplikasi berat", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold)).opacity(0.85)
                    }
                }
            }
            HStack(spacing: 8) {
                gauge("CPU", "cpu.fill", s.cpu, Palette.accent, String(format: tr("%@ core"), "\(ProcessInfo.processInfo.activeProcessorCount)"))
                gauge("Disk", "internaldrive.fill", disk, Palette.accent, String(format: tr("%@ sisa"), bytes(s.diskFree)))
            }

            Card(title: "Aktivitas live", icon: "waveform.path.ecg") {
                Chart {
                    ForEach(s.live, id: \.t) { p in
                        LineMark(x: .value("Waktu", p.t), y: .value("%", p.cpu * 100), series: .value("Seri", "CPU"))
                            .foregroundStyle(by: .value("Seri", "CPU")).interpolationMethod(.monotone)
                        LineMark(x: .value("Waktu", p.t), y: .value("%", p.mem * 100), series: .value("Seri", tr("Memori")))
                            .foregroundStyle(by: .value("Seri", tr("Memori"))).interpolationMethod(.monotone)
                    }
                }
                .chartForegroundStyleScale(["CPU": Palette.accent, tr("Memori"): Color.gray])
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 9)) }
                    }
                }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 90)
            }

            Card(title: "Proses terberat", icon: "flame") {
                Picker("", selection: $byMemory) { Text("CPU").tag(false); Text("Memori").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().controlSize(.small)
                VStack(spacing: 0) {
                    ForEach(top) { p in
                        HoverRow { hover in
                            HStack(spacing: 8) {
                                if let icon = NSRunningApplication(processIdentifier: p.pid)?.icon {
                                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                                } else {
                                    IconBadge(icon: "gearshape.fill", size: 20)
                                }
                                Text(p.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(byMemory ? bytes(p.mb * 1_048_576) : String(format: "%.1f%%", p.cpu))
                                    .font(.system(.callout).weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                                if p.user == NSUserName() {
                                    Button {
                                        if confirm("Tutup \(p.name)?", "Aplikasi akan diminta keluar; pekerjaan yang belum disimpan bisa hilang pada proses non-aplikasi.", "Tutup") { s.quit(p) }
                                    } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14)) }
                                        .buttonStyle(.plain).foregroundStyle(Palette.red.opacity(0.85)).tip("Tutup proses")
                                        .opacity(hover ? 1 : 0)
                                } else {
                                    Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                                        .frame(width: 14).help("Proses milik \(p.user)").opacity(hover ? 1 : 0)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }

    func gauge(_ title: String, _ icon: String, _ v: Double, _ color: Color, _ caption: String) -> some View {
        HStack(spacing: 12) {
            Ring(value: v, color: v > 0.85 ? Palette.red : color, label: "\(Int(v * 100))%", size: 64, line: 8)
            VStack(alignment: .leading, spacing: 2) {
                Label(tr(title), systemImage: icon).font(.system(size: 13, weight: .semibold))
                Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
    }
}
