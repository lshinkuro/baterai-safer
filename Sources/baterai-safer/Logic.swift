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

/// A calibration left by a helper that stopped hours ago is dropped, not resumed: resuming would cut
/// the adapter and drain the battery to 10% long after the user started it (and maybe forgot it).
func resumed(_ s: Status, now: Double) -> Status {
    var s = s
    if s.calibration != 0 && now - s.updated > 6 * 3600 { s.calibration = 0 }
    return s
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
    var hm = Hangman(word: "CAT")
    for c in "XCA" { hm.guess(c) }
    assert(hm.misses == 1 && !hm.won && !hm.lost, "hangman: counts misses")
    hm.guess("T")
    assert(hm.won && { var h = hm; h.guess("Q"); return h.misses == 1 }(), "hangman: no guesses after the end")
    var hanged = Hangman(word: "CAT")
    for c in "BDEFGH" { hanged.guess(c) }
    assert(hanged.lost, "hangman: six misses lose")
    assert(hangmanWordIsUsable("TIGER", recent: [], isWord: { _ in true }) && !hangmanWordIsUsable("TIGER", recent: ["TIGER"], isWord: { _ in true }) && !hangmanWordIsUsable("ICE", recent: [], isWord: { _ in true }) && !hangmanWordIsUsable("CAFÉS", recent: [], isWord: { _ in true }) && !hangmanWordIsUsable("ZZZZ", recent: [], isWord: { _ in false }), "hangman: word checks")
    let sd = Sudoku.generate()
    var sdCopy = sd.cells, sdFilled = sd.cells, sdCount = 0, sdFirst = 0
    _ = Sudoku.solve(&sdCopy, limit: 2, found: &sdCount)
    _ = Sudoku.solve(&sdFilled, limit: 1, found: &sdFirst)
    assert(sdCount == 1 && sdFilled == sd.solution && sd.cells.filter { $0 == 0 }.count == Sudoku.blanks, "sudoku: one solution, right number of blanks")
    assert((0..<81).allSatisfy { i in var b = sd.solution; let v = b[i]; b[i] = 0; return Sudoku.options(b, i) == [v] }, "sudoku: solution is valid")
    var sdWrong = sd
    if let i = sd.cells.firstIndex(of: 0), let given = (0..<9).map({ i / 9 * 9 + $0 }).first(where: { sd.cells[$0] != 0 }) {
        sdWrong.cells[i] = sd.solution[i]
        assert(!sdWrong.conflict(i), "sudoku: right digit is no conflict")
        sdWrong.cells[i] = sd.cells[given]
        assert(sdWrong.conflict(i), "sudoku: repeat in a row is a conflict")
    }
    assert(abs(careScore(water: 4, goal: 8, breaks: 3, breakGoal: 3, habitsDone: 0, habits: 0) - 0.75) < 0.001 && careScore(water: 99, goal: 8, breaks: 9, breakGoal: 3, habitsDone: 2, habits: 2) == 1, "care score")
    let oldCare = try! JSONDecoder().decode(SelfCareData.self, from: Data(#"{"water":{"2026-11-07":3},"waterGoal":10,"habits":[]}"#.utf8))
    assert(oldCare.waterGoal == 10 && oldCare.water["2026-11-07"] == 3 && oldCare.mood.isEmpty, "old selfcare.json keeps its data")
    assert(SelfCare.Kind.stretch.step(elapsed: 0) == "Putar bahu pelan-pelan" && SelfCare.Kind.stretch.step(elapsed: 59) == "Berdiri dan tarik napas dalam", "stretch steps")
    let w1 = Word(word: "a", meaning: "x", example: ""), w2 = Word(word: "b", meaning: "y", example: ""), w3 = Word(word: "c", meaning: "z", example: "")
    let t1 = Date(timeIntervalSince1970: 1000), seenCard = Flashcard(box: 2, due: t1 - 5)
    assert(studyQueue([w1, w2, w3], seen: { $0 == w3 ? seenCard : nil }, now: t1, newLeft: 1) == [w3, w1], "reviews first, new words capped")
    assert(studyQueue([w1], seen: { _ in nil }, now: t1, newLeft: 0).isEmpty, "no new words past the limit")
    assert(Flashcard(box: 2).reviewed(knew: true, at: t1, promote: false).box == 2 && Flashcard(box: 2).reviewed(knew: true, at: t1).box == 3, "only typed answers promote")
    let mizu = Word(word: "水", meaning: "air · みず (mizu)", example: "")
    assert(typedCorrect(" Mizu ", mizu, .ja) && typedCorrect("みず", mizu, .ja) && typedCorrect("水", mizu, .ja) && !typedCorrect("", mizu, .ja) && promptMeaning(mizu, .ja) == "air", "japanese typed answers")
    assert(typedCorrect("facil", Word(word: "fácil", meaning: "mudah", example: ""), .es) && !typedCorrect("かっこう", Word(word: "がっこう", meaning: "sekolah", example: ""), .ja), "accents")
    assert(parseCorrection("✏️ She goes. — Subjek — butuh goes.\nNice!")! == ("She goes.", "Subjek — butuh goes.") && parseCorrection("Nice!") == nil, "chat correction")
    assert(Palette.customHue("hue:0.530") == 0.53 && Palette.customHue("mint") == nil && Palette.color("hue:x") == Palette.color("mint"), "custom accent id")
    assert(Palette.color("aurora") == Palette.color("mint") && Palette.color2("aurora") == Palette.color("sky") && Palette.color2("violet") == Palette.color("violet"), "gradient accent stops")
    let jakarta = TimeZone(identifier: "Asia/Jakarta")!
    func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    assert(ramadanDay(on: iso("2027-02-08T05:00:00Z"), shift: 0, tz: jakarta) == 1, "ramadan first day")
    assert(ramadanDay(on: iso("2027-02-08T05:00:00Z"), shift: 1, tz: jakarta) == nil, "ramadan shifted a day later")
    assert(ramadanDay(on: iso("2026-11-09T05:00:00Z"), shift: 0, tz: jakarta) == nil, "not ramadan")
    assert(zakatFitrah(people: 4, ricePrice: 15000) == 150000, "zakat fitrah")
    assert(zakatMal(wealth: 100_000_000, debt: 0, goldPrice: 1_000_000).due == 2_500_000 && zakatMal(wealth: 84_000_000, debt: 0, goldPrice: 1_000_000).due == 0, "zakat mal nisab")
    assert(zakatMal(wealth: 90_000_000, debt: 10_000_000, goldPrice: 1_000_000).due == 0 && zakatMal(wealth: 5, debt: 0, goldPrice: 0).due == 0, "zakat mal debt and empty price")
    func perft(_ p: Chess, _ d: Int) -> Int { d == 0 ? 1 : p.legal().reduce(0) { $0 + perft(p.after($1), d - 1) } }
    assert(perft(Chess(), 3) == 8902, "chess move generation")
    var fools = Chess()
    for (from, to) in [(53, 45), (12, 28), (54, 38), (3, 39)] { fools = fools.after(.init(from: from, to: to)) }
    assert(fools.outcome(repeated: false) == "Komputer menang", "chess checkmate")
    var mateInOne = Chess()
    for (from, to) in [(52, 36), (12, 28), (61, 34), (1, 18), (59, 31), (6, 21)] { mateInOne = mateInOne.after(.init(from: from, to: to)) }
    assert(mateInOne.after(mateInOne.bestMove(depth: 2)!).outcome(repeated: false) == "Kamu menang!", "chess finds mate in one")
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
    assert(parsePS("9 0.1 100 root baterai-safer\n10 0.1 100 me baterai-safer\n").map(\.name) == ["Poni helper", "Poni"], "ps: own process shows as Poni")
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
    assert(notesHTML("# Belanja\n- susu & <roti>\n\nkopi") == "<div><h1>Belanja</h1></div><div>- susu &amp; &lt;roti&gt;</div><div><br></div><div>kopi</div>", "notes html")
    let nl = parseNotesList("x-coredata://A/ICNote/p1\u{1F}-120\u{1F}false\u{1F}Belanja\nsusu\n\u{1E}x-coredata://A/ICNote/p2\u{1F}-5\u{1F}true\u{1F}Foto\u{1E}junk\u{1E}", now: Date(timeIntervalSince1970: 1000))
    assert(nl.count == 2 && nl[0].text == "Belanja\nsusu" && nl[0].updated == Date(timeIntervalSince1970: 880) && !nl[0].readOnly && nl[1].readOnly && nl[0].synced, "notes list parse")
    let legacy = try! JSONDecoder().decode([Note].self, from: Data(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"lama","updated":0}]"#.utf8))
    assert(legacy[0].text == "lama" && !legacy[0].synced && !legacy[0].dirty, "legacy note decodes and uploads as new")
    let savedFlags = UserDefaults.standard.string(forKey: FeatureFlags.key)
    FeatureFlags.set("music", false); FeatureFlags.set("panel.cleaner", false)
    assert(!NTab.music.enabled && NTab.focus.enabled && !Tab.cleaner.enabled && Tab.battery.enabled, "feature flags off")
    FeatureFlags.set("music", true)
    assert(NTab.music.enabled && FeatureFlags.off() == ["panel.cleaner"], "feature flags on")
    UserDefaults.standard.set(savedFlags, forKey: FeatureFlags.key)
    assert(orderedTabs("git,music,bogus") == [.git, .music] + NTab.allCases.filter { $0 != .git && $0 != .music } && orderedTabs("") == NTab.allCases, "tab order")
    assert(scrollGesture(dx: 0, dy: 40, inverted: true) == .down && scrollGesture(dx: 0, dy: -40, inverted: false) == .down, "scroll down either setting")
    assert(scrollGesture(dx: 40, dy: 5, inverted: true) == .right && scrollGesture(dx: -40, dy: 5, inverted: true) == .left && scrollGesture(dx: 5, dy: 5, inverted: true) == nil, "scroll sideways / too small")
    // Focus
    assert(!earnedLongBreak(0) && !earnedLongBreak(3) && earnedLongBreak(4), "long break after 4 sessions")
    assert(fullChargeMessage(percent: 80, own: " Cabut! ") == "Cabut!" && fullChargeMessage(percent: 80, own: "  ") == "Baterai 80% · boleh cabut charger", "charge message")
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
    var gc = Calendar(identifier: .gregorian); gc.firstWeekday = 2; gc.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    let nov = monthGrid(gc.date(from: DateComponents(year: 2026, month: 11, day: 15))!, gc)
    assert(nov.count == 42 && nov.prefix(6).allSatisfy { $0 == nil } && gc.component(.day, from: nov[6]!) == 1 && gc.component(.day, from: nov[35]!) == 30, "month grid (Nov 2026 starts Sunday, Monday-first)")
    let feb = monthGrid(gc.date(from: DateComponents(year: 2027, month: 2, day: 1))!, gc)
    assert(feb.count == 28 && feb.compactMap { $0 }.count == 28, "month grid (Feb 2027 starts Monday, 4 weeks)")
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    assert(eventStatus(start: t0, end: t0 + 3600, now: t0 + 60)! == ("berlangsung", true), "event live")
    assert(eventStatus(start: t0 + 25 * 60, end: t0 + 3600, now: t0)! == ("25m lagi", false) && eventStatus(start: t0 + 3 * 3600, end: t0 + 4 * 3600, now: t0)! == ("3j lagi", false), "event soon")
    assert(eventStatus(start: t0, end: t0 + 60, now: t0 + 120) == nil && eventStatus(start: t0 + 13 * 3600, end: t0 + 14 * 3600, now: t0) == nil, "event past / far")
    assert(shortDuration(90) == "1j 30m" && shortDuration(30) == "30m" && shortReminder(60) == "1j", "short labels")
    assert(durationLabel(45) == "45 menit" && durationLabel(120) == "2 jam" && durationLabel(90) == "1 jam 30 menit", "duration label")
    assert(reminderLabel(nil) == "Tanpa pengingat" && reminderLabel(10) == "10 menit sebelum" && reminderLabel(60) == "1 jam sebelum", "reminder label")
    // Belajar bahasa
    let c0 = Flashcard(), tNow = Date(timeIntervalSince1970: 0)
    let c1 = c0.reviewed(knew: true, at: tNow), c2 = c1.reviewed(knew: true, at: tNow)
    assert(c1.box == 1 && c1.due == tNow.addingTimeInterval(86400) && c2.box == 2 && c2.due == tNow.addingTimeInterval(3 * 86400), "leitner up")
    let c3 = c2.reviewed(knew: false, at: tNow)
    assert(c3.box == 0 && c3.due == tNow.addingTimeInterval(600), "leitner miss resets")
    var c5 = Flashcard(box: 5); c5 = c5.reviewed(knew: true, at: tNow)
    assert(c5.box == 5 && c5.due == tNow.addingTimeInterval(30 * 86400), "leitner caps at box 5")
    let pw = parseWordLines("Here are words:\n1. Abundant | berlimpah | Water is abundant.\n- precise | tepat | Be precise.\nbroken line\n| | x")
    assert(pw == [Word(word: "abundant", meaning: "berlimpah", example: "Water is abundant."), Word(word: "precise", meaning: "tepat", example: "Be precise.")], "ai word lines")
    assert(Lang.allCases.allSatisfy { Set($0.starter.map(\.word)).count == $0.starter.count }, "starter decks have no duplicates")
    assert(spokenPart("✏️ I went home. — lampau\nNice! Where?") == "Nice! Where?" && spokenPart("Hola") == "Hola", "spoken part skips correction")
    assert(spokenPart("✏️ x — y\nいいですね！\n(Ii desu ne!)") == "いいですね！", "spoken part skips romaji line")
    assert(Lang.allCases.allSatisfy { !$0.title.isEmpty && !$0.testName.isEmpty && !$0.sample.isEmpty }, "every language has its strings")
    let pq = parseQuestions("Here you go:\n\nQ: She ____ to work yesterday.\nA) go\nB) **went**\nC) goes\nD) going\nANSWER: B\nWHY: Lampau.\n\nQ: broken\nA) x\nANSWER: A\n\nq: The data ____ clear.\nA) is\nB) are\nC) be\nD) been\nAnswer: a\nWhy: Uncountable.")
    assert(pq == [Question(q: "She ____ to work yesterday.", options: ["go", "went", "goes", "going"], answer: 1, why: "Lampau."),
                  Question(q: "The data ____ clear.", options: ["is", "are", "be", "been"], answer: 0, why: "Uncountable.")], "test questions")
    let oldLang = try! JSONDecoder().decode(LangState.self, from: Data(#"{"lang":"es","target":15,"cards":{"es:hola":{"box":2,"due":0}},"log":{"2026-11-07":3},"custom":{}}"#.utf8))
    assert(oldLang.lang == .es && oldLang.target == 15 && oldLang.cards["es:hola"]?.box == 2 && oldLang.engine == "apple" && oldLang.tests.isEmpty, "old lang.json keeps progress")
    assert(isNewer("0.6.10", than: "0.6.9") && isNewer("v0.7.0", than: "0.6.9") && isNewer("1.0", than: "0.9.9"), "newer versions")
    assert(!isNewer("0.6.9", than: "0.6.9") && !isNewer("0.6.8", than: "0.6.9") && !isNewer("0.6.9", than: "0.6.9-dev") && !isNewer("0.6", than: "0.6.0"), "not newer")
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
    var sn = Snake(); sn.food = Snake.Point(x: 6, y: 5)
    sn.step(spawn: { Snake.Point(x: 0, y: 0) })
    assert(sn.score == 1 && sn.body[0] == Snake.Point(x: 6, y: 5) && sn.food == Snake.Point(x: 0, y: 0), "snake: eats and grows")
    sn.turn(Snake.Point(x: -1, y: 0)); sn.step()
    assert(sn.body[0] == Snake.Point(x: 7, y: 5), "snake: can't reverse into its neck")
    sn.turn(Snake.Point(x: 0, y: -1)); for _ in 0..<6 { sn.step() }
    assert(sn.over, "snake: wall ends the game")
    var tt = Tetris(); tt.kind = 0; tt.rot = 0; tt.x = 0; tt.y = 0 // flat I piece at the top-left
    for c in 4..<Tetris.cols { tt.board[Tetris.rows - 1][c] = true } // bottom row missing exactly its four cells
    tt.drop()
    assert(tt.lines == 1 && tt.score == 100 + Tetris.rows - 2 && !tt.board.joined().contains(true), "tetris: hard drop completes and clears the row")
    var tw = Tetris(); tw.kind = 0; tw.rot = 0; tw.x = Tetris.cols - 2; tw.y = 0
    tw.rotate()
    assert(tw.rot == 1 && tw.piece.allSatisfy { $0.x < Tetris.cols }, "tetris: rotation kicks off the wall")
    var mem = Memory(shuffled: false)
    mem.flip(0); mem.flip(1)
    assert(mem.moves == 1 && mem.matched.isEmpty && mem.open == [0, 1], "memory: miss stays open")
    mem.flip(8)
    assert(mem.open == [8], "memory: third card hides the miss")
    mem.flip(0)
    assert(mem.matched == [0, 8] && mem.open.isEmpty, "memory: pair matches")
    let xs: [Character?] = ["X", "X", nil, nil, "O", nil, nil, nil, nil]
    assert(XO.bestMove(xs) == 2, "xo: blocks a win")
    let os: [Character?] = ["X", "X", nil, "O", "O", nil, "X", nil, nil]
    assert(XO.bestMove(os) == 5, "xo: takes a win")
    let fenced = extractVisual("Ini dia:\n```svg\n<svg viewBox=\"0 0 10 10\"><rect/></svg>\n```\nSelesai.")
    assert(fenced.visual?.kind == .svg && fenced.visual?.code == "<svg viewBox=\"0 0 10 10\"><rect/></svg>" && fenced.text == "Ini dia:\n\nSelesai.", "visual: svg fence")
    assert(extractVisual("```html\n<div id=c></div><script>1</script>\n```").visual?.kind == .html, "visual: html fence")
    assert(extractVisual("```swift\nlet x = \"<svg>\"\n```").visual == nil, "visual: other languages stay code")
    let bare = extractVisual("Logo: <svg width=\"4\"></svg> ok")
    assert(bare.visual?.kind == .svg && bare.text == "Logo:  ok", "visual: bare svg")
    assert(Visual(kind: .svg, code: "<svg viewBox=\"0 0 1 1\"/>").file.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\""), "visual: svg file gets namespace")
    let lottie = extractVisual("Spinner:\n```json\n{\"v\":\"5.7.4\",\"fr\":30,\"ip\":0,\"op\":60,\"w\":100,\"h\":100,\"layers\":[]}\n```")
    assert(lottie.visual?.kind == .lottie && lottie.visual?.ext == "json", "visual: lottie json")
    assert(extractVisual("```json\n{\"name\": \"poni\"}\n```").visual == nil, "visual: other json stays code")
    let talk = [Exchange(prompt: "hai", answer: "halo"), Exchange(prompt: "x", answer: "gagal", failed: true), Exchange(prompt: "lagi", answer: String(repeating: "a", count: 2000))]
    let tx = transcript(talk)
    assert(tx.contains("User: hai\nAssistant: halo") && !tx.contains("gagal") && tx.contains("…") && tx.hasSuffix("New message:\n"), "ai: transcript skips failures and trims long answers")
    assert(transcript([]).isEmpty, "ai: no transcript without answers")
    let sid = UUID()
    let claude = AIModel.known[0].2
    assert(claude("q", .new(sid)).contains("--session-id") && claude("q", .session(sid)).contains("--resume") && !claude("q", .none).contains("-c"), "ai: claude session flags")
    assert(AIModel.known[1].2("q", .last).contains("--resume") && !AIModel.known[1].2("q", .none).contains("--resume"), "ai: kiro resume flag")
    let saved = try! JSONDecoder().decode([AISession].self, from: JSONEncoder().encode([AISession(id: sid, cli: "Claude", chat: talk)]))
    assert(saved.first?.title == "hai" && saved.first?.chat.count == 3, "ai: sessions round-trip")
    assert(movedTab([NTab.home, .music, .focus], .home, by: 1) { $0 != .music } == [.focus, .music, .home], "tab drag steps over hidden tabs")
    assert(movedTab([NTab.home, .music], .music, by: 1) { _ in true } == [.home, .music], "tab drag stops at the end")
    assert(movedTab(["music", "git", "todo"], "todo", by: -1) { $0 != "git" } == ["todo", "git", "music"], "home drag steps over cards that are switched off")
    assert(placedTab([.home, .music, .focus], .home, at: .focus) == [.music, .focus, .home] && placedTab([.home, .music, .focus], .focus, at: .home) == [.focus, .home, .music], "tab drop in the feature list")
    assert(netCounters()["lo0"] != nil && ipv4("lo0") == "127.0.0.1", "jaringan: lo0 counters and address")
    // Kemenag RI schedule for Kota Jakarta on 8 Nov 2026 (api.myquran.com, id 1301), to the minute ±1.
    var jkt = Calendar(identifier: .gregorian); jkt.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    let nov8 = jkt.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))!
    let pt = prayerTimes(on: nov8, lat: -6.2088, lon: 106.8456, tz: jkt.timeZone)
    let kemenag: [Prayer: (Int, Int)] = [.imsak: (3, 57), .subuh: (4, 7), .terbit: (5, 22), .dzuhur: (11, 40), .ashar: (14, 58), .maghrib: (17, 51), .isya: (19, 3)]
    for (p, (hh, mm)) in kemenag {
        let c = jkt.dateComponents([.hour, .minute], from: pt[p]!)
        assert(abs((c.hour! * 60 + c.minute!) - (hh * 60 + mm)) <= 1, "sholat: \(p.title) \(c.hour!):\(c.minute!) vs Kemenag \(hh):\(mm)")
    }
    var stale = Status(); stale.calibration = 2; stale.updated = 1000
    assert(resumed(stale, now: 1000 + 7 * 3600).calibration == 0 && resumed(stale, now: 1000 + 60).calibration == 2, "daemon: drops a calibration left hours ago, keeps a fresh one")
    let hl = [HealthDay(day: "2026-01-01", maxCapacity: 4500, designCapacity: 5000, cycles: 100), HealthDay(day: "2026-01-31", maxCapacity: 4450, designCapacity: 5000, cycles: 130)]
    let ht = healthTrend(hl)
    assert(ht?.days == 30 && abs((ht?.change ?? 0) + 1) < 0.001 && healthTrend(Array(hl.prefix(1))) == nil, "health: trend over days")
    let today = Date(), cal = Calendar.current
    let ago = { (n: Int) in dayKey(cal.date(byAdding: .day, value: -n, to: today)!) }
    assert(streak([ago(0), ago(1), ago(2), ago(4)], today: today) == 3, "habit: streak counts back from today")
    assert(streak([ago(1), ago(2)], today: today) == 2 && streak([ago(2)], today: today) == 0, "habit: today not done yet keeps yesterday's streak")
    let ls = URL(fileURLWithPath: "/bin/ls")
    assert(teamID(of: ls) == nil && !signed(ls, by: "ABCDE12345"), "update: Apple's own binary has no team and doesn't pass as a release")
    let np0 = mergeNowPlaying([:], ["title": "Video", "playing": true, "artist": "Kanal"], diff: false)
    let np1 = mergeNowPlaying(np0, ["playing": false, "artist": NSNull()], diff: true)
    assert(np1["title"] as? String == "Video" && np1["playing"] as? Bool == false && np1["artist"] == nil, "now playing: diff merges, null removes")
    assert(mergeNowPlaying(np1, ["title": "Lain"], diff: false).count == 1, "now playing: a full payload replaces")
    let at = Date(timeIntervalSince1970: 1_000_000)
    let stamp = ISO8601DateFormatter().string(from: at)
    assert(nowPlayingPosition(["elapsedTime": 10.0, "timestamp": stamp, "playing": true, "duration": 100.0], at: at + 5) == 15, "now playing: position moves while playing")
    assert(nowPlayingPosition(["elapsedTime": 10.0, "timestamp": stamp, "playing": false], at: at + 5) == 10 && nowPlayingPosition(["elapsedTime": 98.0, "timestamp": stamp, "playing": true, "duration": 100.0], at: at + 5) == 100, "now playing: paused stays, capped at duration")
    assert(youtubeID("https://www.youtube.com/watch?v=jNQXAC9IVRw&t=42s") == "jNQXAC9IVRw" && youtubeID("https://youtu.be/jNQXAC9IVRw") == "jNQXAC9IVRw", "video: watch and short links")
    assert(youtubeID("https://m.youtube.com/shorts/jNQXAC9IVRw") == "jNQXAC9IVRw" && youtubeID("https://www.youtube.com/@channel") == nil && youtubeID("https://evil.com/watch?v=jNQXAC9IVRw") == nil, "video: shorts, not a video, other site")
    print("selftest ok")
}
