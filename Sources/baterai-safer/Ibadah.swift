import SwiftUI
import CoreLocation
import UserNotifications
import AVFoundation

// Notch → Ibadah: prayer times computed on this Mac (Kemenag RI method) with reminders, and the
// Qur'an from equran.id (Kemenag text, Latin, Indonesian translation, per-ayah murottal), cached locally.

// MARK: Prayer times

enum Prayer: Int, CaseIterable, Codable {
    case imsak, subuh, terbit, dzuhur, ashar, maghrib, isya
    var title: String { ["Imsak", "Subuh", "Terbit", "Dzuhur", "Ashar", "Maghrib", "Isya"][rawValue] }
    /// Terbit (sunrise) marks the end of Subuh; it is shown but never "the next prayer".
    var counts: Bool { self != .terbit }
}

/// Prayer times for one day, Kemenag RI method: Subuh at 20° below the horizon, Isya at 18°, Ashar at
/// shadow length 1 (Syafi'i), 2 minutes ihtiyat (rounded up; Terbit rounded down), Imsak 10 minutes
/// before Subuh. Astronomy after praytimes.org (sun position from the Julian day, one refinement pass).
func prayerTimes(on day: Date, lat: Double, lon: Double, tz: TimeZone) -> [Prayer: Date] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let c = cal.dateComponents([.year, .month, .day], from: day)
    var (y, m) = (Double(c.year!), Double(c.month!))
    if m <= 2 { y -= 1; m += 12 }
    let a = (y / 100).rounded(.down)
    let jd = (365.25 * (y + 4716)).rounded(.down) + (30.6001 * (m + 1)).rounded(.down) + Double(c.day!) + (2 - a + (a / 4).rounded(.down)) - 1524.5
        - lon / (15 * 24)

    let rad = Double.pi / 180
    func fix(_ x: Double, _ n: Double) -> Double { let r = x.truncatingRemainder(dividingBy: n); return r < 0 ? r + n : r }
    func sun(_ t: Double) -> (decl: Double, eqt: Double) {
        let d = jd + t - 2451545
        let g = fix(357.529 + 0.98560028 * d, 360), q = fix(280.459 + 0.98564736 * d, 360)
        let l = fix(q + 1.915 * sin(g * rad) + 0.020 * sin(2 * g * rad), 360)
        let e = 23.439 - 0.00000036 * d
        let ra = fix(atan2(cos(e * rad) * sin(l * rad), cos(l * rad)) / rad / 15, 24)
        return (asin(sin(e * rad) * sin(l * rad)) / rad, q / 15 - fix(ra, 24))
    }
    func noon(_ t: Double) -> Double { fix(12 - sun(t).eqt, 24) }
    /// Hours from noon until the sun is `angle` degrees below the horizon (positive = below).
    func span(_ angle: Double, _ t: Double) -> Double {
        let d = sun(t).decl * rad, phi = lat * rad
        let x = (-sin(angle * rad) - sin(phi) * sin(d)) / (cos(phi) * cos(d))
        return acos(min(1, max(-1, x))) / rad / 15
    }
    func asrSpan(_ t: Double) -> Double {
        let d = sun(t).decl
        let angle = -atan(1 / (1 + tan(abs(lat - d) * rad))) / rad
        return span(angle, t)
    }
    // First guess at each time (hours), then one pass with the sun's position at that guess.
    let guess: [Prayer: Double] = [.subuh: 5, .terbit: 6, .dzuhur: 12, .ashar: 13, .maghrib: 18, .isya: 18]
    var h: [Prayer: Double] = [:]
    for (p, g) in guess {
        let t = g / 24
        switch p {
        case .subuh: h[p] = noon(t) - span(20, t)
        case .terbit: h[p] = noon(t) - span(0.833, t)
        case .dzuhur: h[p] = noon(t)
        case .ashar: h[p] = noon(t) + asrSpan(t)
        case .maghrib: h[p] = noon(t) + span(0.833, t)
        case .isya: h[p] = noon(t) + span(18, t)
        case .imsak: break
        }
    }
    let shift = Double(tz.secondsFromGMT(for: day)) / 3600 - lon / 15
    let start = cal.startOfDay(for: day)
    var out: [Prayer: Date] = [:]
    for (p, hours) in h {
        let minutes = (hours + shift) * 60 + (p == .terbit ? -2 : 2)
        out[p] = start.addingTimeInterval((p == .terbit ? minutes.rounded(.down) : minutes.rounded(.up)) * 60)
    }
    out[.imsak] = out[.subuh]!.addingTimeInterval(-600)
    return out
}

