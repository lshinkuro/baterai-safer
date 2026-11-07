import SwiftUI
import IOBluetooth

// MARK: Bluetooth devices

struct BTDevice: Identifiable, Equatable {
    let name: String
    let address: String
    let kind: String              // Headphones, Mouse, Keyboard, …
    let connected: Bool
    var batteries: [(String, Int)] // ("Kiri", 80), ("Case", 40), ("", 65)
    var id: String { address }

    static func == (a: BTDevice, b: BTDevice) -> Bool {
        a.address == b.address && a.connected == b.connected && a.batteries.map(\.1) == b.batteries.map(\.1)
    }

    var icon: String {
        let n = name.lowercased(), k = kind.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if k.contains("mouse") { return "magicmouse" }
        if k.contains("keyboard") { return "keyboard" }
        if k.contains("headphone") || k.contains("headset") { return "headphones" }
        if k.contains("speaker") || n.contains("speaker") { return "hifispeaker" }
        if k.contains("gamepad") || k.contains("controller") { return "gamecontroller" }
        return "dot.radiowaves.left.and.right"
    }
    var isAudio: Bool { ["headphones", "airpods", "airpodspro", "airpodsmax", "hifispeaker"].contains(icon) }
}

/// Parses `system_profiler SPBluetoothDataType -json`; battery values look like "85%".
func parseBluetooth(_ d: Data) -> [BTDevice] {
    let root = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["SPBluetoothDataType"] as? [[String: Any]] ?? []
    var out: [BTDevice] = []
    for section in root {
        for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
            for entry in section[key] as? [[String: [String: Any]]] ?? [] {
                for (name, info) in entry {
                    let pct = { (k: String) in (info[k] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) } }
                    let batteries = [("Kiri", "device_batteryLevelLeft"), ("Kanan", "device_batteryLevelRight"), ("Case", "device_batteryLevelCase"), ("", "device_batteryLevelMain")]
                        .compactMap { label, k in pct(k).map { (label, $0) } }
                    out.append(BTDevice(name: name, address: info["device_address"] as? String ?? name, kind: info["device_minorType"] as? String ?? "",
                                        connected: connected, batteries: batteries))
                }
            }
        }
    }
    // connected first; keep the first of duplicate names (some mice pair under two addresses)
    var seen = Set<String>()
    return out.sorted { $0.connected && !$1.connected }.filter { seen.insert($0.name).inserted }
}

final class BluetoothModel: ObservableObject {
    static let shared = BluetoothModel()
    @Published var devices: [BTDevice] = []
    @Published var busy: String?
    private var timer: Timer?
    private var users = 0

    // Several views may show devices; poll only while at least one is visible.
    func start() {
        users += 1
        guard timer == nil else { return }
        refresh()
        timer = .scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { timer?.invalidate(); timer = nil }
    }

    func refresh() {
        runAsync("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]) { _, out, _ in
            var list = parseBluetooth(Data(out.utf8))
            // Non-Apple HID devices (e.g. some mice) report battery only through IOKit.
            let hid = hidBatteries()
            for i in list.indices where list[i].connected && list[i].batteries.isEmpty {
                if let p = hid[list[i].name] { list[i].batteries = [("", p)] }
            }
            if list != self.devices { self.devices = list }
        }
    }

    /// Connects or disconnects; macOS then routes audio itself.
    func toggle(_ d: BTDevice) {
        guard let dev = IOBluetoothDevice(addressString: d.address) else { return }
        busy = d.address
        DispatchQueue.global().async {
            _ = d.connected ? dev.closeConnection() : dev.openConnection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.busy = nil; self.refresh() }
        }
    }
}

