import SwiftUI
import Charts
import SystemConfiguration
import IOKit

// Sistem → Jaringan: live speed of the interface macOS routes through, its addresses, traffic since
// boot, and the public IP (asked from api.ipify.org only while the tab is open).

/// Bytes received/sent per interface since boot. 64-bit counters (NET_RT_IFLIST2); getifaddrs' are 32-bit and wrap at 4 GB.
func netCounters() -> [String: (rx: UInt64, tx: UInt64)] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0], len = 0
    guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return [:] }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return [:] }
    var out: [String: (rx: UInt64, tx: UInt64)] = [:]
    buf.withUnsafeBytes { p in
        var i = 0
        while i + MemoryLayout<if_msghdr>.size <= len {
            let h = p.loadUnaligned(fromByteOffset: i, as: if_msghdr.self)
            guard h.ifm_msglen > 0 else { break }
            if Int32(h.ifm_type) == RTM_IFINFO2, i + MemoryLayout<if_msghdr2>.size <= len {
                let h2 = p.loadUnaligned(fromByteOffset: i, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(h2.ifm_index), &name) != nil { out[String(cString: name)] = (h2.ifm_data.ifi_ibytes, h2.ifm_data.ifi_obytes) }
            }
            i += Int(h.ifm_msglen)
        }
    }
    return out
}

/// First IPv4 address of an interface.
func ipv4(_ name: String) -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return nil }
    defer { freeifaddrs(list) }
    for p in sequence(first: list, next: { $0?.pointee.ifa_next }) {
        guard let a = p?.pointee, String(cString: a.ifa_name) == name, let sa = a.ifa_addr, Int32(sa.pointee.sa_family) == AF_INET else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
    }
    return nil
}

/// MAC address the interface uses now (the private Wi-Fi address when that's on). getifaddrs hands apps a
/// redacted 02:00:00:00:00:00 and ifconfig sometimes does too; then fall back to the hardware address.
func macAddress(_ name: String) -> String? {
    let used = capture("/sbin/ifconfig", name).split(separator: "\n").lazy
        .compactMap { $0.split(whereSeparator: \.isWhitespace).drop { $0 != "ether" }.dropFirst().first.map(String.init) }.first
    if let used, used != "02:00:00:00:00:00" { return used }
    let match = IOServiceMatching("IOEthernetInterface") as NSMutableDictionary
    match["IOPropertyMatch"] = ["BSD Name": name]
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, match)
    guard svc != 0 else { return nil }
    defer { IOObjectRelease(svc) }
    var parent: io_object_t = 0
    guard IORegistryEntryGetParentEntry(svc, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(parent) }
    let d = IORegistryEntryCreateCFProperty(parent, "IOMACAddress" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data
    return d.map { $0.map { String(format: "%02x", $0) }.joined(separator: ":") }
}

final class NetModel: ObservableObject {
    @Published var iface = ""   // BSD name, e.g. en0
    @Published var kind = ""    // "Wi-Fi", "Ethernet"…
    @Published var ipv4: String?
    @Published var mac: String?
    @Published var rx: UInt64 = 0 // since boot, primary interface
    @Published var tx: UInt64 = 0
    @Published var down = 0.0     // bytes/s
    @Published var up = 0.0
    @Published var live: [(t: Date, down: Double, up: Double)] = []
    @Published var publicIP: String?
    private var last: (t: Date, rx: UInt64, tx: UInt64)?
    private var publicAt = Date.distantPast

    func refresh() {
        let primary = (SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any])?["PrimaryInterface"] as? String ?? ""
        if primary != iface {
            iface = primary; last = nil; live = []
            kind = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface])?
                .first { SCNetworkInterfaceGetBSDName($0) as String? == primary }
                .flatMap { SCNetworkInterfaceGetLocalizedDisplayName($0) as String? } ?? ""
            mac = primary.isEmpty ? nil : macAddress(primary)
        }
        ipv4 = primary.isEmpty ? nil : baterai_safer.ipv4(primary)
        let now = Date(), c = netCounters()[primary] ?? (0, 0)
        if let l = last, c.rx >= l.rx, c.tx >= l.tx {
            let dt = now.timeIntervalSince(l.t)
            down = Double(c.rx - l.rx) / dt; up = Double(c.tx - l.tx) / dt
            live = live.suffix(59) + [(now, down, up)]
        }
        last = (now, c.rx, c.tx); rx = c.rx; tx = c.tx
        if now.timeIntervalSince(publicAt) > 300 { fetchPublicIP() }
    }

    func fetchPublicIP() {
        publicAt = Date()
        URLSession.shared.dataTask(with: URL(string: "https://api.ipify.org")!) { d, _, _ in
            let s = d.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let ok = !s.isEmpty && s.count <= 45 && s.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" } // only show something IP-shaped
            DispatchQueue.main.async { self.publicIP = ok ? s : nil }
        }.resume()
    }
}

func speed(_ bps: Double) -> String {
    let f = ByteCountFormatter(); f.countStyle = .decimal; f.allowsNonnumericFormatting = false // "0 KB/s", not "Zero KB/s"
    return f.string(fromByteCount: Int64(bps)) + "/s"
}

struct NetCard: View {
    @ObservedObject var n: NetModel

    var body: some View {
        Card(title: "Jaringan", icon: "network") {
            if n.iface.isEmpty {
                Text(tr("Tidak terhubung ke jaringan")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 16) {
                    rate("arrow.down", "Unduh", n.down, Palette.accent)
                    rate("arrow.up", "Unggah", n.up, .gray)
                    Spacer(minLength: 0)
                }
                Chart {
                    ForEach(n.live, id: \.t) { p in
                        AreaMark(x: .value("Waktu", p.t), y: .value("B/s", p.down), series: .value("Seri", "down"))
                            .foregroundStyle(Palette.accent.opacity(0.15)).interpolationMethod(.monotone)
                        LineMark(x: .value("Waktu", p.t), y: .value("B/s", p.down), series: .value("Seri", "down"))
                            .foregroundStyle(Palette.accent).interpolationMethod(.monotone)
                        LineMark(x: .value("Waktu", p.t), y: .value("B/s", p.up), series: .value("Seri", "up"))
                            .foregroundStyle(Color.gray).interpolationMethod(.monotone)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        AxisValueLabel { Text(speed(v.as(Double.self) ?? 0)).font(.system(size: 9)) }
                    }
                }
                .frame(height: 80)
                VStack(spacing: 6) {
                    info("Antarmuka", n.kind.isEmpty ? n.iface : "\(n.kind) · \(n.iface)")
                    info("IPv4", n.ipv4 ?? "—")
                    info("MAC", n.mac ?? "—")
                    info("IP publik", n.publicIP ?? "—")
                    info("Total sejak nyala", "↓ \(bytes(Double(n.rx)))  ↑ \(bytes(Double(n.tx)))")
                }
            }
        }
    }

    func rate(_ icon: String, _ title: String, _ v: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(tr(title), systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            Text(speed(v)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
        }
    }

    func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(tr(label)).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit().textSelection(.enabled).lineLimit(1)
        }
    }
}
