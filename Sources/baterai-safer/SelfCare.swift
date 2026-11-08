import SwiftUI
import CoreGraphics

// Lainnya → Self-care: gentle reminders (water, 20-20-20 eye breaks, stretching), a water counter and
// daily habits. Reminders are off until switched on, count only time actually spent at the Mac, and
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

struct Habit: Codable, Identifiable {
    var id = UUID()
    var name: String
    var done: Set<String> = []  // days (dayKey)
}

struct SelfCareData: Codable {
    var water: [String: Int] = [:] // day → glasses
    var waterGoal = 8
    var habits: [Habit] = []
}

final class SelfCare: ObservableObject {
    static let shared = SelfCare()
    static let file = Paths.user + "/selfcare.json"

    enum Kind: String, CaseIterable {
        case water, eyes, stretch
        var title: String { ["Minum air", "Istirahat mata", "Peregangan"][index] }
        var icon: String { ["drop.fill", "eye", "figure.walk"][index] }
        var message: String { ["Waktunya minum air", "Lihat jauh 20 detik · istirahat mata", "Berdiri dan regangkan badan"][index] }
        var defaultMinutes: Int { [60, 20, 60][index] }
        static let choices = [20, 30, 45, 60, 90, 120]
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
    private var last: [Kind: Date] = [:]
    private var timer: Timer?

    func every(_ k: Kind) -> Int { minutes[k.rawValue] ?? k.defaultMinutes }

    var waterToday: Int { data.water[dayKey(Date())] ?? 0 }
    func addWater(_ n: Int) { data.water[dayKey(Date()), default: 0] = max(0, waterToday + n) }

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
        guard !on.isEmpty else { return }
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
    @Local private var newHabit = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("AIR HARI INI")).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(s.waterToday)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        Text("/ \(s.data.waterGoal) " + tr("gelas")).font(.system(size: 12)).foregroundStyle(.gray)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<s.data.waterGoal, id: \.self) { i in
                            Image(systemName: i < s.waterToday ? "drop.fill" : "drop").font(.system(size: 11))
                                .foregroundStyle(i < s.waterToday ? Palette.accent : .gray)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        NButton(icon: "plus", title: "Segelas", tint: Palette.accent, prominent: true) { s.addWater(1) }
                        NButton(icon: "minus") { s.addWater(-1) }.tip("Kurangi")
                    }
                }
            }
            .frame(width: 190)

            NCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("PENGINGAT")).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
                    ForEach(SelfCare.Kind.allCases, id: \.self) { k in
                        HStack(spacing: 8) {
                            Image(systemName: k.icon).font(.system(size: 11)).frame(width: 16).foregroundStyle(s.on.contains(k) ? Palette.accent : .gray)
                            Text(tr(k.title)).font(.system(size: 12)).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer()
                            Menu {
                                ForEach(SelfCare.Kind.choices, id: \.self) { m in Button(String(format: tr("Tiap %@ menit"), "\(m)")) { s.minutes[k.rawValue] = m } }
                            } label: {
                                Text(String(format: tr("%@ mnt"), "\(s.every(k))")).font(.system(size: 11)).foregroundStyle(.gray)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            Toggle("", isOn: Binding(get: { s.on.contains(k) }, set: { if $0 { s.on.insert(k) } else { s.on.remove(k) } }))
                                .labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(Palette.accent)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(tr("Hanya dihitung saat kamu memakai Mac; ditunda selama Fokus dan rapat."))
                        .font(.system(size: 10)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                }
            }

            NCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("KEBIASAAN")).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(s.data.habits) { h in habitRow(h) }
                        }
                    }
                    HStack(spacing: 6) {
                        TextField(tr("Kebiasaan baru…"), text: $newHabit).textFieldStyle(.plain).font(.system(size: 12))
                            .onSubmit(add)
                        NButton(icon: "plus") { add() }.tip("Tambah kebiasaan").disabled(newHabit.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.leading, 10).padding(.trailing, 3).padding(.vertical, 3)
                    .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
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
            if n > 0 { Text("🔥 \(n)").font(.system(size: 11, weight: .semibold)).monospacedDigit() }
            Menu { Button(role: .destructive) { remove(h) } label: { Label(tr("Hapus"), systemImage: "trash") } } label: {
                Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tip("Hapus")
        }
        .contextMenu { Button(tr("Hapus")) { remove(h) } }
    }

    func remove(_ h: Habit) {
        if confirm(String(format: tr("Hapus %@?"), h.name), "Catatan dan streak kebiasaan ini ikut terhapus.", "Hapus") { s.data.habits.removeAll { $0.id == h.id } }
    }

    func add() {
        let name = newHabit.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        s.data.habits.append(Habit(name: name))
        newHabit = ""
    }
}
