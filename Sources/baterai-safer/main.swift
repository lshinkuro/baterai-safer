import Foundation

let args = CommandLine.arguments.dropFirst()
switch args.first {
#if !LITE
case "daemon": Daemon.run()
case "install-daemon": Daemon.install(user: args.dropFirst().first ?? ProcessInfo.processInfo.environment["SUDO_USER"] ?? "root")
case "uninstall-daemon": Daemon.uninstall()
#endif
case "selftest": selfTest()
case "ai-usage":
    let t = Date()
    UsageModel.shared.refresh {
        let r = UsageModel.shared.report
        print("7d=\(tokens(r.total)) today=\(tokens(r.today.input + r.today.output + r.today.cache)) ours=\(tokens(r.ours)) models=\(r.models.mapValues(tokens)) in \(String(format: "%.1f", Date().timeIntervalSince(t)))s")
        exit(0)
    }
    RunLoop.main.run()
case "status":
    let b = Battery.read(), s = load(Paths.status, Status())
    print("\(b.percent)% ac=\(b.ac) charging=\(s.charging) adapter=\(s.adapter) health=\(b.health)% cycles=\(b.cycles) temp=\(b.temp.map { String(format: "%.1f", $0) } ?? "-")")
case nil: BateraiApp.main()
default:
    print("usage: poni [daemon|install-daemon [user]|uninstall-daemon|status|ai-usage|selftest]")
    exit(2)
}
