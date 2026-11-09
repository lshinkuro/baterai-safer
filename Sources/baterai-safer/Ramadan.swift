import SwiftUI

// Notch → Ibadah → Ramadan & Zakat: fasting countdown, sahur reminder, tilawah target and a zakat calculator.

/// Day of Ramadan on the Umm al-Qura calendar, or nil outside it. `shift` moves the start for a local sighting (isbat).
func ramadanDay(on d: Date, shift: Int, tz: TimeZone) -> Int? {
    var cal = Calendar(identifier: .islamicUmmAlQura)
    cal.timeZone = tz
    let p = cal.dateComponents([.month, .day], from: d.addingTimeInterval(Double(-shift) * 86400))
    return p.month == 9 ? p.day : nil
}

/// Fitrah is 2.5 kg of staple rice per person (Kemenag and BAZNAS).
func zakatFitrah(people: Double, ricePrice: Double) -> Double { 2.5 * people * ricePrice }

/// Mal is 2.5% of net savings once they reach the nisab of 85 g of gold.
func zakatMal(wealth: Double, debt: Double, goldPrice: Double) -> (nisab: Double, due: Double) {
    let nisab = 85 * goldPrice, net = wealth - debt
    return (nisab, goldPrice > 0 && net >= nisab ? net * 0.025 : 0)
}

extension Ibadah {
    /// What a fasting person waits for next: Imsak before dawn and after Maghrib, the iftar in between.
    func fastNext(after now: Date = Date()) -> (title: String, date: Date) {
        let t = times(now)
        if now < t[.imsak]! { return ("Imsak", t[.imsak]!) }
        if now < t[.maghrib]! { return ("Buka puasa", t[.maghrib]!) }
        return ("Imsak", times(now.addingTimeInterval(86400))[.imsak]!)
    }
}

final class Ramadan: ObservableObject {
    static let shared = Ramadan()
    static let file = Paths.user + "/tilawah.json"
    static let pages = 604 // Mushaf Madinah
    static let sahurLead: TimeInterval = 45 * 60

    @Published var always = UserDefaults.standard.bool(forKey: "fastingAlways") {
        didSet { UserDefaults.standard.set(always, forKey: "fastingAlways"); changed() }
    }
    @Published var shift = UserDefaults.standard.integer(forKey: "ramadanShift") {
        didSet { UserDefaults.standard.set(shift, forKey: "ramadanShift"); changed() }
    }
    @Published var sahur = UserDefaults.standard.object(forKey: "sahurReminder") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sahur, forKey: "sahurReminder"); changed() }
    }
    @Published private(set) var read = load(Ramadan.file, [String: Int]())
    /// Set in the last hour before Imsak or iftar, for the collapsed notch.
    @Published private(set) var soon: (icon: String, minutes: Int)?

    var scheduleKey: String { "\(always)-\(shift)-\(sahur)" }
    var total: Int { read.values.reduce(0, +) }

    func day(_ d: Date = Date()) -> Int? { ramadanDay(on: d, shift: shift, tz: Ibadah.shared.place.zone) }
    func fasting(_ d: Date = Date()) -> Bool { always || day(d) != nil }
    func daysUntil(_ d: Date = Date()) -> Int? { (1...360).first { day(d.addingTimeInterval(Double($0) * 86400)) != nil } }

    /// Pages to read today to finish by the end of the month; today's reading doesn't move the goal.
    func dailyTarget(_ d: Date = Date()) -> Int {
        let daysLeft = day(d).map { max(1, 31 - $0) } ?? 30
        let before = total - (read[dayKey(d)] ?? 0)
        return Int((Double(max(0, Self.pages - before)) / Double(daysLeft)).rounded(.up))
    }

    func add(_ n: Int) {
        let key = dayKey(Date())
        read[key] = max(0, (read[key] ?? 0) + n)
        store()
    }

    func restart() { read = [:]; store() }

    func tick(_ now: Date = Date()) {
        var next: (icon: String, minutes: Int)?
        if fasting(now) {
            let target = Ibadah.shared.fastNext(after: now)
            let minutes = Int((target.date.timeIntervalSince(now) / 60).rounded(.up))
            if minutes <= 60 { next = (target.title == "Imsak" ? "moon.stars.fill" : "fork.knife", minutes) }
        }
        if next?.icon != soon?.icon || next?.minutes != soon?.minutes { soon = next }
    }

    func clearSoon() { soon = nil }

    private func changed() { tick(); Ibadah.shared.schedule() }

    private func store() {
        try? FileManager.default.createDirectory(atPath: Paths.user, withIntermediateDirectories: true)
        save(read, Self.file)
    }
}