struct City: Codable, Equatable, Hashable {
    let name: String, lat: Double, lon: Double, tz: String
    var zone: TimeZone { TimeZone(identifier: tz) ?? .current }
}

let indonesianCities: [City] = [
    ("Banda Aceh", 5.5483, 95.3238, "Asia/Jakarta"), ("Medan", 3.5952, 98.6722, "Asia/Jakarta"), ("Padang", -0.9471, 100.4172, "Asia/Jakarta"),
    ("Pekanbaru", 0.5071, 101.4478, "Asia/Jakarta"), ("Batam", 1.1301, 104.0529, "Asia/Jakarta"), ("Jambi", -1.6101, 103.6131, "Asia/Jakarta"),
    ("Palembang", -2.9761, 104.7754, "Asia/Jakarta"), ("Bengkulu", -3.8004, 102.2655, "Asia/Jakarta"), ("Bandar Lampung", -5.3971, 105.2668, "Asia/Jakarta"),
    ("Pangkal Pinang", -2.1316, 106.1169, "Asia/Jakarta"), ("Serang", -6.1200, 106.1503, "Asia/Jakarta"), ("Tangerang", -6.1783, 106.6319, "Asia/Jakarta"),
    ("Jakarta", -6.2088, 106.8456, "Asia/Jakarta"), ("Bekasi", -6.2383, 106.9756, "Asia/Jakarta"), ("Depok", -6.4025, 106.7942, "Asia/Jakarta"),
    ("Bogor", -6.5971, 106.8060, "Asia/Jakarta"), ("Bandung", -6.9175, 107.6191, "Asia/Jakarta"), ("Cirebon", -6.7320, 108.5523, "Asia/Jakarta"),
    ("Semarang", -6.9667, 110.4167, "Asia/Jakarta"), ("Solo", -7.5755, 110.8243, "Asia/Jakarta"), ("Yogyakarta", -7.7956, 110.3695, "Asia/Jakarta"),
    ("Surabaya", -7.2575, 112.7521, "Asia/Jakarta"), ("Malang", -7.9666, 112.6326, "Asia/Jakarta"), ("Pontianak", -0.0263, 109.3425, "Asia/Jakarta"),
    ("Palangka Raya", -2.2161, 113.9135, "Asia/Jakarta"), ("Denpasar", -8.6705, 115.2126, "Asia/Makassar"), ("Mataram", -8.5833, 116.1167, "Asia/Makassar"),
    ("Kupang", -10.1772, 123.6070, "Asia/Makassar"), ("Banjarmasin", -3.3186, 114.5944, "Asia/Makassar"), ("Balikpapan", -1.2379, 116.8529, "Asia/Makassar"),
    ("Samarinda", -0.5022, 117.1536, "Asia/Makassar"), ("Nusantara (IKN)", -0.9739, 116.7085, "Asia/Makassar"), ("Makassar", -5.1477, 119.4327, "Asia/Makassar"),
    ("Palu", -0.8917, 119.8707, "Asia/Makassar"), ("Kendari", -3.9985, 122.5129, "Asia/Makassar"), ("Gorontalo", 0.5435, 123.0568, "Asia/Makassar"),
    ("Manado", 1.4748, 124.8421, "Asia/Makassar"), ("Mamuju", -2.6748, 118.8885, "Asia/Makassar"), ("Ambon", -3.6954, 128.1814, "Asia/Jayapura"),
    ("Ternate", 0.7893, 127.3770, "Asia/Jayapura"), ("Sorong", -0.8762, 131.2558, "Asia/Jayapura"), ("Manokwari", -0.8615, 134.0620, "Asia/Jayapura"),
    ("Jayapura", -2.5337, 140.7181, "Asia/Jayapura"), ("Merauke", -8.4932, 140.4018, "Asia/Jayapura"),
].map { City(name: $0.0, lat: $0.1, lon: $0.2, tz: $0.3) }

