import SwiftUI

struct Junk: Identifiable {
    let title: String, icon: String, color: Color, path: String
    var size: Double?
    var id: String { path }
}

struct Sized: Identifiable {
    let url: URL
    var size: Double
    var id: String { url.path }
}

/// Parses `du -d 1 -k <parent>` into children (largest first), dropping the parent's own total.
func parseDu(_ s: String, parent: String) -> [Sized] {
    s.split(separator: "\n").compactMap { line -> Sized? in
        let f = line.split(separator: "\t", maxSplits: 1)
        guard f.count == 2, let kb = Double(f[0]), String(f[1]) != parent else { return nil }
        return Sized(url: URL(fileURLWithPath: String(f[1])), size: kb * 1024)
    }
    .sorted { $0.size > $1.size }
}

/// Folders that must never be offered for the Trash from the analyzer.
func isProtected(_ path: String) -> Bool {
    let h = NSHomeDirectory()
    if [h, h + "/Library", h + "/Documents", h + "/Desktop", h + "/Downloads", h + "/Movies", h + "/Music", h + "/Pictures", h + "/Applications"].contains(path) { return true }
    return (path as NSString).deletingLastPathComponent == h + "/Library" // Library's direct children
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
                Junk(title: "iOS DeviceSupport", icon: "iphone", color: .indigo, path: h + "/Library/Developer/Xcode/iOS DeviceSupport"),
                Junk(title: "Cache npm", icon: "shippingbox.circle.fill", color: .red, path: h + "/.npm/_cacache"),
                Junk(title: "Sampah (Trash)", icon: "trash.fill", color: .red, path: h + "/.Trash")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }()
    @Published var apps: [AppItem] = []
    @Published var message = ""
    @Published var bigFiles: [Sized] = []
    @Published var folders: [Sized] = []     // children of `folder`, largest first
    @Published var folder = NSHomeDirectory()
    @Published var analyzing = false
    @Published var simulatorsBusy = false
    private var duCache: [String: [Sized]] = [:]
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

    /// Files over 200 MB that Spotlight knows about (instant, but misses unindexed folders).
    func findBigFiles() {
        runAsync("/usr/bin/mdfind", ["-onlyin", NSHomeDirectory(), "kMDItemFSSize > 209715200"]) { _, out, _ in
            let fm = FileManager.default
            self.bigFiles = out.split(separator: "\n").compactMap { p -> Sized? in
                guard let a = try? fm.attributesOfItem(atPath: String(p)), a[.type] as? FileAttributeType == .typeRegular else { return nil }
                return Sized(url: URL(fileURLWithPath: String(p)), size: Double(a[.size] as? Int ?? 0))
            }
            .sorted { $0.size > $1.size }.prefix(15).map { $0 }
        }
    }

    /// One `du -d 1` per folder, cached; walking the whole home takes about a minute.
    func analyze(_ path: String, force: Bool = false) {
        folder = path
        if !force, let c = duCache[path] { folders = c; return }
        folders = []
        analyzing = true
        runAsync("/usr/bin/du", ["-d", "1", "-k", path]) { _, out, _ in
            let list = parseDu(out, parent: path)
            self.duCache[path] = list
            if self.folder == path { self.folders = list; self.analyzing = false }
        }
    }

    func trash(_ item: Sized) {
        NSWorkspace.shared.recycle([item.url]) { _, err in
            DispatchQueue.main.async {
                if let err { self.message = "Gagal: \(err.localizedDescription)"; return }
                self.message = "\(item.url.lastPathComponent) dipindah ke Trash (\(bytes(item.size)))"
                self.folders.removeAll { $0.id == item.id }
                self.bigFiles.removeAll { $0.id == item.id }
                self.duCache = [:] // parent sizes changed
            }
        }
    }

    /// `simctl delete unavailable` only removes simulators whose runtime is gone — safe.
    func deleteUnavailableSimulators() {
        let devices = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Developer/CoreSimulator/Devices")
        simulatorsBusy = true
        DispatchQueue.global().async {
            let before = dirSize(devices)
            runAsync("/usr/bin/xcrun", ["simctl", "delete", "unavailable"]) { code, _, err in
                DispatchQueue.global().async {
                    let after = dirSize(devices)
                    DispatchQueue.main.async {
                        self.simulatorsBusy = false
                        self.message = code == 0 ? "Simulator tak terpakai dihapus: \(bytes(max(0, before - after))) dibebaskan" : "Gagal: \(lastLine(err))"
                    }
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
    @Local private var query = ""

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

            Card(title: "Simulator iOS", icon: "iphone.gen3") {
                HStack(spacing: 10) {
                    IconBadge(icon: "iphone.gen3", color: .teal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Simulator tak terpakai")
                        Text("Simulator yang runtime-nya sudah tidak terpasang").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if c.simulatorsBusy { ProgressView().controlSize(.small) }
                    Button("Hapus") { c.deleteUnavailableSimulators() }.controlSize(.small).disabled(c.simulatorsBusy)
                }
            }

            DiskAnalyzer(c: c)

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
        .onAppear { c.scanOnce(); if c.bigFiles.isEmpty { c.findBigFiles() } }
    }
}

struct DiskAnalyzer: View {
    @ObservedObject var c: CleanerModel

    var body: some View {
        let home = NSHomeDirectory()
        let top = c.folders.first?.size ?? 1
        Card(title: "Analisis disk", icon: "chart.bar.doc.horizontal") {
            HStack(spacing: 6) {
                if c.folder != home {
                    Button { c.analyze((c.folder as NSString).deletingLastPathComponent) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                }
                Text(c.folder.replacingOccurrences(of: home, with: "~")).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.head)
                Spacer()
                if c.analyzing {
                    ProgressView().controlSize(.small)
                } else {
                    Button(c.folders.isEmpty ? "Analisis" : "Ulang") { c.analyze(c.folder, force: true) }.controlSize(.small)
                }
            }
            if c.analyzing && c.folders.isEmpty {
                Text("Menghitung ukuran folder… (folder rumah bisa sekitar 1 menit)").font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(c.folders.prefix(12)) { item in
                    SizedRow(item: item, fraction: item.size / top, drill: { c.analyze(item.url.path) }, trash: trashAction(item))
                }
            }
            if !c.bigFiles.isEmpty {
                Divider()
                Text("FILE > 200 MB (SPOTLIGHT)").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(c.bigFiles) { item in
                        SizedRow(item: item, fraction: item.size / (c.bigFiles.first?.size ?? 1), drill: nil, trash: trashAction(item))
                    }
                }
            }
        }
    }

    func trashAction(_ item: Sized) -> (() -> Void)? {
        guard !isProtected(item.url.path) else { return nil }
        return {
            if confirm("Pindahkan \(item.url.lastPathComponent) ke Trash?", "\(item.url.path)\n\(bytes(item.size)). Masih bisa dikembalikan dari Trash.", "Pindah ke Trash") { c.trash(item) }
        }
    }
}

struct SizedRow: View {
    let item: Sized
    let fraction: Double
    let drill: (() -> Void)?
    let trash: (() -> Void)?

    var body: some View {
        let isDir = (try? item.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        HoverRow { hover in
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    GeometryReader { g in
                        Capsule().fill(level(fraction * 0.9).gradient).frame(width: max(3, g.size.width * fraction))
                    }
                    .frame(height: 4)
                }
                Text(bytes(item.size)).font(.system(.caption, design: .rounded).weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                HStack(spacing: 6) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                        .help("Tampilkan di Finder")
                    if let trash { Button(action: trash) { Image(systemName: "trash") }.foregroundStyle(.red).help("Pindah ke Trash") }
                }
                .buttonStyle(.borderless).opacity(hover ? 1 : 0)
            }
            .font(.callout)
        }
        .onTapGesture { if isDir { drill?() } }
    }
}
