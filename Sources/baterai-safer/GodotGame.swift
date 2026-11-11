import SwiftUI
import CryptoKit

/// A game built elsewhere (Godot) and shipped as a DMG on its own GitHub Releases. Poni only downloads
/// it once into Application Support and opens it; the game runs in its own window.
final class GodotGame: ObservableObject {
    static let shared = GodotGame()
    static let repo = "lshinkuro/desa-bahagia" // shortcut: one game, owner/repo hard-coded; make it a list when a second game ships
    static let title = "Desa Bahagia"
    static let dir = URL(fileURLWithPath: Paths.user + "/games")
    @Published var status = ""
    @Published var busy = false
    @Published var latest: (tag: String, url: URL, sha256: String?)?

    var app: URL? {
        (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil))?.first { $0.pathExtension == "app" }
    }
    /// Read from the installed bundle, so a copy placed by hand or an older Poni is still compared correctly.
    var installedVersion: String { app.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "" }
    var updateAvailable: Bool { app != nil && latest.map { isNewer($0.tag, than: installedVersion) } == true }

    func check() {
        guard latest == nil else { return }
        URLSession.shared.dataTask(with: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard let tag = json?["tag_name"] as? String,
                  let a = (json?["assets"] as? [[String: Any]])?.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                  let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return }
            let d = (a["digest"] as? String)?.replacingOccurrences(of: "sha256:", with: "")
            DispatchQueue.main.async { self.latest = (tag, u, d) }
        }.resume()
    }

    func play() {
        if let app { NSWorkspace.shared.open(app) }
    }

    func remove() {
        objectWillChange.send()
        try? FileManager.default.removeItem(at: Self.dir)
        status = ""
    }

    func install() {
        guard let latest, !busy else { return }
        busy = true
        status = tr("Mengunduh…")
        URLSession.shared.downloadTask(with: latest.url) { file, _, error in
            do {
                guard let file else { throw UpdateError(error?.localizedDescription ?? tr("Unduhan gagal")) }
                if let want = latest.sha256 {
                    let hash = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
                    guard hash == want else { throw UpdateError(tr("Checksum DMG tidak cocok")) }
                }
                try self.copyApp(from: file)
                DispatchQueue.main.async { self.busy = false; self.status = "" }
            } catch {
                DispatchQueue.main.async { self.busy = false; self.status = (error as? UpdateError)?.message ?? error.localizedDescription }
            }
        }.resume()
    }

    /// Mounts the DMG and copies the first .app in it into `dir`, replacing the old copy.
    private func copyApp(from dmg: URL) throws {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("poni-game-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer { _ = shRun("/usr/bin/hdiutil", "detach", mount.path, "-quiet"); try? fm.removeItem(at: mount) }
        guard shRun("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path) == 0 else {
            throw UpdateError(tr("DMG tidak bisa dibuka"))
        }
        guard let src = try fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError(tr("Tidak ada aplikasi di dalam DMG"))
        }
        try? fm.removeItem(at: Self.dir)
        try fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        guard shRun("/usr/bin/ditto", src.path, Self.dir.appendingPathComponent(src.lastPathComponent).path) == 0 else {
            throw UpdateError(tr("Tidak bisa menyalin game"))
        }
    }
}

struct GodotGameView: View {
    @ObservedObject private var g = GodotGame.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(GodotGame.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text("Dibuat dengan Godot, jalan di jendela sendiri. Diunduh sekali dari GitHub.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            if g.updateAvailable, let t = g.latest?.tag {
                Text(String(format: tr("Versi baru %@ tersedia"), t)).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
            }
            HStack(spacing: 8) {
                if g.app != nil {
                    NButton(icon: "play.fill", title: "Main", tint: Palette.accent, prominent: true) { g.play() }
                }
                if g.app == nil || g.updateAvailable {
                    NButton(icon: g.busy ? "hourglass" : "arrow.down.circle",
                            title: g.busy ? "Mengunduh…" : (g.app == nil ? "Unduh" : "Perbarui"),
                            tint: Palette.accent, prominent: g.app == nil) { g.install() }
                        .disabled(g.busy || g.latest == nil)
                }
                if g.app != nil {
                    NButton(icon: "trash", title: "Hapus", tint: .white.opacity(0.6)) { g.remove() }.disabled(g.busy)
                }
            }
            if !g.status.isEmpty { Text(g.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)) }
            if let t = g.app == nil ? g.latest?.tag : g.installedVersion, !t.isEmpty {
                Text("Versi \(t)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.top, 4)
        .onAppear { g.check() }
    }
}
