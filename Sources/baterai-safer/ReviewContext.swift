import AppKit

/// Paths after `b/` in `diff --git a/x b/y` lines.
func changedFiles(_ diff: String) -> [String] {
    diff.split(separator: "\n").compactMap { l in
        guard l.hasPrefix("diff --git "), let r = l.range(of: " b/", options: .backwards) else { return nil }
        return String(l[r.upperBound...])
    }
}

// MARK: Team guides (per PR repo, chosen by the user)

enum Guides {
    static func files(_ repo: String) -> [String] {
        (UserDefaults.standard.dictionary(forKey: "guides") as? [String: [String]])?[repo] ?? []
    }

    static func set(_ repo: String, _ files: [String]) {
        var all = UserDefaults.standard.dictionary(forKey: "guides") as? [String: [String]] ?? [:]
        all[repo] = files
        UserDefaults.standard.set(all, forKey: "guides")
    }

    /// File contents for the prompt, capped so guides can't crowd out the diff.
    static func text(_ repo: String, limit: Int = 40_000) -> String {
        var out = "", left = limit
        for path in files(repo) where left > 0 {
            guard let s = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let part = String(s.prefix(min(15_000, left)))
            out += "=== \((path as NSString).lastPathComponent)\(part.count < s.count ? " (dipotong)" : "") ===\n\(part)\n\n"
            left -= part.count
        }
        return out
    }

    static func add(_ repo: String, near folder: String?) {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.allowedContentTypes = [.plainText, .json, .xml, .init(filenameExtension: "md")!, .init(filenameExtension: "mdc")!]
        p.message = "Pilih panduan tim / aturan Sonar untuk review \(repo)"
        p.prompt = "Pakai untuk review"
        if let folder { p.directoryURL = URL(fileURLWithPath: folder) }
        guard p.runModal() == .OK else { return }
        set(repo, Array(Set(files(repo) + p.urls.map(\.path))).sorted())
    }
}

// MARK: SonarQube Web API (user token, Basic auth "token:")

enum Sonar {
    static var base: String? { UserDefaults.standard.string(forKey: "sonarURL") }
    private static var cachedToken: String?
    static var token: String? {
        if cachedToken == nil, let base { cachedToken = Keychain.get("sonar " + base) }
        return cachedToken
    }
    static var connected: Bool { token != nil }

    static func call(_ path: String, base: String? = Sonar.base, token: String? = Sonar.token, done: @escaping (Int, Data) -> Void) {
        guard let base, let token, let url = URL(string: base + path) else { done(0, Data()); return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Basic " + Data((token + ":").utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: r) { d, resp, _ in
            DispatchQueue.main.async { done((resp as? HTTPURLResponse)?.statusCode ?? 0, d ?? Data()) }
        }.resume()
    }

    static func connect(base raw: String, token: String, done: @escaping (Bool, String) -> Void) {
        let base = raw.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        call("/api/authentication/validate", base: base, token: token) { code, d in
            let valid = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["valid"] as? Bool ?? false
            guard code == 200, valid else { done(false, code == 0 ? "Tidak bisa terhubung ke SonarQube (VPN?)" : "Token SonarQube tidak valid"); return }
            UserDefaults.standard.set(base, forKey: "sonarURL")
            Keychain.set("sonar " + base, token)
            cachedToken = token
            done(true, "Terhubung ke SonarQube")
        }
    }

    static func disconnect() {
        if let base { Keychain.set("sonar " + base, nil) }
        cachedToken = nil
        UserDefaults.standard.removeObject(forKey: "sonarURL")
    }

