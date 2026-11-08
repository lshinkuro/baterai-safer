import SwiftUI

// First launch: the helper, which notch features to keep, and which macOS permissions they will ask
// for. Features that trigger permission prompts wait until this is done, so a fresh install isn't a
// wall of dialogs before the user knows what Poni is.

enum Onboarding {
    static let key = "onboarded"
    static var done: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Fresh installs only; anyone who already used Poni (history or helper present) skips it.
    static func showIfNeeded() {
        guard !done else { return }
        if FileManager.default.fileExists(atPath: Paths.history) || FileManager.default.fileExists(atPath: Paths.plist) {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        show()
    }

    static func show() { AppWindow.show("welcome", title: "Poni", size: NSSize(width: 640, height: 640)) { WelcomeView() } }

    static func finish() {
        UserDefaults.standard.set(true, forKey: key)
        Notch.shared.applyFeatures() // the chosen features start now, asking for their permissions
        AppWindow.close("welcome")
    }
}

struct WelcomeView: View {
    @AppStorage(FeatureFlags.key) private var featuresOff = "" // re-render when a chip changes
    @Local private var helperError = ""
    @Local private var checked = Date()                         // re-read the helper after installing

    var helperInstalled: Bool { _ = checked; return FileManager.default.fileExists(atPath: Paths.plist) && !Model.helperBroken }

    /// Permission each notch feature will ask for, in the order a user meets them.
    static let permissions: [(NTab, String, String)] = [
        (.music, "music.note", "Automation untuk Spotify / Music, saat lagu diputar"),
        (.agenda, "calendar", "Kalender, saat tab Rapat dibuka"),
        (.ibadah, "moon.stars.fill", "Lokasi dan Notifikasi, untuk jadwal & pengingat sholat"),
        (.notes, "note.text", "Automation untuk Apple Notes, saat catatan disinkron"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Selamat datang di Poni")).font(.system(size: 22, weight: .semibold))
                        Text(tr("Jaga kesehatan baterai, plus notch yang berguna. Tiga langkah singkat.")).font(.system(size: 12)).foregroundStyle(.gray)
                    }
                }
                .padding(.bottom, 4)

                step(1, "Pasang helper", "Helper membatasi pengisian baterai dan tetap jalan saat Poni ditutup. macOS meminta password admin sekali.") {
                    if helperInstalled {
                        Label(tr("Helper terpasang"), systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                    } else {
                        NButton(icon: "lock.shield", title: "Pasang helper…", tint: Palette.accent, prominent: true) {
                            helperError = runAsAdmin("install-daemon")
                            checked = Date()
                        }
                        if !helperError.isEmpty { Text(helperError).font(.system(size: 11)).foregroundStyle(Palette.red) }
                    }
                }

                step(2, "Pilih fitur notch", "Matikan yang tidak kamu pakai. Bisa diubah kapan saja di Tools → Fitur.") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(NTab.allCases.filter { $0 != .more }, id: \.self) { tab in
                            FeatureChip(title: tab.title, icon: tab.icon,
                                        on: Binding(get: { FeatureFlags.isOn("\(tab)") }, set: { FeatureFlags.set("\(tab)", $0) }))
                        }
                    }
                }

                step(3, "Izin macOS", "Diminta satu per satu saat fiturnya pertama dipakai, bukan sekarang semua. Semua diproses di Mac ini.") {
                    let needed = Self.permissions.filter { $0.0.enabled }
                    if needed.isEmpty {
                        Text(tr("Fitur yang kamu pilih tidak butuh izin tambahan.")).font(.system(size: 12)).foregroundStyle(.gray)
                    }
                    ForEach(needed, id: \.0) { _, icon, text in
                        Label(tr(text), systemImage: icon).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                    }
                }

                HStack {
                    Spacer()
                    NButton(icon: "checkmark", title: "Mulai pakai Poni", tint: Palette.accent, prominent: true) { Onboarding.finish() }
                }
                .padding(.top, 4)
            }
        }
    }

    func step<C: View>(_ n: Int, _ title: String, _ info: String, @ViewBuilder content: () -> C) -> some View {
        NCard(padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.onAccent)
                    .frame(width: 26, height: 26).background(Palette.accent, in: Circle())
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr(title)).font(.system(size: 15, weight: .semibold))
                    Text(tr(info)).font(.system(size: 12)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                    content()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
