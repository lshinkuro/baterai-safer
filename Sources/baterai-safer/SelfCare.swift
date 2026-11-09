import SwiftUI
import CoreGraphics

// Lainnya → Self-care: a daily score over water, guided breaks and habits, a mood check-in, and
// gentle reminders (water, 20-20-20 eye breaks, stretching). Reminders are off until switched on, count only time actually spent at the Mac, and
// wait while a focus session or a meeting is on.

/// Consecutive days done, counting back from today (or from yesterday while today isn't done yet).
func streak(_ done: Set<String>, today: Date) -> Int {
    var day = done.contains(dayKey(today)) ? today : Calendar.current.date(byAdding: .day, value: -1, to: today)!
    var n = 0
    while done.contains(dayKey(day)) {
        n += 1
        day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
    }
    return n
}

/// How looked-after today is, 0…1: the average of water, breaks and (when there are any) habits.
func careScore(water: Int, goal: Int, breaks: Int, breakGoal: Int, habitsDone: Int, habits: Int) -> Double {
    var parts = [min(1, Double(water) / Double(max(goal, 1))), min(1, Double(breaks) / Double(max(breakGoal, 1)))]
    if habits > 0 { parts.append(Double(habitsDone) / Double(habits)) }
    return parts.reduce(0, +) / Double(parts.count)
}

struct Habit: Codable, Identifiable {
    var id = UUID()
    var name: String
    var done: Set<String> = []  // days (dayKey)
}

struct SelfCareData: Codable {
    var water: [String: Int] = [:] // day → glasses
    var waterGoal = 8
    var habits: [Habit] = []
    var breaks: [String: Int] = [:] // day → guided breaks finished
    var mood: [String: Int] = [:]   // day → 1…5

    init() {}

    // Fields added later are optional when reading, so an older selfcare.json keeps its habits.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        water = try c.decodeIfPresent([String: Int].self, forKey: .water) ?? [:]
        waterGoal = try c.decodeIfPresent(Int.self, forKey: .waterGoal) ?? 8
        habits = try c.decodeIfPresent([Habit].self, forKey: .habits) ?? []
        breaks = try c.decodeIfPresent([String: Int].self, forKey: .breaks) ?? [:]
        mood = try c.decodeIfPresent([String: Int].self, forKey: .mood) ?? [:]
    }
}

final class SelfCare: ObservableObject {
    static let shared = SelfCare()
    static let file = Paths.user + "/selfcare.json"
    static let breakGoal = 3

    enum Kind: String, CaseIterable {
        case water, eyes, stretch
        var title: String { ["Minum air", "Istirahat mata", "Peregangan"][index] }
        var icon: String { ["drop.fill", "eye", "figure.walk"][index] }
        var message: String { ["Waktunya minum air", "Lihat jauh 20 detik · istirahat mata", "Berdiri dan regangkan badan"][index] }
        var defaultMinutes: Int { [60, 20, 60][index] }
        static let choices = [20, 30, 45, 60, 90, 120]
        static let guided: [Kind] = [.eyes, .stretch]
        /// How long the guided break lasts; water has none.
        var seconds: Int? { [nil, 20, 60][index] }
        var steps: [String] {
            [[], ["Lihat benda yang jauh, sekitar 6 meter"],
             ["Putar bahu pelan-pelan", "Miringkan leher ke kiri dan kanan", "Rentangkan tangan ke atas", "Berdiri dan tarik napas dalam"]][index]
        }
        func step(elapsed: Double) -> String {
            guard let seconds, !steps.isEmpty else { return "" }
            return steps[max(0, min(steps.count - 1, Int(elapsed / (Double(seconds) / Double(steps.count)))))]
        }
        private var index: Int { Self.allCases.firstIndex(of: self)! }
    }

    @Published var on: Set<Kind> = Set((UserDefaults.standard.stringArray(forKey: "selfcareOn") ?? []).compactMap(Kind.init)) {
        didSet { UserDefaults.standard.set(on.map(\.rawValue), forKey: "selfcareOn"); restart() }
    }
    @Published var minutes: [String: Int] = UserDefaults.standard.dictionary(forKey: "selfcareMinutes") as? [String: Int] ?? [:] {
        didSet { UserDefaults.standard.set(minutes, forKey: "selfcareMinutes") }
    }
    @Published var data = load(SelfCare.file, SelfCareData()) {
        didSet { save(data, Self.file) }
    }
    @Published private(set) var activeBreak: Kind?
    @Published private(set) var breakEnds = Date()
    private var last: [Kind: Date] = [:]
    private var timer: Timer?
    private var breakTimer: Timer?

    func every(_ k: Kind) -> Int { minutes[k.rawValue] ?? k.defaultMinutes }

