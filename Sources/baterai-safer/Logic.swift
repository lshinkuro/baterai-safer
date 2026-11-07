import SwiftUI

enum Paths {
    static let dir = "/Library/Application Support/BateraiSafer"
    static let config = dir + "/config.json"
    static let status = dir + "/status.json"
    static let label = "io.github.lshinkuro.baterai-safer"
    static let plist = "/Library/LaunchDaemons/\(label).plist"
    // Per-user data (the app runs as the user; dir above is root-owned)
    static let user = NSHomeDirectory() + "/Library/Application Support/BateraiSafer"
    static let history = user + "/history.json"
    static let clips = user + "/clips.json"
    static let clipDir = user + "/clips"
    static let focus = user + "/focus.json"
    static let notes = user + "/notes.json"
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
    let ps = parsePS("  1   0.0  12000 root     launchd\n 512  12.5 204800 me       Google Chrome Helper\nbad line\n")
    assert(ps.count == 2 && ps[1] == Proc(pid: 512, cpu: 12.5, mb: 200, user: "me", name: "Google Chrome Helper"), "ps parse")
    assert(parsePS("3284   0.2 205792 a2267            WhatsApp\n").first?.name == "WhatsApp", "ps: no leading spaces in name")
    assert(parseLRC("[00:12.50] Halo\n[01:02.00]\nbukan lirik\n") == [Lyric(t: 12.5, line: "Halo"), Lyric(t: 62, line: "")], "lrc")
    let day = { (i: Int) in dayKey(Calendar.current.date(byAdding: .day, value: -i, to: Date())!) }
    assert(focusStreak([day(0): 25, day(1): 50, day(3): 25], today: Date()) == 2, "streak counts back from today")
    assert(focusStreak([day(1): 25, day(2): 25], today: Date()) == 2, "unfinished today keeps the streak")
    assert(focusStreak([day(2): 25], today: Date()) == 0, "gap breaks the streak")
    assert(parseGitStatus("# branch.oid abc\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -1\n1 .M N... 100644 100644 100644 a b README.md\n? new.txt\n")
           == GitStatus(branch: "main", ahead: 2, behind: 1, changes: 2), "git status")
    assert(stripANSI("\u{1B}[1;32mJakarta\u{1B}[0m") == "Jakarta", "ansi")
    assert(checkSummary([]) == "none" && checkSummary(["SUCCESS", "SKIPPED"]) == "pass")
    assert(checkSummary(["SUCCESS", "FAILURE"]) == "fail" && checkSummary(["SUCCESS", "PENDING"]) == "pending", "checks")
    let pr = try! JSONDecoder().decode(GHPR.self, from: Data(#"{"number":7,"title":"t","url":"https://github.com/acme/app/pull/7","author":{"login":"x"},"isDraft":false}"#.utf8)).pr
    assert(pr.repo == "acme/app" && pr.author == "x", "pr repo from url")
    let bb = parseBitbucketPRs(Data(#"{"values":[{"id":42,"version":3,"title":"Fix login","author":{"user":{"name":"budi"}},"toRef":{"displayId":"main","repository":{"slug":"mobile-app","project":{"key":"MOB"}}},"links":{"self":[{"href":"https://bb.example/projects/MOB/repos/mobile-app/pull-requests/42"}]}},{"id":"bad"}]}"#.utf8), reviewer: true)
    assert(bb.count == 1 && bb[0].repo == "MOB/mobile-app" && bb[0].number == 42 && bb[0].version == 3 && bb[0].host == .bitbucket && bb[0].reviewRequested, "bitbucket parse")
    assert(Bitbucket.repoPath(bb[0]) == "/rest/api/1.0/projects/MOB/repos/mobile-app/pull-requests/42")
    assert(checkSummary(["SUCCESSFUL"]) == "pass" && checkSummary(["SUCCESSFUL", "FAILED"]) == "fail" && checkSummary(["INPROGRESS"]) == "pending", "bitbucket checks")
    assert(diffStats("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1,2 @@\n-old\n+new\n+more\ndiff --git a/y b/y\n") == (2, 1, 2), "diff stats")
    assert(cleanCommitMessage("```\nAdd login\n\n- detail\n```") == "Add login\n\n- detail", "commit msg fences")
    assert(cleanCommitMessage("\"Fix bug\"") == "Fix bug", "commit msg quotes")
    let du = parseDu("100\t/h/a\n300\t/h/b c\n400\t/h\n", parent: "/h")
    assert(du.map(\.url.path) == ["/h/b c", "/h/a"] && du[0].size == 300 * 1024, "du parse")
    assert(isProtected(NSHomeDirectory() + "/Library/Caches") && isProtected(NSHomeDirectory()) && !isProtected(NSHomeDirectory() + "/Library/Caches/x"), "protected paths")
    assert(changedFiles("diff --git a/x.swift b/x.swift\n+a\ndiff --git a/old b/src/new.ts\n") == ["x.swift", "src/new.ts"], "changed files")
    let sq = sonarIssues(Data(#"{"issues":[{"rule":"swift:S1172","severity":"MAJOR","component":"p:ios/App/Login.swift","line":12,"message":"Remove unused"},{"rule":"ts:S1","severity":"MINOR","component":"p:web/a.ts","message":"m"}]}"#.utf8), files: ["App/Login.swift"])
    assert(sq == ["- [MAJOR] swift:S1172 ios/App/Login.swift:12 — Remove unused"], "sonar issues filtered to changed files")
    assert(sonarLanguage("TSX") == "ts" && sonarLanguage("swift") == "swift" && sonarLanguage("png") == nil)
    let rp = reviewPrompt(pr, PRDetail(), diff: "d", guides: "=== api-guide.md ===\nx", sonar: "Temuan SonarQube: y")
    assert(rp.contains("PANDUAN TIM") && rp.contains("SONARQUBE") && rp.contains("[sonar]"), "prompt includes context")
    assert(!reviewPrompt(pr, PRDetail(), diff: "d").contains("PANDUAN TIM"), "no empty sections")
    // Dev Utils
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJidWRpIiwiZXhwIjoxMDAwMDAwMDAwfQ.sig"
    let jc = conversions(jwt, now: Date(timeIntervalSince1970: 2_000_000_000))
    assert(jc.map(\.title) == ["JWT header", "JWT payload", "JWT exp — SUDAH KEDALUWARSA"] && jc[1].output.contains("\"sub\" : \"budi\""), "jwt")
    let jsc = conversions(#"{"b":1,"a":[1,2]}"#)
    assert(jsc[0].title == "JSON rapi" && jsc[0].output.hasPrefix("{\n  \"a\"") && jsc[1].title == "JSON ringkas" && jsc[1].output.count == 17, "json pretty (sorted) + minified")
    assert(conversions("1700000000").first?.title == "Timestamp → tanggal" && conversions("1700000000000").first!.output.contains("2023-11-14T22:13:20Z"), "timestamp s/ms")
    assert(conversions("aGFsbyBkdW5pYQ==").contains(Conversion(title: "Base64 decode", output: "halo dunia")), "base64")
    assert(conversions("a%20b%26c").first == Conversion(title: "URL decode", output: "a b&c"), "url decode")
    assert(conversions("abc").contains(Conversion(title: "SHA-256", output: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")), "sha256")
    assert(conversions("abc").contains(Conversion(title: "MD5", output: "900150983cd24fb0d6963f7d28e17f72")), "md5")
    assert(conversions("   ").isEmpty && !conversions("hello world").contains { $0.title == "Base64 decode" }, "no false base64")
    // Meetings
    assert(meetingLink([nil, "Ruang 3", "Join: https://acme.zoom.us/j/123456?pwd=x\nPasscode"])?.absoluteString == "https://acme.zoom.us/j/123456?pwd=x", "zoom link")
    assert(meetingLink(["https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com" && meetingLink(["https://example.com"]) == nil, "meet link")
    let now = Date(), mt = Meeting(title: "Standup", start: now.addingTimeInterval(299), end: now.addingTimeInterval(1200), link: nil, color: nil)
    assert(mt.when(now) == "5m lagi" && mt.isSoon(now) && !Meeting(title: "x", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(4000), link: nil, color: nil).isSoon(now), "meeting timing")
    assert(Meeting(title: "x", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60), link: nil, color: nil).when(now) == "berlangsung")
    // Notes
    assert(Note(text: "# Belanja\n- susu").title == "Belanja" && Note().title == "Catatan baru", "note title")
    let savedFlags = UserDefaults.standard.string(forKey: FeatureFlags.key)
    FeatureFlags.set("music", false); FeatureFlags.set("panel.cleaner", false)
    assert(!NTab.music.enabled && NTab.focus.enabled && !Tab.cleaner.enabled && Tab.battery.enabled, "feature flags off")
    FeatureFlags.set("music", true)
    assert(NTab.music.enabled && FeatureFlags.off() == ["panel.cleaner"], "feature flags on")
    UserDefaults.standard.set(savedFlags, forKey: FeatureFlags.key)
    // Focus
    assert(breakMinutes(25) == 5 && breakMinutes(50) == 10 && breakMinutes(90) == 18 && breakMinutes(10) == 5, "break length")
    let jd = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 14, minute: 5))!
    assert(journalLine(" Laporan Q3 ", "draft selesai\n", minutes: 50, at: jd) == "- 7 Nov 14.05 · 50m · **Laporan Q3** — draft selesai", "journal line")
    assert(journalLine("", "", minutes: 25, at: jd) == "- 7 Nov 14.05 · 25m · **Sesi fokus**", "journal line: empty")
    // Lainnya
    var fc = FullChargeAlert()
    assert(!fc.step(percent: 79, ac: true, target: 80) && fc.step(percent: 80, ac: true, target: 80), "full charge fires at target")
    assert(!fc.step(percent: 80, ac: true, target: 80) && !fc.step(percent: 79, ac: true, target: 80), "fires once, no re-arm at -1%")
    assert(!fc.step(percent: 77, ac: true, target: 80) && fc.step(percent: 80, ac: true, target: 80), "re-arms after dropping 2%+")
    assert(!fc.step(percent: 80, ac: false, target: 80) && fc.step(percent: 80, ac: true, target: 80), "re-arms after unplug")
    assert(ColorPick.hex(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) == "#FF8000" && Color(hexString: "#FF8000") != nil && Color(hexString: "red") == nil, "color hex")
    assert(newDownloads(old: ["a.pdf"], now: ["a.pdf", "b.zip", "c.zip.crdownload", ".DS_Store", "d.part", "e.download", "F.PNG"]) == ["b.zip", "F.PNG"], "new downloads")
    // Meeting pause
    var mp = MeetingPause(); let m1 = Date(timeIntervalSince1970: 1000), m2 = Date(timeIntervalSince1970: 5000)
    assert(mp.step(meeting: m1, focusing: true) == .pause, "pause when meeting starts")
    assert(mp.step(meeting: m1, focusing: false) == .none, "stay paused during meeting")
    assert(mp.step(meeting: nil, focusing: false) == .offerResume && mp.step(meeting: nil, focusing: false) == .none, "offer resume once")
    assert(mp.step(meeting: m2, focusing: true) == .pause && mp.step(meeting: m2, focusing: true) == .none, "manual resume mid-meeting sticks")
    assert(mp.step(meeting: nil, focusing: true) == .none, "no resume hint after manual resume")
    assert(mp.step(meeting: m1, focusing: false) == .none, "not focusing: nothing")
    // AI usage
    let usageNow = isoDate("2026-11-07T10:00:00.000Z")!
    let u = """
    {"type":"assistant","timestamp":"2026-11-07T09:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-x","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}
    {"type":"assistant","timestamp":"2026-11-07T09:00:01.000Z","requestId":"r1","message":{"id":"m1","model":"claude-x","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}
    {"type":"assistant","timestamp":"2026-10-01T09:00:00.000Z","requestId":"r0","message":{"id":"m0","model":"claude-x","usage":{"input_tokens":999,"output_tokens":999}}}
    {"type":"user","message":{"content":"no usage here"}}
    not json "usage"
    """
    var ur = UsageReport(), seenU = Set<String>()
    addClaudeUsage(u[...], since: usageNow.addingTimeInterval(-7 * 86400), today: dayKey(isoDate("2026-11-07T09:00:00.000Z")!), ours: true, into: &ur, seen: &seenU)
    assert(ur.total == 135 && ur.models == ["claude-x": 135] && ur.ours == 135, "usage: dedupe + window")
    assert(ur.today.input == 10 && ur.today.output == 5 && ur.today.cache == 120, "usage: today split")
    assert(tokens(1_234_567) == "1.2M" && tokens(999) == "999", "token format")
    assert(UsageModel.ourFolder.hasSuffix("-Library-Application-Support-BateraiSafer-ai"), "our claude folder")
    print("selftest ok")
}
