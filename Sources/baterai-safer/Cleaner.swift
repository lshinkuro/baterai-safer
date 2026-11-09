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
    a.messageText = tr(title)
    a.informativeText = tr(info)
    a.alertStyle = .warning
    a.addButton(withTitle: tr(button))
    a.addButton(withTitle: tr("Batal"))
    return a.runModal() == .alertFirstButtonReturn
}

final class CleanerModel: ObservableObject {
    @Published var junk: [Junk] = {
        let h = NSHomeDirectory()
        return [Junk(title: "Cache aplikasi", icon: "shippingbox.fill", color: Palette.blue, path: h + "/Library/Caches"),
                Junk(title: "Log", icon: "doc.text.fill", color: Palette.slate, path: h + "/Library/Logs"),
                Junk(title: "Xcode DerivedData", icon: "hammer.fill", color: Palette.sky, path: h + "/Library/Developer/Xcode/DerivedData"),
                Junk(title: "iOS DeviceSupport", icon: "iphone", color: Palette.indigo, path: h + "/Library/Developer/Xcode/iOS DeviceSupport"),
                Junk(title: "Cache npm", icon: "shippingbox.circle.fill", color: Palette.red, path: h + "/.npm/_cacache"),
                Junk(title: "Sampah (Trash)", icon: "trash.fill", color: Palette.red, path: h + "/.Trash")]
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
                if let err { self.message = String(format: tr("Gagal: %@"), err.localizedDescription); return }
                self.message = String(format: tr("%@ dipindah ke Trash (%@)"), "\(item.url.lastPathComponent)", "\(bytes(item.size))")
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
                        self.message = code == 0 ? String(format: tr("Simulator tak terpakai dihapus: %@ dibebaskan"), "\(bytes(max(0, before - after)))") : String(format: tr("Gagal: %@"), "\(lastLine(err))")
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
        message = String(format: tr("%@: %@ dibebaskan"), tr(j.title), bytes(max(0, (j.size ?? 0) - after))) + (failed > 0 ? String(format: tr(", %@ item dilewati (sedang dipakai/terlindungi)"), "\(failed)") : "")
        if let i = junk.firstIndex(where: { $0.id == j.id }) { junk[i].size = after }
    }

    // Moves the app and its leftovers to the Trash, so it can still be restored.
    func uninstall(_ a: AppItem, confirmed: ([URL]) -> Bool = { _ in true }) {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleID).isEmpty {
            message = String(format: tr("Tutup %@ dulu sebelum menghapus."), a.name)
            return
        }
        let extra = leftovers(name: a.name, bundleID: a.bundleID)
        guard confirmed(extra) else { return }
        NSWorkspace.shared.recycle([a.url] + extra) { _, err in
            DispatchQueue.main.async {
                if let err { self.message = String(format: tr("Gagal: %@"), err.localizedDescription); return }
                self.apps.removeAll { $0.id == a.id }
                self.message = String(format: tr("%@ dipindah ke Trash"), a.name)
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
            Hero {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Bisa dibersihkan", systemImage: "sparkles").font(.system(size: 12, weight: .bold)).opacity(0.85)
                        Text(scanning ? tr("Memindai…") : bytes(total)).font(.system(size: 40, weight: .semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("cache, log, dan sisa build").font(.system(size: 12, weight: .semibold)).opacity(0.8)
                    }
                    Spacer()
                    Button { c.scan() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .semibold))
                            .frame(width: 42, height: 42).background(.white.opacity(0.22), in: Circle())
                    }
                    .buttonStyle(.plain).help("Pindai ulang").disabled(scanning)
                }
            }

            Card(title: "File sampah", icon: "trash") {
                ForEach(c.junk) { j in
                    HStack(spacing: 10) {
                        IconBadge(icon: j.icon)
                        Text(tr(j.title))
                        Spacer()
                        if let s = j.size {
                            Text(bytes(s)).font(.system(.callout).weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
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
                    IconBadge(icon: "iphone.gen3")
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
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(spacing: 0) {
                    ForEach(c.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { a in
                        HoverRow { hover in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 24, height: 24)
                                Text(a.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                Text(a.size.map(bytes) ?? "…").font(.system(.callout)).monospacedDigit().foregroundStyle(.secondary)
                                Button {
                                    c.uninstall(a) { extra in
                                        let list = extra.map { "• ~/Library/" + $0.path.replacingOccurrences(of: NSHomeDirectory() + "/Library/", with: "") }.joined(separator: "\n")
                                        return confirm("Hapus \(a.name)?", "Aplikasi\(extra.isEmpty ? "" : " dan \(extra.count) file sisanya") dipindah ke Trash:\n\(list)", "Pindah ke Trash")
                                    }
                                } label: { Image(systemName: "trash.circle.fill").font(.system(size: 16)) }
                                    .buttonStyle(.plain).foregroundStyle(Palette.red.opacity(0.85))
                                    .tip("Pindah ke Trash beserta file sisanya").opacity(hover ? 1 : 0)
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
                        .buttonStyle(.borderless).tip("Folder induk")
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
                ForEach(Array(c.folders.prefix(12).enumerated()), id: \.element.id) { i, item in
                    SizedRow(item: item, fraction: item.size / top, color: Palette.accent,
                             drill: { c.analyze(item.url.path) }, trash: trashAction(item))
                }
            }
            if !c.bigFiles.isEmpty {
                Divider()
                Text("File di atas 200 MB").font(.system(size: 12, weight: .bold))
                VStack(spacing: 0) {
                    ForEach(Array(c.bigFiles.enumerated()), id: \.element.id) { i, item in
                        SizedRow(item: item, fraction: item.size / (c.bigFiles.first?.size ?? 1), color: Color.gray,
                                 drill: nil, trash: trashAction(item))
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
    let color: Color
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
                        ZStack(alignment: .leading) {
                            Capsule().fill(color.opacity(0.15))
                            Capsule().fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, g.size.width * fraction))
                        }
                    }
                    .frame(height: 6)
                }
                Text(bytes(item.size)).font(.system(.caption).weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                HStack(spacing: 6) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                        .tip("Tampilkan di Finder")
                    if let trash { Button(action: trash) { Image(systemName: "trash") }.foregroundStyle(Palette.red).tip("Pindah ke Trash") }
                }
                .buttonStyle(.borderless).opacity(hover ? 1 : 0)
            }
            .font(.callout)
        }
        .onTapGesture { if isDir { drill?() } }
    }
}