struct RamadanPane: View {
    @ObservedObject var r = Ramadan.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            HStack(spacing: 10) {
                NCard(padding: 12) { tilawah(ctx.date) }
                NCard(padding: 12) { settings(ctx.date) }
            }
        }
    }

    func heading(_ text: String) -> some View {
        Text(tr(text).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
    }

    func tilawah(_ now: Date) -> some View {
        let today = r.read[dayKey(now)] ?? 0, target = r.dailyTarget(now)
        return VStack(alignment: .leading, spacing: 10) {
            heading("Tilawah")
            HStack(spacing: 12) {
                Ring(value: min(1, Double(r.total) / Double(Ramadan.pages)), color: Palette.accent, label: "\(min(100, r.total * 100 / Ramadan.pages))%", size: 58, line: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hari ini \(today)/\(target)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text("\(r.total)/\(Ramadan.pages) halaman").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                NButton(icon: "plus", title: "1", tint: Palette.accent, prominent: true) { r.add(1) }
                NButton(icon: "plus", title: "5", tint: Palette.accent) { r.add(5) }
                NButton(icon: "minus") { r.add(-1) }.tip("Kurangi satu halaman")
                Spacer(minLength: 0)
                NButton(icon: "arrow.counterclockwise") {
                    if confirm("Mulai khatam baru?", "Catatan halaman yang sudah dibaca akan dihapus.", "Mulai baru") { r.restart() }
                }
                .tip("Mulai khatam baru")
            }
        }
    }

    func settings(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            heading("Puasa")
            Group {
                if let d = r.day(now) {
                    Text(String(format: tr("Ramadan hari ke-%@"), "\(d)"))
                } else if let n = r.daysUntil(now) {
                    Text(String(format: tr("Ramadan %@ hari lagi"), "\(n)"))
                }
            }
            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
            option("Selalu aktif (puasa sunnah)", r.always) { r.always.toggle() }
            option("Pengingat sahur", r.sahur) { r.sahur.toggle() }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text("Awal Ramadan").font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                Spacer(minLength: 2)
                ForEach([-1, 0, 1], id: \.self) { v in
                    Button { r.shift = v } label: {
                        Text(v > 0 ? "+\(v)" : "\(v)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(r.shift == v ? Palette.onAccent : .gray)
                            .frame(width: 26, height: 20)
                            .background(r.shift == v ? Palette.accent : Color.white.opacity(0.05), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: tr("Geser awal Ramadan %@ hari"), "\(v)"))
                }
            }
            .help("Sesuaikan dengan hasil sidang isbat")
        }
    }

    func option(_ title: String, _ on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 13)).foregroundStyle(on ? Palette.accent : .gray)
                Text(tr(title)).font(.system(size: 12)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(tr(on ? "Nyala" : "Mati"))
    }
}

struct ZakatPane: View {
    @AppStorage("zakatRicePrice") private var rice = ""
    @AppStorage("zakatGoldPrice") private var gold = ""
    @Local private var people = "1"
    @Local private var wealth = "" // savings are never written to disk
    @Local private var debt = ""

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                NCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        heading("Zakat fitrah")
                        field("Jumlah jiwa", $people)
                        field("Harga beras per kg", $rice)
                        Spacer(minLength: 0)
                        money(zakatFitrah(people: number(people), ricePrice: number(rice)))
                    }
                }
                NCard(padding: 12) {
                    let mal = zakatMal(wealth: number(wealth), debt: number(debt), goldPrice: number(gold))
                    VStack(alignment: .leading, spacing: 6) {
                        heading("Zakat mal")
                        field("Harta tersimpan", $wealth)
                        field("Utang jatuh tempo", $debt)
                        field("Harga emas per gram", $gold)
                        Spacer(minLength: 0)
                        if mal.due > 0 || mal.nisab == 0 {
                            money(mal.due)
                        } else {
                            Text("Belum wajib, di bawah nisab").font(.system(size: 12, weight: .medium)).foregroundStyle(.gray).lineLimit(1)
                        }
                    }
                }
            }
            Text("Perkiraan. Besaran resmi mengikuti ketetapan BAZNAS atau lembaga setempat.").font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
        }
    }

    func number(_ s: String) -> Double { Double(s.filter(\.isNumber)) ?? 0 }

    func heading(_ text: String) -> some View {
        Text(tr(text).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
    }

    func money(_ v: Double) -> some View {
        Text(v, format: .currency(code: "IDR").precision(.fractionLength(0)).locale(appLocale))
            .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.accent).lineLimit(1).minimumScaleFactor(0.7)
    }

    func field(_ title: String, _ text: Binding<String>) -> some View {
        TextField(tr(title), text: text).textFieldStyle(.plain).font(.system(size: 12))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