final class Ibadah: NSObject, ObservableObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    static let shared = Ibadah()
    @Published var place = baterai_safer.load(Ibadah.placeFile, indonesianCities.first { $0.name == "Jakarta" }!)
    @Published var auto = UserDefaults.standard.object(forKey: "ibadahAuto") as? Bool ?? true
    @Published var locating = false
    @Published var locationDenied = false
    @Published var reminders = Set((UserDefaults.standard.array(forKey: "ibadahReminders") as? [Int])?.compactMap(Prayer.init) ?? [.subuh, .dzuhur, .ashar, .maghrib, .isya]) {
        didSet { UserDefaults.standard.set(reminders.map(\.rawValue), forKey: "ibadahReminders"); schedule() }
    }
    private let location = CLLocationManager()
    private var timer: Timer?
    private var scheduledDay = ""
    static let placeFile = Paths.user + "/ibadah-place.json"

    func times(_ day: Date = Date()) -> [Prayer: Date] { prayerTimes(on: day, lat: place.lat, lon: place.lon, tz: place.zone) }

    /// The next prayer from now (today's, or tomorrow's Subuh after Isya).
    func next(after now: Date = Date()) -> (Prayer, Date) {
        if let p = Prayer.allCases.filter(\.counts).map({ ($0, times(now)[$0]!) }).first(where: { $0.1 > now }) { return p }
        return (.imsak, times(now.addingTimeInterval(86400))[.imsak]!)
    }

    /// Notifications and Location need an app bundle; a bare binary (selftest, CLI, render harness) would crash.
    private var bundled: Bool { Bundle.main.bundleIdentifier != nil }

    func start() {
        guard timer == nil, bundled else { return }
        UNUserNotificationCenter.current().delegate = self
        if auto { locate() }
        schedule()
        // Reschedule once a day so reminders always cover the next few days.
        timer = .scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.schedule() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        guard bundled else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.ids)
        scheduledDay = ""
    }

    func useAutomatic() { auto = true; UserDefaults.standard.set(true, forKey: "ibadahAuto"); locate() }

    func pick(_ c: City) {
        auto = false
        UserDefaults.standard.set(false, forKey: "ibadahAuto")
        set(c)
    }

    private func set(_ c: City) {
        place = c
        try? FileManager.default.createDirectory(atPath: Paths.user, withIntermediateDirectories: true)
        save(c, Self.placeFile)
        scheduledDay = ""
        schedule()
    }

    private func locate() {
        guard bundled else { return }
        location.delegate = self
        locating = true
        locationDenied = false
        location.requestWhenInUseAuthorization()
        location.requestLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations ls: [CLLocation]) {
        guard let l = ls.last else { return }
        CLGeocoder().reverseGeocodeLocation(l) { marks, _ in
            DispatchQueue.main.async {
                self.locating = false
                guard self.auto else { return }
                let name = marks?.first.flatMap { $0.locality ?? $0.subAdministrativeArea } ?? String(format: "%.2f, %.2f", l.coordinate.latitude, l.coordinate.longitude)
                self.set(City(name: name, lat: l.coordinate.latitude, lon: l.coordinate.longitude, tz: TimeZone.current.identifier))
            }
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.locating = false
            self.locationDenied = [.denied, .restricted].contains(m.authorizationStatus)
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if [.denied, .restricted].contains(m.authorizationStatus) { DispatchQueue.main.async { self.locating = false; self.locationDenied = true } }
    }

    // MARK: Reminders

    static let ids = (0..<3).flatMap { d in Prayer.allCases.map { "sholat-\(d)-\($0.rawValue)" } }

    /// Today and the next two days, so reminders arrive even if Poni isn't running.
    func schedule() {
        let key = "\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)-\(place.name)-\(reminders.count)"
        guard bundled, key != scheduledDay else { return }
        scheduledDay = key
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Self.ids)
        guard !reminders.isEmpty else { return }
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            DispatchQueue.main.async {
                let now = Date()
                for d in 0..<3 {
                    let times = self.times(now.addingTimeInterval(Double(d) * 86400))
                    for p in Prayer.allCases where self.reminders.contains(p) {
                        guard let t = times[p], t > now else { continue }
                        let content = UNMutableNotificationContent()
                        content.title = String(format: tr(p == .imsak ? "Imsak · %@" : "Waktu %@ · %@"), p == .imsak ? self.clock(t) : tr(p.title), self.clock(t))
                        content.body = self.place.name
                        content.sound = .default
                        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: t)
                        center.add(UNNotificationRequest(identifier: "sholat-\(d)-\(p.rawValue)", content: content,
                                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
                    }
                }
            }
        }
    }

    func clock(_ d: Date) -> String {
        var f = Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale)
        f.timeZone = place.zone
        return d.formatted(f)
    }

    // Show reminders even while Poni is the active app (it usually is, with the notch open).
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}

