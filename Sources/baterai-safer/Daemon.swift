import Foundation
import IOKit
import IOKit.pwr_mgt

// Root daemon: owns SMC writes, so limits hold while the menu bar app is closed.
enum Daemon {
    static var status = resumed(load(Paths.status, Status()), now: Date().timeIntervalSince1970)
    static var rootPort: io_connect_t = 0

    static func apply(charge: Bool, adapter: Bool) {
        if charge != status.charging || adapter != status.adapter {
            log("charge=\(charge) adapter=\(adapter)")
        }
        if SMC.canInhibit { SMC.setCharging(charge) }
        SMC.setAdapter(adapter)
        status.charging = charge
        status.adapter = adapter
        status.updated = Date().timeIntervalSince1970
        save(status, Paths.status)
    }

    static var binaryMisses = 0

    static func tick() {
        // `brew uninstall` without `uninstall-daemon` leaves us running; restore power and remove ourselves.
        // Two misses in a row, so the brief opt/ relink during `brew upgrade` doesn't trigger it.
        binaryMisses = FileManager.default.fileExists(atPath: CommandLine.arguments[0]) ? 0 : binaryMisses + 1
        if binaryMisses >= 2 {
            log("binary removed, uninstalling daemon")
            try? FileManager.default.removeItem(atPath: Paths.plist)
            apply(charge: true, adapter: true)
            sh("/bin/launchctl", "bootout", "system/\(Paths.label)")
            exit(0)
        }
        let c = load(Paths.config, Config()), b = Battery.read()
        var r = decide(c, b, &status)
        if !SMC.canInhibit {
            // Native mode: firmware stops at the limit itself. No heat cut here: on battery the temp stays high,
            // so cutting the adapter for heat locked users out of charging entirely.
            r.charge = r.adapter && b.charging
        }
        apply(charge: r.charge, adapter: r.adapter)
    }

    static func run() {
        guard getuid() == 0 else { fatal("daemon must run as root") }
        tick()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in tick() }

        // Re-enable charging on stop, so uninstalling never leaves the battery stuck.
        signal(SIGTERM, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { apply(charge: true, adapter: true); exit(0) }
        term.resume()

        var notifier: IONotificationPortRef?
        var iter: io_object_t = 0
        rootPort = IORegisterForSystemPower(nil, &notifier, { _, _, type, arg in
            switch type {
            case 0xE000_0280: // kIOMessageSystemWillSleep (macro not imported)
                // Never sleep with the adapter cut (battery would drain); optionally freeze charging.
                let c = load(Paths.config, Config())
                Daemon.apply(charge: c.enabled && c.stopOnSleep ? false : Daemon.status.charging, adapter: true)
                IOAllowPowerChange(Daemon.rootPort, Int(bitPattern: arg))
            case 0xE000_0270: // kIOMessageCanSystemSleep
                IOAllowPowerChange(Daemon.rootPort, Int(bitPattern: arg))
            case 0xE000_0300: // kIOMessageSystemHasPoweredOn
                Daemon.tick()
            default: break
            }
        }, &iter)
        if let notifier { CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(notifier).takeUnretainedValue(), .defaultMode) }
        RunLoop.main.run()
    }

    // Homebrew upgrades replace the Cellar path, so point launchd at the stable opt/ path.
    static func stableBinary() -> String {
        let p = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        return p.replacingOccurrences(of: #"/Cellar/([^/]+)/[^/]+/"#, with: "/opt/$1/", options: .regularExpression)
    }

    static func install(user: String) {
        guard getuid() == 0 else { fatal("run with sudo") }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Paths.dir, withIntermediateDirectories: true)
        // The menu bar app (running as the user) writes config.json here.
        chown(Paths.dir, user)
        if !fm.fileExists(atPath: Paths.config) { save(Config(), Paths.config); chown(Paths.config, user) }
        let plist: [String: Any] = [
            "Label": Paths.label,
            "ProgramArguments": [stableBinary(), "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardErrorPath": "/var/log/baterai-safer.log",
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try! data.write(to: URL(fileURLWithPath: Paths.plist))
        sh("/bin/launchctl", "bootout", "system/\(Paths.label)")
        guard sh("/bin/launchctl", "bootstrap", "system", Paths.plist) == 0 else { fatal("launchctl bootstrap failed") }
        print("daemon installed")
    }

    static func uninstall() {
        guard getuid() == 0 else { fatal("run with sudo") }
        sh("/bin/launchctl", "bootout", "system/\(Paths.label)")
        try? FileManager.default.removeItem(atPath: Paths.plist)
        SMC.setCharging(true)
        SMC.setAdapter(true)
        print("daemon removed, charging restored")
    }

    static func chown(_ path: String, _ user: String) { sh("/usr/sbin/chown", user, path) }
}

@discardableResult
func sh(_ args: String...) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: args[0])
    p.arguments = Array(args.dropFirst())
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

func log(_ s: String) { FileHandle.standardError.write("\(Date()) \(s)\n".data(using: .utf8)!) }
func fatal(_ s: String) -> Never { log(s); exit(1) }
