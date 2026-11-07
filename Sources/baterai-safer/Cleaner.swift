import SwiftUI

struct Junk: Identifiable {
    let title: String, icon: String, color: Color, path: String
    var size: Double?
    var id: String { path }
}

struct AppItem: Identifiable {
    let url: URL, name: String, bundleID: String
    var size: Double?
    var id: String { url.path }
}

// du is several times faster than walking the tree with FileManager.
func dirSize(_ url: URL) -> Double {
    (Double(capture("/usr/bin/du", "-sk", url.path).split(separator: "\t").first ?? "") ?? 0) * 1024
}

/// Per-user files an app leaves behind. Only looked up at uninstall time, since probing
/// other apps' Containers can trigger a macOS privacy prompt.
func leftovers(name: String, bundleID: String) -> [URL] {
    let lib = NSHomeDirectory() + "/Library/"
    return ["Application Support/\(name)", "Application Support/\(bundleID)", "Caches/\(bundleID)", "Preferences/\(bundleID).plist",
            "Containers/\(bundleID)", "Saved Application State/\(bundleID).savedState", "HTTPStorages/\(bundleID)",
            "WebKit/\(bundleID)", "Logs/\(name)"]
        .map { lib + $0 }.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
}

func confirm(_ title: String, _ info: String, _ button: String) -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    a.alertStyle = .warning
    a.addButton(withTitle: button)
    a.addButton(withTitle: "Batal")
    return a.runModal() == .alertFirstButtonReturn
}

final class CleanerModel: ObservableObject {
    @Published var junk: [Junk] = {
        let h = NSHomeDirectory()
        return [Junk(title: "Cache aplikasi", icon: "shippingbox.fill", color: .blue, path: h + "/Library/Caches"),
                Junk(title: "Log", icon: "doc.text.fill", color: .gray, path: h + "/Library/Logs"),
                Junk(title: "Xcode DerivedData", icon: "hammer.fill", color: .cyan, path: h + "/Library/Developer/Xcode/DerivedData"),
                Junk(title: "Sampah (Trash)", icon: "trash.fill", color: .red, path: h + "/.Trash")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }()
    @Published var apps: [AppItem] = []
    @Published var message = ""
    private var scanned = false

    func scanOnce() { if !scanned { scanned = true; scan() } }

    func scan() {
        let fm = FileManager.default
        apps = ((try? fm.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
            .compactMap { u in
                guard let id = Bundle(url: u)?.bundleIdentifier, !id.hasPrefix("com.apple.") else { return nil }
                return AppItem(url: u, name: u.deletingPathExtension().lastPathComponent, bundleID: id)
            }
        for i in junk.indices { junk[i].size = nil }
        let junkPaths = junk.map(\.path), appURLs = apps.map(\.url)
        DispatchQueue.global(qos: .utility).async {
            for (i, p) in junkPaths.enumerated() {
                let s = dirSize(URL(fileURLWithPath: p))
                DispatchQueue.main.async { if i < self.junk.count { self.junk[i].size = s } }
            }
            for u in appURLs {
                let s = dirSize(u)
                DispatchQueue.main.async {
                    if let i = self.apps.firstIndex(where: { $0.url == u }) { self.apps[i].size = s }
                    self.apps.sort { ($0.size ?? -1) > ($1.size ?? -1) }
                }
            }
        }
    }

    // Deletes the folder's contents, never the folder itself; files in use or protected are skipped.
    func clean(_ j: Junk) {
        let fm = FileManager.default, dir = URL(fileURLWithPath: j.path)
        var failed = 0
        for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            do { try fm.removeItem(at: u) } catch { failed += 1 }
        }
        let after = dirSize(dir)
        message = "\(j.title): \(bytes(max(0, (j.size ?? 0) - after))) dibebaskan" + (failed > 0 ? ", \(failed) item dilewati (sedang dipakai/terlindungi)" : "")
        if let i = junk.firstIndex(where: { $0.id == j.id }) { junk[i].size = after }
    }

    // Moves the app and its leftovers to the Trash, so it can still be restored.
    func uninstall(_ a: AppItem, confirmed: ([URL]) -> Bool = { _ in true }) {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleID).isEmpty {
            message = "Tutup \(a.name) dulu sebelum menghapus."
            return
        }
        let extra = leftovers(name: a.name, bundleID: a.bundleID)
        guard confirmed(extra) else { return }
        NSWorkspace.shared.recycle([a.url] + extra) { _, err in
            DispatchQueue.main.async {
                if let err { self.message = "Gagal: \(err.localizedDescription)"; return }
                self.apps.removeAll { $0.id == a.id }
                self.message = "\(a.name) dipindah ke Trash"
            }
        }
    }
}

struct CleanerTab: View {
    @ObservedObject var c: CleanerModel
    @State private var query = ""

    var body: some View {
        let total = c.junk.compactMap(\.size).reduce(0, +), scanning = c.junk.contains { $0.size == nil }
        VStack(spacing: 12) {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scanning ? "Memindai…" : bytes(total)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("file sampah bisa dibersihkan").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { c.scan() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Pindai ulang").disabled(scanning)
                }
            }

            Card(title: "File sampah", icon: "trash") {
                ForEach(c.junk) { j in
                    HStack(spacing: 10) {
                        IconBadge(icon: j.icon, color: j.color)
                        Text(j.title)
                        Spacer()
                        if let s = j.size {
                            Text(bytes(s)).font(.system(.callout, design: .rounded).weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button("Bersihkan") {
                            if confirm("Bersihkan \(j.title)?", "Isi \(j.path) (\(bytes(j.size ?? 0))) akan dihapus permanen. Aplikasi akan membuat ulang cache-nya bila perlu.", "Hapus") { c.clean(j) }
                        }
                        .controlSize(.small).disabled((j.size ?? 0) < 1_000_000)
                    }
                }
            }

            Card(title: "Uninstall aplikasi", icon: "xmark.app") {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Cari aplikasi", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(spacing: 0) {
                    ForEach(c.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { a in
                        HoverRow { hover in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 24, height: 24)
                                Text(a.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(a.size.map(bytes) ?? "…").font(.system(.callout, design: .rounded)).monospacedDigit().foregroundStyle(.secondary)
                                Button {
                                    c.uninstall(a) { extra in
                                        let list = extra.map { "• ~/Library/" + $0.path.replacingOccurrences(of: NSHomeDirectory() + "/Library/", with: "") }.joined(separator: "\n")
                                        return confirm("Hapus \(a.name)?", "Aplikasi\(extra.isEmpty ? "" : " dan \(extra.count) file sisanya") dipindah ke Trash:\n\(list)", "Pindah ke Trash")
                                    }
                                } label: { Image(systemName: "trash.circle.fill").font(.system(size: 16)) }
                                    .buttonStyle(.plain).foregroundStyle(.red.opacity(0.85))
                                    .help("Pindah ke Trash beserta file sisanya").opacity(hover ? 1 : 0)
                            }
                        }
                    }
                }
            }

            if !c.message.isEmpty {
                Label(c.message, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { c.scanOnce() }
    }
}