/// Product name → battery percent for HID devices that expose `BatteryPercent`.
func hidBatteries() -> [String: Int] {
    var out: [String: Int] = [:]
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS else { return out }
    defer { IOObjectRelease(iter) }
    while case let s = IOIteratorNext(iter), s != 0 {
        defer { IOObjectRelease(s) }
        let prop = { (k: String) in IORegistryEntryCreateCFProperty(s, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
        if let name = prop("Product") as? String, let p = prop("BatteryPercent") as? Int { out[name] = p }
    }
    return out
}

// MARK: Weather (Open-Meteo: free, no API key)

/// WMO weather code → (SF Symbol, Indonesian label).
func weatherInfo(_ code: Int, night: Bool = false) -> (String, String) {
    switch code {
    case 0: return (night ? "moon.stars.fill" : "sun.max.fill", "Cerah")
    case 1, 2: return (night ? "cloud.moon.fill" : "cloud.sun.fill", "Cerah berawan")
    case 3: return ("cloud.fill", "Berawan")
    case 45, 48: return ("cloud.fog.fill", "Berkabut")
    case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Gerimis")
    case 61, 63, 66, 80, 81: return ("cloud.rain.fill", "Hujan")
    case 65, 67, 82: return ("cloud.heavyrain.fill", "Hujan lebat")
    case 71, 73, 75, 77, 85, 86: return ("cloud.snow.fill", "Salju")
    case 95, 96, 99: return ("cloud.bolt.rain.fill", "Badai petir")
    default: return ("cloud.fill", "—")
    }
}

struct Weather {
    struct Hour: Identifiable { let time: Date; let temp: Double; let rain: Int; let code: Int; var id: Date { time } }
    var city = ""
    var temp = 0.0, feels = 0.0, humidity = 0, wind = 0.0
    var code = 0, isDay = true
    var high = 0.0, low = 0.0
    var hours: [Hour] = []
}

func parseWeather(_ d: Data, city: String, now: Date = Date()) -> Weather? {
    guard let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
          let c = o["current"] as? [String: Any], let h = o["hourly"] as? [String: Any], let day = o["daily"] as? [String: Any] else { return nil }
    let num = { (v: Any?) in (v as? NSNumber)?.doubleValue ?? 0 }
    var w = Weather(city: city, temp: num(c["temperature_2m"]), feels: num(c["apparent_temperature"]),
                    humidity: Int(num(c["relative_humidity_2m"])), wind: num(c["wind_speed_10m"]),
                    code: Int(num(c["weather_code"])), isDay: num(c["is_day"]) == 1,
                    high: num((day["temperature_2m_max"] as? [Any])?.first), low: num((day["temperature_2m_min"] as? [Any])?.first))
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    if let tz = o["timezone"] as? String { f.timeZone = TimeZone(identifier: tz) }
    let times = h["time"] as? [String] ?? [], temps = h["temperature_2m"] as? [Any] ?? []
    let rain = h["precipitation_probability"] as? [Any] ?? [], codes = h["weather_code"] as? [Any] ?? []
    for i in times.indices {
        guard let t = f.date(from: times[i]), t > now.addingTimeInterval(-3600), i < temps.count else { continue }
        w.hours.append(.init(time: t, temp: num(temps[i]), rain: Int(num(i < rain.count ? rain[i] : 0)), code: Int(num(i < codes.count ? codes[i] : 0))))
        if w.hours.count == 8 { break }
    }
    return w
}

final class WeatherModel: ObservableObject {
    @Published var weather: Weather?
    @Published var error = ""
    @Published var city = UserDefaults.standard.string(forKey: "weatherCity") ?? ""
    private var fetched = Date.distantPast
    private var place: (lat: Double, lon: Double, name: String)?

    /// Refreshes at most every 15 minutes unless forced.
    func refresh(force: Bool = false) {
        guard !city.isEmpty, force || Date().timeIntervalSince(fetched) > 900 else { return }
        fetched = Date()
        error = ""
        if let p = place { forecast(p); return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "id")]
        URLSession.shared.dataTask(with: c.url!) { d, _, _ in
            let r = ((d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["results"] as? [[String: Any]])?.first
            DispatchQueue.main.async {
                guard let r, let lat = (r["latitude"] as? NSNumber)?.doubleValue, let lon = (r["longitude"] as? NSNumber)?.doubleValue else {
                    self.error = d == nil ? "Tidak ada koneksi" : "Kota \"\(self.city)\" tidak ditemukan"
                    return
                }
                self.place = (lat, lon, r["name"] as? String ?? self.city)
                self.forecast(self.place!)
            }
        }.resume()
    }

    func setCity(_ name: String) {
        city = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(city, forKey: "weatherCity")
        place = nil
        weather = nil
        refresh(force: true)
    }

    private func forecast(_ p: (lat: Double, lon: Double, name: String)) {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [.init(name: "latitude", value: "\(p.lat)"), .init(name: "longitude", value: "\(p.lon)"),
                        .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"),
                        .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
                        .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                        .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2")]
        URLSession.shared.dataTask(with: c.url!) { d, _, _ in
            let w = d.flatMap { parseWeather($0, city: p.name) }
            DispatchQueue.main.async {
                if let w { self.weather = w } else { self.error = "Gagal memuat cuaca" }
            }
        }.resume()
    }
}

// MARK: Calculator & conversions

/// Reads Indonesian-style numbers: "1.500.000", "1,5", "150rb", "2jt", "3k", "1,2miliar".
func parseAmount(_ raw: String) -> Double? {
    var s = raw.lowercased().trimmingCharacters(in: .whitespaces)
    var mult = 1.0
    for (suffix, m) in [("miliar", 1e9), ("juta", 1e6), ("ribu", 1e3), ("rb", 1e3), ("jt", 1e6), ("k", 1e3)] where s.hasSuffix(suffix) {
        mult = m
        s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        break
    }
    // dots as thousands separators only when they group by three ("1.500.000"); comma is decimal
    if s.range(of: #"^\d{1,3}(\.\d{3})+(,\d+)?$"#, options: .regularExpression) != nil { s = s.replacingOccurrences(of: ".", with: "") }
    s = s.replacingOccurrences(of: ",", with: ".")
    guard let v = Double(s) else { return nil }
    return v * mult
}

/// Tiny arithmetic parser (+ − × ÷ ^ %, parentheses) — no NSExpression, which crashes on bad input.
struct Calc {
    private var tokens: [String]
    private var i = 0

    static func eval(_ text: String) -> Double? {
        var c = Calc(tokens: tokenize(text))
        guard !c.tokens.isEmpty, let v = c.expr(), c.i == c.tokens.count, v.isFinite else { return nil }
        return v
    }

    private static func tokenize(_ s: String) -> [String] {
        let t = s.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "x", with: "*")
        var out: [String] = [], cur = ""
        for ch in t {
            if "+-*/^()%".contains(ch) {
                if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
                cur = ""
                out.append(String(ch))
            } else if ch == " " && !cur.isEmpty && !cur.hasSuffix(" ") {
                cur.append(ch)
            } else if ch != " " {
                cur.append(ch)
            }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur.trimmingCharacters(in: .whitespaces)) }
        return out
    }

    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while i < tokens.count, tokens[i] == "+" || tokens[i] == "-" {
            let op = tokens[i]; i += 1
            // "200rb + 10%" means 10 percent of the left side
            if i + 1 < tokens.count, tokens[i + 1] == "%", let p = parseAmount(tokens[i]), i + 2 == tokens.count || tokens[i + 2] == ")" {
                i += 2
                v = op == "+" ? v * (1 + p / 100) : v * (1 - p / 100)
                continue
            }
            guard let r = term() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while i < tokens.count, ["*", "/", "%"].contains(tokens[i]) {
            let op = tokens[i]; i += 1
            if op == "%" { v /= 100; continue } // postfix percent: "15% * 200rb"
            guard let r = power() else { return nil }
            v = op == "*" ? v * r : v / r
        }
        return v
    }

    private mutating func power() -> Double? {
        guard let b = unary() else { return nil }
        if i < tokens.count, tokens[i] == "^" { i += 1; guard let e = power() else { return nil }; return pow(b, e) }
        return b
    }

    private mutating func unary() -> Double? {
        guard i < tokens.count else { return nil }
        if tokens[i] == "-" { i += 1; return unary().map { -$0 } }
        if tokens[i] == "(" {
            i += 1
            guard let v = expr(), i < tokens.count, tokens[i] == ")" else { return nil }
            i += 1
            return v
        }
        guard let v = parseAmount(tokens[i]) else { return nil }
        i += 1
        return v
    }
}

let unitTable: [String: Dimension] = [
    "km": UnitLength.kilometers, "m": UnitLength.meters, "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
    "mil": UnitLength.miles, "mi": UnitLength.miles, "ft": UnitLength.feet, "kaki": UnitLength.feet, "inch": UnitLength.inches, "in": UnitLength.inches, "yd": UnitLength.yards,
    "kg": UnitMass.kilograms, "g": UnitMass.grams, "gram": UnitMass.grams, "ons": UnitMass.ounces, "oz": UnitMass.ounces, "lb": UnitMass.pounds, "pon": UnitMass.pounds, "ton": UnitMass.metricTons,
    "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "f": UnitTemperature.fahrenheit, "°f": UnitTemperature.fahrenheit, "k": UnitTemperature.kelvin,
    "l": UnitVolume.liters, "liter": UnitVolume.liters, "ml": UnitVolume.milliliters, "gal": UnitVolume.gallons, "cup": UnitVolume.cups,
    "kmh": UnitSpeed.kilometersPerHour, "km/j": UnitSpeed.kilometersPerHour, "mph": UnitSpeed.milesPerHour, "m/s": UnitSpeed.metersPerSecond,
    "gb": UnitInformationStorage.gigabytes, "mb": UnitInformationStorage.megabytes, "tb": UnitInformationStorage.terabytes, "kb": UnitInformationStorage.kilobytes,
]

enum CalcResult: Equatable {
    case value(Double)
    case converted(Double, String)    // value, target unit label
    case needsRates(Double, String, String) // amount, from, to (currency)
}

/// "5 km ke mil", "100 usd ke idr", "150rb * 12", "15% dari 200rb".
func calculate(_ raw: String) -> CalcResult? {
    let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }
    if let m = s.firstMatch(#"^(.+?)%\s*(?:dari|of)\s+(.+)$"#), let p = Calc.eval(m[0]), let base = Calc.eval(m[1]) {
        return .value(p / 100 * base)
    }
    if let m = s.firstMatch(#"^(.+?)\s*([a-z°/]+)\s+(?:ke|to|in|=)\s+([a-z°/]+)$"#), let amount = Calc.eval(m[0]) {
        let from = m[1], to = m[2]
        if let a = unitTable[from], let b = unitTable[to], type(of: a) == type(of: b) {
            return .converted(Measurement(value: amount, unit: a).converted(to: b).value, to)
        }
        if from.count == 3, to.count == 3 { return .needsRates(amount, from.uppercased(), to.uppercased()) }
        return nil
    }
    return Calc.eval(s).map { .value($0) }
}

extension String {
    /// Capture groups of the first regex match.
    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: self).map { String(self[$0]) } }
    }
}

