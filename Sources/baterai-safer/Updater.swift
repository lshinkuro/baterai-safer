import SwiftUI
import CryptoKit

// Update check against GitHub Releases. Homebrew installs upgrade through brew; DMG installs download
// the release DMG, check its SHA-256 against GitHub's digest (the app isn't Apple-signed, so this is
// what tells us the file is the one we published), swap the app bundle and relaunch.

/// Numeric dotted-version compare ("0.6.10" > "0.6.9"); a "-dev" style suffix is ignored.
func isNewer(_ a: String, than b: String) -> Bool {
    func parts(_ v: String) -> [Int] {
        v.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: "-")[0].split(separator: ".").map { Int($0) ?? 0 }
    }
    let x = parts(a), y = parts(b)
    for i in 0..<max(x.count, y.count) {
        let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
        if l != r { return l > r }
    }
    return false
}

final class Updater: ObservableObject {
    static let shared = Updater()
    static let api = URL(string: "https://api.github.com/repos/lshinkuro/poni/releases/latest")!
    @Published var latest: String?           // newer version available, e.g. "0.7.0"
    @Published var status = ""
    @Published var busy = false
    @Published var auto = UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(auto, forKey: "autoUpdate") }
    }
    private var dmg: (url: URL, sha256: String)?
    private var timer: Timer?

    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    var appURL: URL { Bundle.main.bundleURL.resolvingSymlinksInPath() }
    var viaHomebrew: Bool { appURL.path.contains("/Cellar/") }
    /// Formula this copy came from: "poni", or "baterai-safer" for installs from before the rename.
    var formula: String {
        let c = appURL.pathComponents
        return c.firstIndex(of: "Cellar").map { c[$0 + 1] } ?? "poni"
    }
    /// Local builds (swift build / .build) never update themselves.
    var updatable: Bool { !current.contains("dev") && Bundle.main.bundleIdentifier != nil && !appURL.path.contains("/.build/") }

    func start() {
        guard timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.check() }
        timer = .scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check(manual: Bool = false) {
        if manual { status = "Mengecek…" }
        URLSession.shared.dataTask(with: Self.api) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let asset = (json?["assets"] as? [[String: Any]])?.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }
            DispatchQueue.main.async {
                guard let tag else { if manual { self.status = "Gagal mengecek (offline?)" }; return }
                if let a = asset, let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)),
                   let d = (a["digest"] as? String)?.replacingOccurrences(of: "sha256:", with: "") { self.dmg = (u, d) }
                guard isNewer(tag, than: self.current) else {
                    self.latest = nil
                    if manual { self.status = "Sudah versi terbaru (v\(self.current))" }
                    return
                }
                let first = self.latest != tag
                self.latest = tag
                self.status = "v\(tag) tersedia"
                if first { Notch.shared.flash("Poni v\(tag) tersedia" + (self.auto && self.updatable ? " · memasang…" : "")) }
                // Don't restart under someone mid-session; the next check tries again.
                if self.auto, self.updatable, !Notch.shared.focus.running { self.install() }
            }
        }.resume()
    }

    func install() {
        guard let v = latest, updatable, !busy else { return }
        busy = true
        if viaHomebrew {
            status = "Memperbarui lewat Homebrew… (1–2 menit)"
            let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first(where: FileManager.default.isExecutableFile) ?? "/opt/homebrew/bin/brew"
            runAsync(brew, ["update", "--quiet"]) { _, _, _ in
                runAsync(brew, ["upgrade", self.formula]) { code, _, err in
                    let opt = URL(fileURLWithPath: (brew as NSString).deletingLastPathComponent + "/../opt/\(self.formula)/Poni.app").standardizedFileURL
                    code == 0 ? self.relaunch(opt, v) : self.fail(err.split(separator: "\n").last.map(String.init) ?? "brew upgrade gagal")
                }
            }
            return
        }
        guard let dmg else { fail("Rilis ini tidak punya DMG"); return }
        status = "Mengunduh v\(v)…"
        URLSession.shared.downloadTask(with: dmg.url) { file, _, error in
            guard let file else { DispatchQueue.main.async { self.fail(error?.localizedDescription ?? "Unduhan gagal") }; return }
            do {
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard hash == dmg.sha256 else { throw UpdateError("Checksum DMG tidak cocok, update dibatalkan") }
                try self.swap(dmgFile: file)
                DispatchQueue.main.async { self.relaunch(self.appURL, v) }
            } catch {
                DispatchQueue.main.async { self.fail((error as? UpdateError)?.message ?? error.localizedDescription) }
            }
        }.resume()
    }

    /// Mounts the DMG, copies the new app next to the current one, then replaces it in one step.
    private func swap(dmgFile: URL) throws {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("bs-update-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { _ = shRun("/usr/bin/hdiutil", "detach", mount.path, "-quiet"); try? fm.removeItem(at: mount) }
        guard shRun("/usr/bin/hdiutil", "attach", dmgFile.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path) == 0 else {
            throw UpdateError("DMG tidak bisa dibuka")
        }
        let staged = appURL.deletingLastPathComponent().appendingPathComponent(".Poni.update.app")
        try? fm.removeItem(at: staged)
        // Copies keep their own file name (an install from before the rename stays "Baterai Safer.app"),
        // so the helper daemon, which runs the binary by path, keeps working.
        guard shRun("/usr/bin/ditto", mount.appendingPathComponent("Poni.app").path, staged.path) == 0 else {
            throw UpdateError("Tidak bisa menyalin ke \(appURL.deletingLastPathComponent().path)")
        }
        _ = try fm.replaceItemAt(appURL, withItemAt: staged)
    }

    private func relaunch(_ app: URL, _ v: String) {
        status = "Diperbarui ke v\(v), memulai ulang…"
        Notch.shared.flash("Diperbarui ke v\(v) · memulai ulang")
        // A detached shell outlives us and opens the new copy once we've quit.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1.5; /usr/bin/open -n \"$0\"", app.path]
        try? p.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }

    private func fail(_ msg: String) {
        busy = false
        status = msg
        Notch.shared.flash("Update gagal: \(msg)")
    }
}

struct UpdateError: Error { let message: String; init(_ m: String) { message = m } }

/// Exit status of a short command; output is discarded.
@discardableResult
func shRun(_ args: String...) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

struct UpdateCard: View {
    @ObservedObject var u = Updater.shared

    var body: some View {
        Card(title: "Update", icon: "arrow.down.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versi \(u.current)").font(.system(size: 12.5, weight: .semibold))
                    if !u.status.isEmpty { Text(u.status).font(.caption).foregroundStyle(u.latest != nil ? Palette.green : .secondary) }
                }
                Spacer()
                if u.busy {
                    ProgressView().controlSize(.small)
                } else if let v = u.latest, u.updatable {
                    Button("Update ke v\(v)") { u.install() }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Button("Cek sekarang") { u.check(manual: true) }.controlSize(.small)
                }
            }
            Toggle("Pasang update otomatis", isOn: $u.auto).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small)
            Text(u.updatable ? (u.viaHomebrew ? "Lewat Homebrew (brew upgrade)" : "Diunduh dari GitHub Releases, diverifikasi SHA-256")
                 : "Build lokal: update otomatis nonaktif")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
