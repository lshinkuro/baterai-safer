import SwiftUI

// "Home" tab: the user picks which small cards it shows.

struct HomeView: View {
    @ObservedObject var m: NowPlaying
    @ObservedObject var f: Focus
    @ObservedObject var a = AgendaModel.shared
    @ObservedObject var care = SelfCare.shared
    @ObservedObject var prayer = Ibadah.shared
    @ObservedObject var notes = Notch.shared.notes
    @ObservedObject var clips = Notch.shared.clips
    @ObservedObject var git = Notch.shared.git
    @ObservedObject var shelf = Notch.shared.shelf
    @ObservedObject var sys = Notch.shared.sys
    @AppStorage("morePage") private var morePage = ""
    @AppStorage("homeWidgets") private var stored = "music,calendar,habits"

    static let all: [(id: String, icon: String, title: String, tab: NTab)] = [
        ("music", "music.note", "Musik", .music), ("calendar", "calendar", "Kalender", .agenda),
        ("habits", "checklist", "Kebiasaan", .more), ("focus", "timer", "Fokus", .focus),
        ("ibadah", "moon.stars.fill", "Ibadah", .ibadah), ("notes", "note.text", "Catatan", .notes),
        ("clipboard", "doc.on.clipboard", "Clipboard", .clipboard), ("git", "arrow.triangle.branch", "Git", .git),
        ("stats", "gauge.medium", "Stats", .stats), ("water", "drop.fill", "Air minum", .more),
        ("shelf", "tray.full", "Shelf", .shelf), ("ai", "sparkles", "AI", .ai), ("dev", "curlybraces", "Dev Utils", .dev),
    ]

    var chosen: [String] { stored.split(separator: ",").map(String.init) }