// MARK: Notch tab

struct IbadahView: View {
    @ObservedObject var m = Ibadah.shared
    @Local private var picking = false

    var body: some View {
        HStack(spacing: 12) {
            NCard(padding: 14) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    let (p, t) = m.next(after: ctx.date)
                    let mins = Int(t.timeIntervalSince(ctx.date) / 60) + 1
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("SHOLAT BERIKUTNYA")).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(tr(p.title)).font(.system(size: 26, weight: .semibold))
                            Text(m.clock(t)).font(.system(size: 15, weight: .medium)).monospacedDigit().foregroundStyle(Palette.accent)
                        }
                        Text(String(format: tr("%@ lagi"), mins >= 60 ? String(format: tr("%@j %@m"), "\(mins / 60)", "\(mins % 60)") : "\(mins)m"))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).monospacedDigit()
                        Spacer(minLength: 0)
                        Button { withAnimation(Motion.ease) { picking.toggle() } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: m.auto ? "location.fill" : "mappin").font(.system(size: 10))
                                Text(m.locating ? tr("Mencari lokasi…") : m.place.name).lineLimit(1)
                                Image(systemName: picking ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).tip("Ganti lokasi")
                        NButton(icon: "book.fill", title: "Baca Al-Qur'an", tint: Palette.accent, prominent: true) { QuranWindow.show() }
                    }
                }
            }
            .frame(width: 230)
            if picking { cities } else { schedule }
        }
        .onAppear { m.start() }
    }

    var schedule: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            // After Isya the day is done: show tomorrow's times instead of a list of past ones.
            let tomorrow = ctx.date >= m.times(ctx.date)[.isya]!
            let times = m.times(tomorrow ? ctx.date.addingTimeInterval(86400) : ctx.date), next = m.next(after: ctx.date).0
            VStack(spacing: 3) {
                if tomorrow {
                    Text(tr("BESOK")).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                }
                ForEach(Prayer.allCases, id: \.self) { p in
                    let t = times[p]!, on = p == next && t > ctx.date, past = t <= ctx.date
                    HStack(spacing: 10) {
                        Text(tr(p.title)).font(.system(size: 12, weight: on ? .bold : .medium))
                        Spacer()
                        Text(m.clock(t)).font(.system(size: 12, weight: on ? .bold : .medium)).monospacedDigit()
                        Button {
                            if m.reminders.contains(p) { m.reminders.remove(p) } else { m.reminders.insert(p) }
                        } label: {
                            Image(systemName: m.reminders.contains(p) ? "bell.fill" : "bell.slash")
                                .font(.system(size: 10, weight: .semibold)).frame(width: 18)
                                .foregroundStyle(on ? Palette.onAccent : m.reminders.contains(p) ? Palette.accent : .gray)
                        }
                        .buttonStyle(.plain).tip(m.reminders.contains(p) ? "Matikan pengingat" : "Nyalakan pengingat")
                    }
                    .foregroundStyle(on ? Palette.onAccent : past ? .white.opacity(0.4) : .white.opacity(0.9))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(on ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    var cities: some View {
        ScrollView {
            VStack(spacing: 3) {
                cityRow(icon: "location.fill", name: m.locationDenied ? tr("Lokasi otomatis (izin ditolak)") : tr("Lokasi otomatis"), on: m.auto) { m.useAutomatic(); picking = false }
                if m.locationDenied {
                    Text(tr("System Settings → Privacy & Security → Location Services → Poni")).font(.system(size: 10)).foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
                }
                ForEach(indonesianCities, id: \.self) { c in
                    cityRow(icon: "mappin", name: c.name, on: !m.auto && m.place == c) { m.pick(c); picking = false }
                }
            }
        }
    }

    func cityRow(icon: String, name: String, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 10)).frame(width: 14)
                Text(name).font(.system(size: 12, weight: on ? .semibold : .regular))
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundStyle(on ? Palette.onAccent : .white.opacity(0.9))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(on ? Palette.accent : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Qur'an (equran.id)

struct SurahInfo: Codable, Identifiable, Hashable {
    let nomor: Int, nama: String, namaLatin: String, jumlahAyat: Int, tempatTurun: String, arti: String
    var id: Int { nomor }
}

struct Ayah: Codable, Identifiable {
    let nomorAyat: Int, teksArab: String, teksLatin: String, teksIndonesia: String, audio: [String: String]
    var id: Int { nomorAyat }
}

struct Surah: Codable {
    let nomor: Int, nama: String, namaLatin: String, jumlahAyat: Int, tempatTurun: String, arti: String, ayat: [Ayah]
}

final class Quran: ObservableObject {
    static let shared = Quran()
    static let api = "https://equran.id/api/v2/surat"
    static let dir = Paths.user + "/quran"
    static let qaris = [("05", "Misyari Rasyid Al-Afasi"), ("01", "Abdullah Al-Juhany"), ("02", "Abdul Muhsin Al-Qasim"),
                        ("03", "Abdurrahman as-Sudais"), ("04", "Ibrahim Al-Dossari"), ("06", "Yasser Al-Dosari")]

    @Published var list: [SurahInfo] = load(Quran.dir + "/list.json", [SurahInfo]())
    @Published var surah: Surah?
    @Published var loading = false
    @Published var error = ""
    @Published var playing: Int?   // ayah number being recited
    @Published var qari = UserDefaults.standard.string(forKey: "quranQari") ?? "05" {
        didSet { UserDefaults.standard.set(qari, forKey: "quranQari") }
    }
    /// Last ayah marked as read: "surah:ayah".
    @Published var lastRead = UserDefaults.standard.string(forKey: "quranLastRead") {
        didSet { UserDefaults.standard.set(lastRead, forKey: "quranLastRead") }
    }
    private var player: AVPlayer?
    private var ended: Any?

    private struct Envelope<T: Decodable>: Decodable { let data: T }

    /// Cached JSON first; the network only for what isn't on this Mac yet.
    private func fetch<T: Codable>(_ url: String, cache: String, done: @escaping (T?) -> Void) {
        if let hit: T = load(cache, Optional<T>.none) { done(hit); return }
        guard let u = URL(string: url) else { done(nil); return }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            let v = data.flatMap { try? JSONDecoder().decode(Envelope<T>.self, from: $0).data }
            if let v {
                try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
                save(v, cache)
            }
            DispatchQueue.main.async { done(v) }
        }.resume()
    }

    func loadList() {
        guard list.isEmpty, !loading else { return }
        loading = true
        fetch(Self.api, cache: Self.dir + "/list.json") { (v: [SurahInfo]?) in
            self.loading = false
            if let v { self.list = v } else { self.error = tr("Tidak bisa memuat daftar surah (offline?)") }
        }
    }

    func open(_ n: Int) {
        guard surah?.nomor != n else { return }
        stop()
        loading = true
        error = ""
        fetch("\(Self.api)/\(n)", cache: Self.dir + "/surah-\(n).json") { (v: Surah?) in
            self.loading = false
            if let v { self.surah = v } else { self.error = tr("Surah belum tersimpan dan tidak bisa diunduh (offline?)") }
        }
    }

    /// Recites from this ayah to the end of the surah.
    func play(_ n: Int) {
        guard let s = surah, let a = s.ayat.first(where: { $0.nomorAyat == n }), let url = (a.audio[qari] ?? a.audio.values.first).flatMap(URL.init(string:)) else { stop(); return }
        if let ended { NotificationCenter.default.removeObserver(ended) }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        ended = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self, self.playing == n else { return }
            n < s.jumlahAyat ? self.play(n + 1) : self.stop()
        }
        playing = n
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
        playing = nil
    }
}

struct QuranView: View {
    @ObservedObject var q = Quran.shared
    @Local private var search = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                    TextField(tr("Cari surah"), text: $search).textFieldStyle(.plain)
                }
                .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if let last = q.lastRead?.split(separator: ":").compactMap({ Int($0) }), last.count == 2, let s = q.list.first(where: { $0.nomor == last[0] }) {
                    NButton(icon: "bookmark.fill", title: String(format: tr("Lanjut %@ : %@"), s.namaLatin, "\(last[1])"), tint: Palette.accent, prominent: true) { q.open(s.nomor) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(q.list.filter { search.isEmpty || $0.namaLatin.localizedCaseInsensitiveContains(search) || $0.arti.localizedCaseInsensitiveContains(search) || "\($0.nomor)" == search }) { s in
                            surahRow(s)
                        }
                    }
                }
            }
            .frame(width: 250)
            reader
        }
        .onAppear { q.loadList() }
        .onDisappear { q.stop() }
    }

    func surahRow(_ s: SurahInfo) -> some View {
        let on = q.surah?.nomor == s.nomor
        return Button { q.open(s.nomor) } label: {
            HStack(spacing: 10) {
                Text("\(s.nomor)").font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.namaLatin).font(.system(size: 12, weight: .semibold))
                    Text("\(s.arti) · \(s.jumlahAyat)").font(.system(size: 10)).opacity(0.6)
                }
                Spacer()
                Text(s.nama).font(.system(size: 16))
            }
            .foregroundStyle(on ? Palette.onAccent : .white.opacity(0.9))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Palette.accent : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var reader: some View {
        if let s = q.surah {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(s.nomor). \(s.namaLatin)").font(.system(size: 20, weight: .semibold))
                        Text("\(s.arti) · \(s.tempatTurun) · \(String(format: tr("%@ ayat"), "\(s.jumlahAyat)"))").font(.system(size: 11)).foregroundStyle(.gray)
                    }
                    Spacer()
                    Picker("", selection: $q.qari) { ForEach(Quran.qaris, id: \.0) { Text($0.1).tag($0.0) } }
                        .labelsHidden().fixedSize().controlSize(.small).tip("Qari")
                    NButton(icon: q.playing == nil ? "play.fill" : "stop.fill", title: q.playing == nil ? "Putar surah" : "Berhenti", tint: Palette.accent, prominent: true) {
                        q.playing == nil ? q.play(1) : q.stop()
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(s.ayat) { a in ayah(s, a).id(a.nomorAyat) }
                            Text(tr("Teks, terjemahan, dan audio: equran.id (Kemenag RI)")).font(.system(size: 10)).foregroundStyle(.gray).padding(.vertical, 16)
                        }
                    }
                    .onChange(of: q.playing) { n in if let n { withAnimation(Motion.ease) { proxy.scrollTo(n, anchor: .center) } } }
                    .onAppear {
                        if let last = q.lastRead?.split(separator: ":").compactMap({ Int($0) }), last.count == 2, last[0] == s.nomor { proxy.scrollTo(last[1], anchor: .top) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if q.loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Placeholder(icon: "book.closed", title: q.error.isEmpty ? "Pilih surah" : q.error, subtitle: q.error.isEmpty ? "Surah yang pernah dibuka tersimpan dan bisa dibaca offline" : nil)
        }
    }

    func ayah(_ s: Surah, _ a: Ayah) -> some View {
        let on = q.playing == a.nomorAyat, marked = q.lastRead == "\(s.nomor):\(a.nomorAyat)"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("\(a.nomorAyat)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .frame(width: 28, height: 28).background(on ? Palette.accent : Color.white.opacity(0.08), in: Circle())
                    .foregroundStyle(on ? Palette.onAccent : .white)
                Spacer()
                NButton(icon: on ? "stop.fill" : "play.fill") { on ? q.stop() : q.play(a.nomorAyat) }.tip(on ? "Berhenti" : "Dengarkan")
                NButton(icon: marked ? "bookmark.fill" : "bookmark", tint: marked ? Palette.accent : .white) { q.lastRead = "\(s.nomor):\(a.nomorAyat)" }
                    .tip("Tandai terakhir dibaca")
                NButton(icon: "doc.on.doc") {
                    copyText("\(a.teksArab)\n\n\(a.teksIndonesia)\n(QS. \(s.namaLatin): \(a.nomorAyat))")
                }.tip("Salin ayat")
            }
            Text(a.teksArab).font(.system(size: 28)).lineSpacing(14)
                .multilineTextAlignment(.trailing).frame(maxWidth: .infinity, alignment: .trailing)
            Text(a.teksLatin).font(.system(size: 12)).italic().foregroundStyle(Palette.accent.opacity(0.9))
            Text(a.teksIndonesia).font(.system(size: 13)).foregroundStyle(.white.opacity(0.85)).textSelection(.enabled)
        }
        .padding(.vertical, 16).padding(.horizontal, 4)
        .background(alignment: .bottom) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }
}

enum QuranWindow {
    static func show() { AppWindow.show("quran", title: "Al-Qur'an", size: NSSize(width: 1000, height: 720)) { QuranView() } }
}