func formatNumber(_ v: Double) -> String {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "id_ID")
    f.numberStyle = .decimal
    f.maximumFractionDigits = abs(v) >= 1000 ? 2 : 6
    return f.string(from: NSNumber(value: v)) ?? String(v)
}

final class CalcModel: ObservableObject {
    @Published var input = ""
    @Published var result = ""
    @Published var history: [(String, String)] = []
    private var rates: [String: Double] = [:], ratesBase = "", ratesAt = Date.distantPast

    func evaluate() {
        switch calculate(input) {
        case .value(let v)?: result = formatNumber(v)
        case .converted(let v, let unit)?: result = "\(formatNumber(v)) \(["c": "°C", "°c": "°C", "f": "°F", "°f": "°F", "k": "K"][unit] ?? unit)"
        case .needsRates(let a, let from, let to)?:
            result = "…"
            withRates(from) { rates in
                guard let r = rates[to] else { self.result = "Mata uang \(to) tidak dikenal"; return }
                self.result = "\(formatNumber(a * r)) \(to)"
            }
        case nil: result = input.isEmpty ? "" : "?"
        }
    }

    func commit() {
        guard !result.isEmpty, result != "?", result != "…" else { return }
        history.insert((input, result), at: 0)
        history = Array(history.prefix(5))
        copyText(result.components(separatedBy: " ").first ?? result)
    }

