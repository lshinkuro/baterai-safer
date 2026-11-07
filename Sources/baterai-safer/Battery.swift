import Foundation
import IOKit
import CSMC

struct Battery {
    var percent = 0
    var ac = false
    var charging = false
    var cycles = 0
    var maxCapacity = 0     // mAh
    var designCapacity = 0  // mAh
    var temp: Double?       // °C

    var health: Int { designCapacity > 0 ? maxCapacity * 100 / designCapacity : 0 }

    static func read() -> Battery {
        var b = Battery()
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard svc != 0, IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return b }
        let data = d["BatteryData"] as? [String: Any] ?? [:]
        b.percent = d["CurrentCapacity"] as? Int ?? 0
        b.ac = d["ExternalConnected"] as? Bool ?? false
        b.charging = d["IsCharging"] as? Bool ?? false
        b.cycles = d["CycleCount"] as? Int ?? 0
        b.maxCapacity = data["FullChargeCapacity"] as? Int ?? d["AppleRawMaxCapacity"] as? Int ?? 0
        b.designCapacity = data["DesignCapacity"] as? Int ?? d["DesignCapacity"] as? Int ?? 0
        b.temp = SMC.batteryTemp() ?? (d["Temperature"] as? Int).map { Double($0) / 100 }
        return b
    }
}

enum SMC {
    static func read(_ key: String) -> (bytes: [UInt8], type: String)? {
        var buf = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 32, type: UInt32 = 0
        guard smc_read(key, &buf, &size, &type) == 0 else { return nil }
        let t = String(bytes: withUnsafeBytes(of: type.bigEndian, Array.init), encoding: .ascii) ?? ""
        return (Array(buf.prefix(Int(size))), t)
    }

    static func write(_ key: String, _ bytes: [UInt8]) -> Bool { smc_write(key, bytes, UInt32(bytes.count)) == 0 }
    static func has(_ key: String) -> Bool { smc_has_key(key) != 0 }

    static func batteryTemp() -> Double? {
        guard let (b, t) = read("TB0T") else { return nil }
        switch t {
        case "flt ": return b.count == 4 ? Double(b.withUnsafeBytes { $0.load(as: Float.self) }) : nil
        case "sp78": return b.count == 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 : nil
        default: return nil
        }
    }

    /// false on macOS 27+ firmware, where charging is limited via `native_limit_set` instead.
    static let canInhibit = has("CHTE") || has("CH0B")

    // Newer Apple Silicon firmware uses CHTE/CHIE; older uses CH0B+CH0C / CH0I.
    @discardableResult
    static func setCharging(_ on: Bool) -> Bool {
        if has("CHTE") { return write("CHTE", on ? [0, 0, 0, 0] : [1, 0, 0, 0]) }
        let v: UInt8 = on ? 0 : 2
        return write("CH0B", [v]) && write("CH0C", [v])
    }

    @discardableResult
    static func setAdapter(_ on: Bool) -> Bool {
        if has("CHIE") { return write("CHIE", [on ? 0 : 8]) }
        return write("CH0I", [on ? 0 : 1])
    }
}
