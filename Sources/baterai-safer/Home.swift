import SwiftUI

// "Home" tab: the user picks which small cards it shows.

struct HomeView: View {
    @ObservedObject var m: NowPlaying
    @ObservedObject var f: Focus
    @ObservedObject var a = AgendaModel.shared
    @ObservedObject var care = SelfCare.shared
    @ObservedObject var prayer = Ibadah.shared
    @ObservedObject var ramadan = Ramadan.shared
    @ObservedObject var study = LangModel.shared
    @ObservedObject var todos = TodoModel.shared
    @Local private var newTodo = ""
    @Local private var drag = TabDrag<String>()
    @Local private var dragEnded = Date.distantPast
    @ObservedObject var notes = Notch.shared.notes
    @ObservedObject var clips = Notch.shared.clips
    @ObservedObject var git = Notch.shared.git
    @ObservedObject var shelf = Notch.shared.shelf
    @ObservedObject var sys = Notch.shared.sys
    @AppStorage("morePage") private var morePage = ""
    @AppStorage("homeWidgets") private var stored = "music,calendar,todo"

    static let all: [(id: String, icon: String, title: String, tab: NTab)] = [
        ("music", "music.note", "Musik", .music), ("calendar", "calendar", "Kalender", .agenda),
        ("todo", "checkmark.circle", "Todo", .more), ("habits", "checklist", "Kebiasaan", .more), ("focus", "timer", "Fokus", .focus),
        ("ibadah", "moon.stars.fill", "Ibadah", .ibadah), ("notes", "note.text", "Catatan", .notes),
        ("clipboard", "doc.on.clipboard", "Clipboard", .clipboard), ("git", "arrow.triangle.branch", "Git", .git),
        ("stats", "gauge.medium", "Stats", .stats), ("water", "drop.fill", "Air minum", .more),
        ("shelf", "tray.full", "Shelf", .shelf), ("ai", "sparkles", "AI", .ai), ("dev", "curlybraces", "Dev Utils", .dev),
        ("lang", "character.book.closed.fill", "Belajar Bahasa", .more),
    ]