    /// Explicit mapping first, else `sonar.projectKey` from a watched repo named like the PR's repo.
    static func projectKey(_ pr: PR, repos: [String]) -> String? {
        if let k = (UserDefaults.standard.dictionary(forKey: "sonarKeys") as? [String: String])?[pr.repo] { return k }
        let slug = (pr.repo.components(separatedBy: "/").last ?? "").lowercased()
        guard let dir = repos.first(where: { ($0 as NSString).lastPathComponent.lowercased() == slug }) else { return nil }
        let fm = FileManager.default
        let candidates = [dir] + ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).map { dir + "/" + $0 }
        for c in candidates {
            guard let s = try? String(contentsOfFile: c + "/sonar-project.properties", encoding: .utf8) else { continue }
            if let line = s.split(separator: "\n").first(where: { $0.hasPrefix("sonar.projectKey") }),
               let v = line.split(separator: "=", maxSplits: 1).last { return v.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    static func setProjectKey(_ pr: PR, _ key: String?) {
        var all = UserDefaults.standard.dictionary(forKey: "sonarKeys") as? [String: String] ?? [:]
        all[pr.repo] = key
        UserDefaults.standard.set(all, forKey: "sonarKeys")
    }

    /// Open issues for the PR (PR analysis → branch → main limited to changed files) plus
    /// BLOCKER/CRITICAL rules active for the diff's languages. Reports (prompt text, summary).
    static func context(key: String, pr: PR, head: String, files: [String], done: @escaping (String, String) -> Void) {
        let q = "/api/issues/search?componentKeys=\(enc(key))&resolved=false&ps=100"
        var issues: [String] = [], source = ""
        let tries: [(String, String, Bool)] = [(q + "&pullRequest=\(pr.number)", "analisis PR", false),
                                               (q + "&branch=\(enc(head))", "branch \(head)", true),
                                               (q.replacingOccurrences(of: "ps=100", with: "ps=500"), "branch utama (file yang berubah)", true)]
        func attempt(_ i: Int) {
            guard i < tries.count else { rules(); return }
            call(tries[i].0) { code, d in
                let found = code == 200 ? sonarIssues(d, files: tries[i].2 ? files : nil) : []
                if found.isEmpty { attempt(i + 1) } else { issues = found; source = tries[i].1; rules() }
            }
        }
        func rules() {
            let langs = Set(files.compactMap { sonarLanguage(($0 as NSString).pathExtension) })
            call("/api/qualityprofiles/search?project=\(enc(key))") { _, d in
                let profiles = (((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["profiles"] as? [[String: Any]] ?? [])
                    .filter { langs.contains($0["language"] as? String ?? "") }
                var lines: [String] = []
                let g = DispatchGroup()
                for p in profiles {
                    guard let k = p["key"] as? String else { continue }
                    g.enter()
                    call("/api/rules/search?qprofile=\(enc(k))&activation=true&severities=BLOCKER,CRITICAL&ps=150&f=name,lang") { _, d in
                        let rules = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["rules"] as? [[String: Any]] ?? []
                        lines += rules.compactMap { r in (r["key"] as? String).map { "- \($0) — \(r["name"] as? String ?? "")" } }
                        g.leave()
                    }
                }
                g.notify(queue: .main) {
                    var text = ""
                    if !issues.isEmpty { text += "Temuan SonarQube (\(source)):\n" + issues.joined(separator: "\n") + "\n\n" }
                    if !lines.isEmpty { text += "Aturan Sonar BLOCKER/CRITICAL yang aktif:\n" + lines.prefix(150).joined(separator: "\n") + "\n" }
                    done(text, issues.isEmpty ? "Sonar: tidak ada temuan, \(lines.count) aturan" : "Sonar: \(issues.count) temuan (\(source))")
                }
            }
        }
        attempt(0)
    }

    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s }
}

func sonarLanguage(_ ext: String) -> String? {
    ["swift": "swift", "ts": "ts", "tsx": "ts", "js": "js", "jsx": "js", "kt": "kotlin", "java": "java",
     "m": "objc", "mm": "objc", "h": "objc", "py": "py", "go": "go", "css": "css", "scss": "css", "html": "web"][ext.lowercased()]
}

/// Formats `/api/issues/search` results; `files` limits to issues in those paths.
func sonarIssues(_ d: Data, files: [String]?) -> [String] {
    let issues = ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any])?["issues"] as? [[String: Any]] ?? []
    return issues.compactMap { i in
        let path = (i["component"] as? String ?? "").split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
        if let files, !files.contains(where: { path.hasSuffix($0) || $0.hasSuffix(path) }) { return nil }
        let line = (i["line"] as? Int).map { ":\($0)" } ?? ""
        return "- [\(i["severity"] as? String ?? "?")] \(i["rule"] as? String ?? "") \(path)\(line) — \(i["message"] as? String ?? "")"
    }
}

/// NSAlert with a text field; nil when cancelled.
func ask(_ title: String, _ info: String, _ value: String) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = info
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    f.stringValue = value
    a.accessoryView = f
    a.addButton(withTitle: "Simpan")
    a.addButton(withTitle: "Batal")
    a.window.initialFirstResponder = f
    return a.runModal() == .alertFirstButtonReturn ? f.stringValue.trimmingCharacters(in: .whitespaces) : nil
}