    var body: some View {
        // Features switched off in Tools don't get a card (their background work is stopped).
        let shown = chosen.compactMap { id in Self.all.first { $0.id == id && $0.tab.enabled } }
        VStack(spacing: 8) {
            HStack {
                Spacer()
                Menu {
                    ForEach(Self.all, id: \.id) { w in
                        Button { toggle(w.id) } label: { Label(tr(w.title), systemImage: chosen.contains(w.id) ? "checkmark" : w.icon) }
                    }
                } label: { Label("Atur", systemImage: "slider.horizontal.3") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11, weight: .semibold))
                    .tip("Pilih isi Home")
            }
            if shown.isEmpty {
                Placeholder(icon: "house.fill", title: "Home masih kosong", subtitle: "Pilih isinya lewat Atur")
            } else {
                if shown.count <= 4 {
                    HStack(spacing: 10) { ForEach(shown, id: \.id) { widget($0.id, $0.title, $0.tab) } }
                } else {
                    // More than fit: the fifth card peeks in so it's clear the row scrolls.
                    GeometryReader { geo in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(shown, id: \.id) { widget($0.id, $0.title, $0.tab).frame(width: 165) } }
                                .frame(height: geo.size.height)
                        }
                    }
                }
            }
        }
        .onAppear {
            if Onboarding.done && chosen.contains("calendar") { a.start() } // Calendar permission waits for the welcome screen
            if chosen.contains("git") { git.refresh() }
            if chosen.contains("stats") { sys.start() }
        }
        .onDisappear { if Notch.shared.state.tab != .stats { sys.stop() } } // the Stats tab keeps the same poller going
    }

    func widget(_ id: String, _ title: String, _ tab: NTab) -> some View {
        NCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button { open(id, tab) } label: {
                    HStack(spacing: 3) {
                        Text(tr(title).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.gray).contentShape(Rectangle())
                }
                .buttonStyle(.plain).tip("Buka")
                card(id).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    func open(_ id: String, _ tab: NTab) {
        if tab == .more { morePage = "selfcare" } // the only cards that live under Lainnya
        withAnimation(Motion.snap) { Notch.shared.state.tab = tab }
    }

    func toggle(_ id: String) {
        stored = (chosen.contains(id) ? chosen.filter { $0 != id } : chosen + [id]).joined(separator: ",")
        if id == "calendar", Onboarding.done { a.start() }
        if id == "git" { git.refresh() }
        if id == "stats" { chosen.contains(id) ? sys.start() : sys.stop() }
    }

    @ViewBuilder func card(_ id: String) -> some View {
        switch id {
        case "music": music
        case "calendar": calendar
        case "habits": habits
        case "ibadah": ibadah
        case "notes": recentNotes
        case "clipboard": clipboard
        case "git": repos
        case "stats": stats
        case "water": water
        case "shelf": shelfFiles
        case "ai": launcher("sparkles", "Tanya AI", .ai)
        case "dev": launcher("curlybraces", "JSON, Base64, UUID, dan lainnya", .dev)
        default: focus
        }
    }

    @ViewBuilder var music: some View {
        if m.app == nil || m.title.isEmpty {
            note("Tidak ada musik")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AlbumArt(m: m, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(m.artist).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    musicControl("backward.fill", 13, "Sebelumnya") { m.send("previous track") }
                    musicControl(m.playing ? "pause.fill" : "play.fill", 20, m.playing ? "Jeda" : "Putar") { m.togglePlay() }
                    musicControl("forward.fill", 13, "Berikutnya") { m.send("next track") }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder var calendar: some View {
        let events = a.today
        if a.access == false {
            note("Izin Kalender ditolak")
        } else if events.isEmpty {
            note("Tidak ada acara hari ini")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(events.prefix(5), id: \.eventIdentifier) { e in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: e.calendar.cgColor)).frame(width: 3, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title ?? "").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            if e.isAllDay {
                                Text("penuh").font(.system(size: 10)).foregroundStyle(.gray)
                            } else {
                                Text(e.startDate, format: .dateTime.hour().minute().locale(appLocale)).font(.system(size: 10)).foregroundStyle(.gray)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder var habits: some View {
        if care.data.habits.isEmpty {
            note("Tambah kebiasaan di Lainnya → Self-care")
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(care.data.habits) { h in
                        let done = h.done.contains(dayKey(Date()))
                        Button { care.toggle(h) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 13)).foregroundStyle(done ? Palette.accent : .gray)
                                Text(h.name).font(.system(size: 12)).lineLimit(1).strikethrough(done, color: .gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var focus: some View {
        VStack(spacing: 8) {
            Ring(value: f.remaining / f.total, color: f.onBreak ? Palette.green : Palette.accent, label: f.clock, size: 76, line: 7)
            NButton(icon: f.running ? "pause.fill" : "play.fill", title: f.running ? "Jeda" : "Mulai", tint: Palette.accent, prominent: true) { f.toggle() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var ibadah: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let (p, t) = prayer.next(after: ctx.date)
            let mins = Int(t.timeIntervalSince(ctx.date) / 60) + 1
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(p.title)).font(.system(size: 22, weight: .semibold))
                Text(prayer.clock(t)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Palette.accent)
                Text(String(format: tr("%@ lagi"), mins >= 60 ? String(format: tr("%@j %@m"), "\(mins / 60)", "\(mins % 60)") : "\(mins)m"))
                    .font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
            }
        }
    }

    @ViewBuilder var recentNotes: some View {
        if notes.notes.isEmpty {
            note("Belum ada catatan")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(notes.notes.sorted { $0.updated > $1.updated }.prefix(5)) { n in
                    row(n.title) { notes.selected = n.id; open("notes", .notes) }
                }
            }
        }
    }

    @ViewBuilder var clipboard: some View {
        if clips.items.isEmpty {
            note("Clipboard masih kosong")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(clips.items.prefix(5)) { c in
                    row(c.text ?? tr("Gambar")) { clips.copy(c); Notch.shared.flash("Disalin") }
                }
            }
        }
    }

    @ViewBuilder var repos: some View {
        if git.repos.isEmpty {
            note("Belum ada repo")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(git.repos.prefix(4)) { r in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(r.status.branch).lineLimit(1)
                            if r.status.changes > 0 { Text("· \(r.status.changes)").foregroundStyle(Palette.amber) }
                        }
                        .font(.system(size: 10)).foregroundStyle(.gray)
                    }
                }
            }
        }
    }

    var stats: some View {
        VStack(alignment: .leading, spacing: 10) {
            meter("CPU", sys.cpu)
            meter("Memori", sys.memUsed / sys.memTotal)
        }
    }

    func meter(_ title: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tr(title)).font(.system(size: 11)).foregroundStyle(.gray)
                Spacer()
                Text("\(Int(v * 100))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            Meter(value: v, color: v > 0.85 ? Palette.red : Palette.accent)
        }
    }

    var water: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(care.waterToday)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text("/ \(care.data.waterGoal) " + tr("gelas")).font(.system(size: 11)).foregroundStyle(.gray)
            }
            NButton(icon: "plus", title: "Segelas", tint: Palette.accent, prominent: true) { care.addWater(1) }
        }
    }

    @ViewBuilder var shelfFiles: some View {
        if shelf.files.isEmpty {
            note("Shelf masih kosong")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shelf.files.prefix(5), id: \.self) { f in
                    Text(f.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                }
                if shelf.files.count > 5 { note(String(format: tr("+%@ lainnya"), "\(shelf.files.count - 5)")) }
            }
        }
    }

    func launcher(_ icon: String, _ text: String, _ tab: NTab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note(text)
            Spacer(minLength: 0)
            NButton(icon: icon, title: "Buka", tint: Palette.accent, prominent: true) { open("", tab) }
        }
    }

    func row(_ text: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines)).font(.system(size: 12)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func note(_ text: String) -> some View {
        Text(tr(text)).font(.system(size: 11)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
    }
}
