import Foundation

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "daemon": Daemon.run()
case "install-daemon": Daemon.install(user: args.dropFirst().first ?? ProcessInfo.processInfo.environment["SUDO_USER"] ?? "root")
case "uninstall-daemon": Daemon.uninstall()
case "selftest": selfTest()
case "status":
    let b = Battery.read(), s = load(Paths.status, Status())
    print("\(b.percent)% ac=\(b.ac) charging=\(s.charging) adapter=\(s.adapter) health=\(b.health)% cycles=\(b.cycles) temp=\(b.temp.map { String(format: "%.1f", $0) } ?? "-")")
case nil: BateraiApp.main()
default:
    print("usage: baterai-safer [daemon|install-daemon [user]|uninstall-daemon|status|selftest]")
    exit(2)
}