    var waterToday: Int { data.water[dayKey(Date())] ?? 0 }
    func addWater(_ n: Int) { data.water[dayKey(Date()), default: 0] = max(0, waterToday + n) }

    var breaksToday: Int { data.breaks[dayKey(Date())] ?? 0 }
    var moodToday: Int? { data.mood[dayKey(Date())] }
    func setMood(_ v: Int) { data.mood[dayKey(Date())] = v }
    var score: Double {
        let done = data.habits.filter { $0.done.contains(dayKey(Date())) }.count
        return careScore(water: waterToday, goal: data.waterGoal, breaks: breaksToday, breakGoal: Self.breakGoal, habitsDone: done, habits: data.habits.count)
    }
    /// The last seven days, oldest first.
    var lastWeek: [Date] { (0..<7).reversed().map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! } }

    /// Minutes until this reminder fires, nil when it's off.
    func nextIn(_ k: Kind, now: Date = Date()) -> Int? {
        guard on.contains(k), let l = last[k] else { return nil }
        return max(0, Int(((Double(every(k)) * 60 - now.timeIntervalSince(l)) / 60).rounded(.up)))
    }

    func startBreak(_ k: Kind) {
        guard let seconds = k.seconds else { return }
        breakTimer?.invalidate()
        activeBreak = k
        breakEnds = Date().addingTimeInterval(Double(seconds))
        breakTimer = .scheduledTimer(withTimeInterval: Double(seconds), repeats: false) { [weak self] _ in self?.finishBreak() }
    }

    func cancelBreak() {
        breakTimer?.invalidate()
        activeBreak = nil
    }

    private func finishBreak() {
        guard let k = activeBreak else { return }
        activeBreak = nil
        data.breaks[dayKey(Date()), default: 0] += 1
        if on.contains(k) { last[k] = Date() } // the break just taken counts: no reminder right after it
        Notch.shared.flash(tr("Istirahat selesai"), icon: k.icon)
    }

    func toggle(_ h: Habit) {
        guard let i = data.habits.firstIndex(where: { $0.id == h.id }) else { return }
        let d = dayKey(Date())
        if data.habits[i].done.contains(d) { data.habits[i].done.remove(d) } else { data.habits[i].done.insert(d) }
    }

    func start() {
        guard timer == nil else { return }
        restart()
        timer = .scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// A reminder counts from when it's switched on (or changed), not from some old timestamp.
    private func restart() { last = Dictionary(uniqueKeysWithValues: on.map { ($0, Date()) }) }

    private func tick() {
        guard !on.isEmpty, activeBreak == nil else { return }
        let now = Date()
        // Five minutes away from the keyboard and mouse is a break already: start every interval over.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= 300 { restart(); return }
        let n = Notch.shared
        if n.focus.running && !n.focus.onBreak { return } // don't break a focus session; resumes after it
        if let m = n.meet.next, m.start <= now, now < m.end { return }
        for k in Kind.allCases where on.contains(k) {
            guard now.timeIntervalSince(last[k] ?? now) >= Double(every(k)) * 60 else { continue }
            last[k] = now
            n.flash(tr(k.message), icon: k.icon, seconds: 8)
            break // one at a time; the others come on the next tick
        }
    }
}

struct SelfCareView: View {
    @ObservedObject var s = SelfCare.shared
    @AppStorage("selfcarePage") private var page = 0 // 0 hari ini, 1 kebiasaan, 2 minggu ini, 3 pengingat
    @Local private var newHabit = ""
    @Local private var editing: UUID?
    static let moods = [("😣", "Berat"), ("🙁", "Kurang baik"), ("😐", "Biasa"), ("🙂", "Baik"), ("😄", "Sangat baik")]
    static let suggestions = ["Tidur 7 jam", "Jalan kaki 20 menit", "Baca 10 halaman", "Tanpa HP sebelum tidur"]