    var chosen: [String] { stored.split(separator: ",").map(String.init) }
    // Features switched off in Tools don't get a card (their background work is stopped).
    var shown: [(id: String, icon: String, title: String, tab: NTab)] { chosen.compactMap { id in Self.all.first { $0.id == id && $0.tab.enabled } } }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(tr(greeting(ctx.date))).font(.system(size: 15, weight: .semibold))
                        Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide).locale(appLocale)).font(.system(size: 12)).foregroundStyle(.gray)
                    }
                }
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
                    HStack(spacing: 10) { ForEach(shown, id: \.id) { widget($0) } }
                        .coordinateSpace(name: "homeCards")
                } else {
                    // More than fit: the fifth card peeks in so it's clear the row scrolls.
                    GeometryReader { geo in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(shown, id: \.id) { widget($0, width: 165) } }
                                .coordinateSpace(name: "homeCards")
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

    func widget(_ w: (id: String, icon: String, title: String, tab: NTab), width: CGFloat? = nil) -> some View {
        let n = CGFloat(shown.count), grabbed = drag.tab == w.id
        let step = width.map { $0 + 10 } ?? (NotchView.open.width - 36 + 10) / max(n, 1) // card plus gap
        return NCard(padding: 12, glow: true) {
            VStack(alignment: .leading, spacing: 10) {
                Button { if drag.tab == nil, Date().timeIntervalSince(dragEnded) > 0.25 { open(w.id, w.tab) } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: w.icon).font(.system(size: 10, weight: .semibold))
                        Text(tr(w.title).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).lineLimit(1)
                        Spacer(minLength: 4)
                        if let n = w.id == "calendar" ? a.today.count : w.id == "todo" ? todos.open.count : nil, n > 0 { Text("\(n)").font(.system(size: 10, weight: .semibold)).monospacedDigit() }
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.gray).contentShape(Rectangle())
                }
                .buttonStyle(.plain).tip("Klik untuk buka, seret untuk mengubah urutan")
                .simultaneousGesture(reorder(w.id, step: step)) // a Button swallows the card's own drag
                .accessibilityAction(named: tr("Geser ke kiri")) { move(w.id, by: -1) }
                .accessibilityAction(named: tr("Geser ke kanan")) { move(w.id, by: 1) }
                card(w.id).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background {
            // Same album-art wash as the Musik tab.
            if w.id == "music", !m.title.isEmpty, let art = m.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).blur(radius: 40).opacity(0.45).saturation(1.4)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .gesture(reorder(w.id, step: step)) // lower priority than the card's own controls (scrubber, text fields)
        .frame(width: width)
        .scaleEffect(grabbed ? 1.03 : 1)
        .offset(x: grabbed ? drag.offset : 0)
        .zIndex(grabbed ? 1 : 0)
    }

    func reorder(_ id: String, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("homeCards"))
            .onChanged { drag.update(id, $0.translation.width, step: step, items: shown.map(\.id)) { move(id, by: $0) } }
            .onEnded { _ in // a release over the header also presses its button; the time check in widget ignores that
                dragEnded = Date()
                withAnimation(Motion.snap) { drag = TabDrag() }
            }
    }

    func move(_ id: String, by d: Int) {
        let visible = shown.map(\.id)
        stored = movedTab(chosen, id, by: d) { visible.contains($0) }.joined(separator: ",")
    }

    func greeting(_ d: Date) -> String {
        switch Calendar.current.component(.hour, from: d) {
        case 4..<11: "Selamat pagi"
        case 11..<15: "Selamat siang"
        case 15..<18: "Selamat sore"
        default: "Selamat malam"
        }
    }

    func open(_ id: String, _ tab: NTab) {
        if tab == .more { morePage = ["lang", "todo"].contains(id) ? id : "selfcare" }
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
        case "lang": language
        case "todo": todo
        case "ai": launcher("sparkles", "Tanya AI", .ai)
        case "dev": launcher("curlybraces", "JSON, Base64, UUID, dan lainnya", .dev)
        default: focus
        }
    }

    @ViewBuilder var music: some View {
        if m.app == nil || m.title.isEmpty {
            VStack(spacing: 8) {
                Placeholder(icon: "music.note", title: "Tidak ada musik")
                if let p = NowPlaying.installed.first {
                    NButton(icon: "play.fill", title: String(format: tr("Putar di %@"), p.name), tint: Palette.accent, prominent: true) { m.play(p.id) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    AlbumArt(m: m, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(m.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if m.playing { Equalizer(color: .white.opacity(0.8)) }
                }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Meter(value: m.duration > 0 ? min(1, m.now(ctx.date) / m.duration) : 0, color: .white.opacity(0.85))
                }
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
            Placeholder(icon: "calendar.badge.exclamationmark", title: "Izin Kalender ditolak")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Date(), format: .dateTime.day().locale(appLocale)).font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    Text(Date(), format: .dateTime.weekday(.wide).locale(appLocale)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                }
                if events.isEmpty { note("Tidak ada acara hari ini") }
                ForEach(events.prefix(3), id: \.eventIdentifier) { e in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: e.calendar.cgColor)).frame(width: 3, height: 16)
                        Text(e.title ?? "").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Group {
                            if e.isAllDay {
                                Text("penuh")
                            } else {
                                Text(e.startDate, format: .dateTime.hour().minute().locale(appLocale))
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit().fixedSize()
                    }
                }
                if events.count > 3 { note(String(format: tr("+%@ lainnya"), "\(events.count - 3)")) }
            }
        }
    }

    @ViewBuilder var habits: some View {
        if care.data.habits.isEmpty {
            Placeholder(icon: "checklist", title: "Belum ada kebiasaan", subtitle: "Tambah di Lainnya → Self-care")
        } else {
            let total = care.data.habits.count, finished = care.data.habits.filter { $0.done.contains(dayKey(Date())) }.count
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Ring(value: Double(finished) / Double(total), color: Palette.accent, label: "\(finished)/\(total)", size: 46, line: 5)
                    Text(finished == total ? "Semua beres hari ini" : "\(total - finished) lagi hari ini").font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
                // Short lists stay still; a long one scrolls.
                ViewThatFits(in: .vertical) {
                    habitRows
                    ScrollView(showsIndicators: false) { habitRows }
                }
            }
        }
    }

    var habitRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(care.data.habits) { h in
                let done = h.done.contains(dayKey(Date()))
                Button { care.toggle(h) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 13)).foregroundStyle(done ? Palette.accent : .gray)
                        Text(h.name).font(.system(size: 12)).lineLimit(1).strikethrough(done, color: .gray)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            let fast = ramadan.fasting(ctx.date) ? prayer.fastNext(after: ctx.date) : nil
            let next = prayer.next(after: ctx.date), t = fast?.date ?? next.1
            let mins = Int(t.timeIntervalSince(ctx.date) / 60) + 1
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(fast?.title ?? next.0.title)).font(.system(size: 22, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(prayer.clock(t)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Palette.accent)
                Text(String(format: tr("%@ lagi"), mins >= 60 ? String(format: tr("%@j %@m"), "\(mins / 60)", "\(mins % 60)") : "\(mins)m"))
                    .font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder var recentNotes: some View {
        if notes.notes.isEmpty {
            Placeholder(icon: "note.text", title: "Belum ada catatan")
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
            Placeholder(icon: "doc.on.clipboard", title: "Clipboard masih kosong")
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
            Placeholder(icon: "arrow.triangle.branch", title: "Belum ada repo")
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
        let b = Battery.read()
        return VStack(alignment: .leading, spacing: 7) {
            meter("Baterai", Double(b.percent) / 100, color: b.percent <= 20 && !b.ac ? Palette.red : Palette.accent)
            meter("CPU", sys.cpu)
            meter("Memori", sys.memUsed / sys.memTotal)
            meter("Disk", sys.diskTotal > 0 ? 1 - sys.diskFree / sys.diskTotal : 0)
        }
        .frame(maxHeight: .infinity)
    }

    func meter(_ title: String, _ v: Double, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tr(title)).font(.system(size: 11)).foregroundStyle(.gray)
                Spacer()
                Text("\(Int(v * 100))%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            Meter(value: v, color: color ?? (v > 0.85 ? Palette.red : Palette.accent))
        }
    }

    var water: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(care.waterToday)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text("/ \(care.data.waterGoal) " + tr("gelas")).font(.system(size: 11)).foregroundStyle(.gray)
            }
            Meter(value: min(1, Double(care.waterToday) / Double(max(1, care.data.waterGoal))), color: Palette.accent)
            NButton(icon: "plus", title: "Segelas", tint: Palette.accent, prominent: true) { care.addWater(1) }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder var shelfFiles: some View {
        if shelf.files.isEmpty {
            Placeholder(icon: "tray.full", title: "Shelf masih kosong")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shelf.files.prefix(5), id: \.self) { f in
                    Text(f.lastPathComponent).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                }
                if shelf.files.count > 5 { note(String(format: tr("+%@ lainnya"), "\(shelf.files.count - 5)")) }
            }
        }
    }

    var todo: some View {
        VStack(alignment: .leading, spacing: 8) {
            if todos.open.isEmpty {
                Placeholder(icon: "checkmark.circle", title: todos.items.isEmpty ? "Belum ada tugas" : "Semua beres")
            } else {
                ViewThatFits(in: .vertical) {
                    todoRows
                    ScrollView(showsIndicators: false) { todoRows }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            HStack(spacing: 4) {
                TextField(tr("Tugas baru…"), text: $newTodo).textFieldStyle(.plain).font(.system(size: 12)).onSubmit { todos.add(newTodo); newTodo = "" }
                Button { todos.add(newTodo); newTodo = "" } label: { Image(systemName: "plus.circle.fill").font(.system(size: 16)).foregroundStyle(Palette.accent) }
                    .buttonStyle(.plain).tip("Tambah tugas").disabled(newTodo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 10).padding(.trailing, 3).padding(.vertical, 3)
            .background(Color.white.opacity(0.07), in: Capsule())
        }
    }

    var todoRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(todos.open) { t in
                Button { withAnimation(Motion.ease) { todos.toggle(t) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(.gray)
                        Text(t.text).font(.system(size: 12)).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var language: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Ring(value: min(1, Double(study.today) / Double(max(study.s.target, 1))), color: Palette.accent, label: "\(study.today)", size: 46, line: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(study.s.lang.flag) \(tr(study.s.lang.title))").font(.system(size: 12, weight: .semibold))
                    Text("\(study.dueCount) perlu diulang").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            NButton(icon: "play.fill", title: "Latihan", tint: Palette.accent, prominent: true) { open("lang", .more) }
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
