import Foundation

enum Paths {
    static let dir = "/Library/Application Support/BateraiSafer"
    static let config = dir + "/config.json"
    static let status = dir + "/status.json"
    static let label = "io.github.lshinkuro.baterai-safer"
    static let plist = "/Library/LaunchDaemons/\(label).plist"
}

struct Config: Codable, Equatable {
    var enabled = true
    var limit = 80
    var sailing = 5           // recharge only below limit - sailing; 0 = off
    var heatProtection = true
    var maxTemp = 35.0
    var autoDischarge = false // run on battery while above limit, even when plugged in
    var topUp = false         // temporarily charge to 100%
    var stopOnSleep = true
    var calibrateAt = 0.0     // request timestamp; 0 = none / cancel
}

struct Status: Codable {
    var wantCharge = true     // sailing hysteresis state
    var charging = true
    var adapter = true
    var calibration = 0       // 0 off, 1 charge to 100, 2 drain to 10, 3 charge to 100
    var calibrationHandled = 0.0
    var updated = 0.0
}

func load<T: Decodable>(_ path: String, _ fallback: T) -> T {
    guard let d = FileManager.default.contents(atPath: path) else { return fallback }
    return (try? JSONDecoder().decode(T.self, from: d)) ?? fallback
}

func save<T: Encodable>(_ v: T, _ path: String) {
    try? JSONEncoder().encode(v).write(to: URL(fileURLWithPath: path), options: .atomic)
}

/// Pure policy: given settings and a battery reading, decide charging and adapter state.
func decide(_ c: Config, _ b: Battery, _ s: inout Status) -> (charge: Bool, adapter: Bool) {
    guard c.enabled else { s.calibration = 0; return (true, true) }
    let hot = c.heatProtection && (b.temp ?? 0) >= c.maxTemp

    if c.calibrateAt > s.calibrationHandled { s.calibration = 1; s.calibrationHandled = c.calibrateAt }
    if c.calibrateAt == 0 { s.calibration = 0 }
    if s.calibration == 1 && b.percent >= 100 { s.calibration = 2 }
    if s.calibration == 2 && b.percent <= 10 { s.calibration = 3 }
    if s.calibration == 3 && b.percent >= 100 { s.calibration = 0 }
    switch s.calibration {
    case 1, 3: return (!hot, true)
    case 2: return (false, false)
    default: break
    }

    let target = c.topUp ? 100 : min(max(c.limit, 20), 100)
    s.wantCharge = s.wantCharge ? b.percent < target : b.percent < target - max(c.sailing, 0)
    let adapter = !(c.autoDischarge && b.percent > target)
    return (s.wantCharge && adapter && !hot, adapter)
}

/// Native macOS charge limit (macOS 27+) only accepts 80–100 in steps of 5; 100 means off.
func nativeTarget(_ c: Config, _ s: Status) -> Int {
    if !c.enabled || c.topUp || s.calibration == 1 || s.calibration == 3 { return 100 }
    return min(100, max(80, (c.limit + 4) / 5 * 5))
}

func selfTest() {
    func run(_ c: Config, _ pct: Int, temp: Double = 30, _ s: inout Status) -> (Bool, Bool) {
        var b = Battery(); b.percent = pct; b.temp = temp
        let r = decide(c, b, &s); return (r.charge, r.adapter)
    }
    var c = Config(), s = Status()
    assert(run(c, 50, &s) == (true, true))
    assert(run(c, 80, &s) == (false, true))
    assert(run(c, 77, &s) == (false, true), "sailing: hold until below 75")
    assert(run(c, 74, &s) == (true, true))
    assert(run(c, 50, temp: 40, &s) == (false, true), "heat protection")
    c.autoDischarge = true
    assert(run(c, 90, &s) == (false, false), "discharge to limit")
    c.topUp = true
    assert(run(c, 90, &s) == (true, true), "top up")
    c = Config(); s = Status(); c.calibrateAt = 1
    assert(run(c, 50, &s) == (true, true) && s.calibration == 1)
    assert(run(c, 100, &s) == (false, false) && s.calibration == 2)
    assert(run(c, 10, &s) == (true, true) && s.calibration == 3)
    _ = run(c, 100, &s); assert(s.calibration == 0)
    assert(run(c, 100, &s) == (false, true), "calibration not re-triggered")
    c = Config(); s = Status(); c.limit = 82
    assert(nativeTarget(c, s) == 85)
    c.limit = 60; assert(nativeTarget(c, s) == 80)
    s.calibration = 1; assert(nativeTarget(c, s) == 100)
    print("selftest ok")
}