    /// Free ECB-based rates (open.er-api.com, no key), cached for an hour per base currency.
    private func withRates(_ base: String, _ done: @escaping ([String: Double]) -> Void) {
        if base == ratesBase, Date().timeIntervalSince(ratesAt) < 3600 { done(rates); return }
        URLSession.shared.dataTask(with: URL(string: "https://open.er-api.com/v6/latest/\(base)")!) { d, _, _ in
            let r = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["rates"] as? [String: NSNumber]
            DispatchQueue.main.async {
                guard let r else { self.result = d == nil ? "Tidak ada koneksi" : "Mata uang \(base) tidak dikenal"; return }
                self.rates = r.mapValues(\.doubleValue)
                self.ratesBase = base
                self.ratesAt = Date()
                done(self.rates)
            }
        }.resume()
    }
}

/// Paired Bluetooth devices with battery levels and one-click connect (menu bar, Baterai tab).
struct DevicesCard: View {
    @ObservedObject var bt: BluetoothModel

    var body: some View {
        Card(title: "Perangkat Bluetooth", icon: "airpods") {
            let connected = bt.devices.filter(\.connected), audio = bt.devices.filter { !$0.connected && $0.isAudio }
            if connected.isEmpty {
                Text(bt.devices.isEmpty ? "Belum ada perangkat yang dipasangkan." : "Tidak ada perangkat yang tersambung.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(Array(connected.enumerated()), id: \.element.id) { i, d in
                HStack(spacing: 10) {
                    IconBadge(icon: d.icon, color: d.connected ? Palette.cycle[i % Palette.cycle.count] : Palette.slate, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if !d.connected {
                            Text("Tidak tersambung").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        } else if d.batteries.isEmpty {
                            Text("Tersambung").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Palette.green)
                        } else {
                            HStack(spacing: 8) {
                                ForEach(d.batteries, id: \.0) { label, p in
                                    HStack(spacing: 4) {
                                        if !label.isEmpty { Text(label).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary) }
                                        Meter(value: Double(p) / 100, color: p <= 20 ? Palette.red : Palette.green).frame(width: 34)
                                        Text("\(p)%").font(.system(size: 10.5, weight: .heavy, design: .rounded)).monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    if bt.busy == d.address {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Putuskan") { bt.toggle(d) }.controlSize(.small)
                    }
                }
            }
            if !audio.isEmpty {
                Text("Sambungkan cepat").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(audio.prefix(4)) { d in
                        Button { bt.toggle(d) } label: {
                            HStack(spacing: 6) {
                                if bt.busy == d.address { ProgressView().controlSize(.mini) } else { Image(systemName: d.icon).font(.system(size: 11, weight: .bold)) }
                                Text(d.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Palette.teal.opacity(0.13), in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { bt.start() }
        .onDisappear { bt.stop() }
    }
}