    var body: some View {
        if let k = s.activeBreak {
            breakView(k)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    HStack(spacing: 1) {
                        ForEach(Array(["Hari ini", "Kebiasaan", "Minggu ini", "Pengingat"].enumerated()), id: \.offset) { i, t in
                            Button { withAnimation(Motion.ease) { page = i } } label: {
                                Text(tr(t)).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
                                    .foregroundStyle(page == i ? Palette.onAccent : .gray)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(page == i ? Palette.accent.opacity(0.9) : Color.clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    Spacer(minLength: 4)
                    Text("Jaga badan selama kerja di Mac").font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                }
                switch page {
                case 1: habits
                case 2: week
                case 3: reminders
                default: today
                }
            }
        }
    }

    func heading(_ text: String) -> some View {
        Text(tr(text)).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
    }

    // MARK: Hari ini

    var today: some View {
        HStack(spacing: 10) {
            NCard(padding: 12, glow: true) {
                let score = s.score
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Ring(value: score, color: Palette.accent, label: "\(Int((score * 100).rounded()))%", size: 58, line: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr(score >= 1 ? "Hari ini terjaga 🎉" : score >= 0.5 ? "Sudah separuh jalan" : "Yuk mulai dari segelas air")).font(.system(size: 13, weight: .semibold))
                            Text("Dari air, istirahat, dan kebiasaan").font(.system(size: 11)).foregroundStyle(.gray)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Text("Mood").font(.system(size: 11)).foregroundStyle(.gray)
                        Spacer(minLength: 0)
                        ForEach(Self.moods.indices, id: \.self) { i in
                            let on = s.moodToday == i + 1
                            Button { s.setMood(i + 1) } label: {
                                Text(Self.moods[i].0).font(.system(size: 15)).frame(width: 28, height: 26)
                                    .background(on ? Palette.accent.opacity(0.55) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).tip(Self.moods[i].1)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            NCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    heading("AIR HARI INI")
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(s.waterToday)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
                        Text("/ \(s.data.waterGoal) " + tr("gelas")).font(.system(size: 11)).foregroundStyle(.gray)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(13), spacing: 3), count: 8), alignment: .leading, spacing: 3) {
                        ForEach(0..<s.data.waterGoal, id: \.self) { i in
                            Image(systemName: i < s.waterToday ? "drop.fill" : "drop").font(.system(size: 11))
                                .foregroundStyle(i < s.waterToday ? Palette.accent : .gray)
                        }
                    }
                    .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        NButton(icon: "plus", title: "Segelas", tint: Palette.accent, prominent: true) { s.addWater(1) }
                        NButton(icon: "minus") { s.addWater(-1) }.tip("Kurangi")
                    }
                }
            }
            .frame(width: 164)
            NCard(padding: 12) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            heading("ISTIRAHAT")
                            Spacer()
                            Text("\(s.breaksToday)/\(SelfCare.breakGoal)").font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.gray)
                        }
                        ForEach(SelfCare.Kind.guided, id: \.self) { k in breakRow(k, ctx.date) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    func breakRow(_ k: SelfCare.Kind, _ now: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: k.icon).font(.system(size: 12)).frame(width: 18).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(tr(k.title)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(s.nextIn(k, now: now).map { String(format: tr("Pengingat %@ mnt lagi"), "\($0)") } ?? tr("Pengingat mati"))
                    .font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
            }
            Spacer(minLength: 2)
            NButton(icon: "play.fill", title: "Mulai", tint: Palette.accent) { withAnimation(Motion.ease) { s.startBreak(k) } }
        }
    }

    func breakView(_ k: SelfCare.Kind) -> some View {
        NCard(padding: 14, glow: true) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let total = Double(k.seconds ?? 1), left = max(0, s.breakEnds.timeIntervalSince(ctx.date))
                HStack(spacing: 24) {
                    Ring(value: left / total, color: Palette.accent, label: "\(Int(left.rounded(.up)))", size: 104, line: 9)
                    VStack(alignment: .leading, spacing: 8) {
                        heading(k.title.uppercased())
                        Text(tr(k.step(elapsed: total - left))).font(.system(size: 20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        NButton(icon: "xmark", title: "Batal") { withAnimation(Motion.ease) { s.cancelBreak() } }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Kebiasaan

    var habits: some View {
        HStack(spacing: 10) {
            NCard(padding: 12) {
                if s.data.habits.isEmpty {
                    Placeholder(icon: "checklist", title: "Belum ada kebiasaan", subtitle: "Mulai dari satu yang kecil")
                } else {
                    ViewThatFits(in: .vertical) {
                        habitRows
                        ScrollView(showsIndicators: false) { habitRows }
                    }
                }
            }
            NCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    heading(editing == nil ? "TAMBAH KEBIASAAN" : "UBAH KEBIASAAN")
                    HStack(spacing: 6) {
                        TextField(tr("Kebiasaan baru…"), text: $newHabit).textFieldStyle(.plain).font(.system(size: 12)).onSubmit(submit)
                        NButton(icon: editing == nil ? "plus" : "checkmark") { submit() }
                            .tip(editing == nil ? "Tambah kebiasaan" : "Simpan").disabled(newHabit.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.leading, 10).padding(.trailing, 3).padding(.vertical, 3)
                    .background(Color.white.opacity(0.07), in: Capsule())
                    ForEach(Self.suggestions.filter { t in !s.data.habits.contains { $0.name == tr(t) } }.prefix(3), id: \.self) { t in
                        Button { s.data.habits.append(Habit(name: tr(t))) } label: {
                            Label(tr(t), systemImage: "plus").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 210)
        }
    }

    var habitRows: some View {
        VStack(spacing: 4) {
            ForEach(s.data.habits) { h in habitRow(h) }
        }
    }

    func habitRow(_ h: Habit) -> some View {
        let done = h.done.contains(dayKey(Date())), n = streak(h.done, today: Date())
        return HStack(spacing: 8) {
            Button { s.toggle(h) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                    .foregroundStyle(done ? Palette.accent : .gray)
            }
            .buttonStyle(.plain).tip(done ? "Belum" : "Selesai hari ini")
            Text(h.name).font(.system(size: 12)).lineLimit(1).strikethrough(done, color: .gray)
            Spacer()
            HStack(spacing: 3) {
                ForEach(s.lastWeek, id: \.self) { d in
                    Circle().fill(h.done.contains(dayKey(d)) ? Palette.accent : Color.white.opacity(0.13)).frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)
            Text(n > 0 ? "🔥 \(n)" : "").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 36, alignment: .trailing)
            Menu {
                Button(tr("Ubah")) { editing = h.id; newHabit = h.name }
                Button(role: .destructive) { remove(h) } label: { Label(tr("Hapus"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tip("Lainnya")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(editing == h.id ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            Button(tr("Ubah")) { editing = h.id; newHabit = h.name }
            Button(tr("Hapus")) { remove(h) }
        }
    }

    func remove(_ h: Habit) {
        guard confirm(String(format: tr("Hapus %@?"), h.name), "Catatan dan streak kebiasaan ini ikut terhapus.", "Hapus") else { return }
        s.data.habits.removeAll { $0.id == h.id }
        if editing == h.id { editing = nil; newHabit = "" }
    }

    func submit() {
        let name = newHabit.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let i = s.data.habits.firstIndex(where: { $0.id == editing }) { s.data.habits[i].name = name } else { s.data.habits.append(Habit(name: name)) }
        editing = nil
        newHabit = ""
    }

    // MARK: Minggu ini

    var week: some View {
        HStack(spacing: 10) {
            bars("AIR MINUM") { s.data.water[$0] ?? 0 }
            bars("ISTIRAHAT") { s.data.breaks[$0] ?? 0 }
            NCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    heading("MOOD")
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        ForEach(s.lastWeek, id: \.self) { d in
                            VStack(spacing: 4) {
                                Text(s.data.mood[dayKey(d)].map { Self.moods[max(0, min(4, $0 - 1))].0 } ?? "·").font(.system(size: 15)).frame(height: 22)
                                Text(weekday(d)).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    func weekday(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).locale(appLocale)) }

    func bars(_ title: String, _ value: @escaping (String) -> Int) -> some View {
        let peak = max(s.lastWeek.map { value(dayKey($0)) }.max() ?? 0, 1)
        return NCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                heading(title)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(s.lastWeek, id: \.self) { d in
                        let v = value(dayKey(d))
                        VStack(spacing: 3) {
                            Text(v > 0 ? "\(v)" : "").font(.system(size: 9, weight: .semibold)).monospacedDigit()
                            RoundedRectangle(cornerRadius: 4).fill(Palette.accent.gradient).frame(height: max(2, 56 * CGFloat(v) / CGFloat(peak)))
                            Text(weekday(d)).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: Pengingat

    var reminders: some View {
        HStack(spacing: 10) {
            NCard(padding: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    heading("PENGINGAT")
                    ForEach(SelfCare.Kind.allCases, id: \.self) { k in
                        HStack(spacing: 8) {
                            Image(systemName: k.icon).font(.system(size: 11)).frame(width: 16).foregroundStyle(s.on.contains(k) ? Palette.accent : .gray)
                            Text(tr(k.title)).font(.system(size: 12)).lineLimit(1)
                            Spacer()
                            Menu {
                                ForEach(SelfCare.Kind.choices, id: \.self) { m in Button(String(format: tr("Tiap %@ menit"), "\(m)")) { s.minutes[k.rawValue] = m } }
                            } label: {
                                Text(String(format: tr("%@ mnt"), "\(s.every(k))")).font(.system(size: 11)).foregroundStyle(.gray)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            Toggle("", isOn: Binding(get: { s.on.contains(k) }, set: { if $0 { s.on.insert(k) } else { s.on.remove(k) } }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Palette.accent)
                                .accessibilityLabel(tr(k.title))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            NCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    heading("TARGET AIR")
                    HStack(spacing: 8) {
                        NButton(icon: "minus") { s.data.waterGoal = max(4, s.data.waterGoal - 1) }.tip("Kurangi")
                        Text("\(s.data.waterGoal) " + tr("gelas")).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        NButton(icon: "plus") { s.data.waterGoal = min(16, s.data.waterGoal + 1) }.tip("Tambah")
                    }
                    Spacer(minLength: 0)
                    Text(tr("Hanya dihitung saat kamu memakai Mac; ditunda selama Fokus dan rapat."))
                        .font(.system(size: 10)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 220)
        }
    }
}
