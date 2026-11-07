import AppKit
import Vision

// MARK: Now Playing (Spotify / Apple Music via AppleScript; MediaRemote is closed to third parties on recent macOS)

struct Lyric: Equatable {
    let t: Double
    let line: String
}

/// Parses LRC lines like `[01:23.45] text`.
func parseLRC(_ s: String) -> [Lyric] {
    s.split(separator: "\n").compactMap { l in
        guard l.hasPrefix("["), let close = l.firstIndex(of: "]") else { return nil }
        let ts = l[l.index(after: l.startIndex)..<close].split(separator: ":")
        guard ts.count == 2, let m = Double(ts[0]), let sec = Double(ts[1]) else { return nil }
        return Lyric(t: m * 60 + sec, line: l[l.index(after: close)...].trimmingCharacters(in: .whitespaces))
    }
}

final class NowPlaying: ObservableObject {
    @Published var app: String?
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var playing = false
    @Published var duration = 0.0
    @Published var position = 0.0
    @Published var polledAt = Date()
    @Published var artwork: NSImage?
    @Published var lyrics: [Lyric] = []
    @Published var lyricsStatus = ""
    private var bundleID = "", trackKey = ""
    private var timer: Timer?
    private let q = DispatchQueue(label: "nowplaying")
    private var scripts: [String: NSAppleScript] = [:] // only touched on q

    static let players = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")]

    func start() { stop(); poll(); timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() } }
    func stop() { timer?.invalidate(); timer = nil }

    /// Position extrapolated between polls, for a smooth progress bar and lyrics.
    func now(_ date: Date) -> Double { min(duration, position + (playing ? date.timeIntervalSince(polledAt) : 0)) }

    private func run(_ src: String) -> NSAppleEventDescriptor? {
        let s = scripts[src] ?? NSAppleScript(source: src)
        scripts[src] = s
        var err: NSDictionary?
        return s?.executeAndReturnError(&err)
    }

    func poll() {
        // Only talk to a player that is already running; `tell application` would launch it.
        guard let (id, name) = Self.players.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.0).isEmpty }) else {
            if app != nil { app = nil; playing = false; artwork = nil; lyrics = []; trackKey = "" }
            return
        }
        let spotify = id == "com.spotify.client"
        let src = """
        tell application id "\(id)"
            if player state is stopped then return ""
            set d to character id 31
            set t to current track
            return (player state as text) & d & (name of t) & d & (artist of t) & d & (album of t) & d & ((duration of t) as text) & d & (player position as text)\(spotify ? " & d & (artwork url of t)" : "")
        end tell
        """
        q.async {
            let f = (self.run(src)?.stringValue ?? "").components(separatedBy: "\u{1F}")
            DispatchQueue.main.async { self.apply(id: id, name: name, f) }
        }
    }

    private func apply(id: String, name: String, _ f: [String]) {
        bundleID = id
        app = name
        guard f.count >= 6 else { playing = false; return }
        let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        playing = f[0] == "playing"
        title = f[1]; artist = f[2]; album = f[3]
        duration = num(f[4]) / (id == "com.spotify.client" ? 1000 : 1) // Spotify reports ms
        position = num(f[5])
        polledAt = Date()
        if title + artist != trackKey {
            trackKey = title + artist
            loadArtwork(f.count > 6 ? f[6] : "")
            loadLyrics()
        }
    }

    private func loadArtwork(_ url: String) {
        artwork = nil
        let key = trackKey
        let set = { (d: Data?) in DispatchQueue.main.async { if key == self.trackKey { self.artwork = d.flatMap(NSImage.init(data:)) } } }
        if let u = URL(string: url), !url.isEmpty {
            URLSession.shared.dataTask(with: u) { d, _, _ in set(d) }.resume()
        } else {
            q.async { set(self.run("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")?.data) }
        }
    }

    private func loadLyrics() {
        lyrics = []
        lyricsStatus = "Mencari lirik…"
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [.init(name: "artist_name", value: artist), .init(name: "track_name", value: title),
                        .init(name: "album_name", value: album), .init(name: "duration", value: String(Int(duration)))]
        var r = URLRequest(url: c.url!)
        r.setValue("BateraiSafer (https://github.com/lshinkuro/baterai-safer)", forHTTPHeaderField: "User-Agent")
        let key = trackKey
        URLSession.shared.dataTask(with: r) { d, _, _ in
            let synced = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["syncedLyrics"] as? String
            DispatchQueue.main.async {
                guard key == self.trackKey else { return }
                self.lyrics = parseLRC(synced ?? "")
                self.lyricsStatus = self.lyrics.isEmpty ? "Lirik tidak tersedia" : ""
            }
        }.resume()
    }

    func send(_ cmd: String) {
        let id = bundleID
        q.async {
            _ = self.run("tell application id \"\(id)\" to \(cmd)")
            DispatchQueue.main.async { self.poll() }
        }
    }
}

// MARK: Pomodoro

func dayKey(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

/// Consecutive days with focus time, ending today (or yesterday, so an unfinished today doesn't break it).
func focusStreak(_ log: [String: Int], today: Date) -> Int {
    let cal = Calendar.current
    var d = today, n = 0
    if (log[dayKey(d)] ?? 0) == 0 { d = cal.date(byAdding: .day, value: -1, to: d)! }
    while (log[dayKey(d)] ?? 0) > 0 { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
    return n
}

final class Focus: ObservableObject {
    static let focusLen = 25 * 60.0, breakLen = 5 * 60.0
    @Published var onBreak = false
    @Published var endAt: Date? // set while running
    @Published var left = Focus.focusLen
    @Published var log = load(Paths.focus, [String: Int]()) // day → focus minutes
    private var timer: Timer?

    var running: Bool { endAt != nil }
    var total: Double { onBreak ? Self.breakLen : Self.focusLen }
    var remaining: Double { endAt.map { max(0, $0.timeIntervalSinceNow) } ?? left }
    var clock: String { let r = Int(remaining.rounded(.up)); return String(format: "%02d:%02d", r / 60, r % 60) }
    var streak: Int { focusStreak(log, today: Date()) }
    var today: Int { log[dayKey(Date())] ?? 0 }
    var last7: [(day: String, minutes: Int)] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEE"
        return (0..<7).reversed().map { i in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            return (f.string(from: d), log[dayKey(d)] ?? 0)
        }
    }

    func toggle() {
        if let e = endAt {
            left = max(0, e.timeIntervalSinceNow)
            endAt = nil
            timer?.invalidate()
        } else {
            endAt = Date().addingTimeInterval(left)
            timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
                if self.remaining <= 0 { self.next(completed: true) }
            }
        }
    }

    func reset() { timer?.invalidate(); endAt = nil; left = total }

    /// Switches focus ⇄ break; only a completed focus session counts toward the log.
    func next(completed: Bool = false) {
        timer?.invalidate()
        endAt = nil
        if completed {
            if !onBreak { log[dayKey(Date()), default: 0] += Int(Self.focusLen / 60); save(log, Paths.focus) }
            NSSound(named: "Glass")?.play()
        }
        onBreak.toggle()
        left = total
    }
}

// MARK: Clipboard history

struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String?
    var image: String? // file name in Paths.clipDir
    var ocr: String?
    var pinned = false
}

/// Synchronous OCR; only called by the `ocr` subcommand.
func ocrText(_ data: Data) -> String {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.automaticallyDetectsLanguage = true
    try? VNImageRequestHandler(data: data).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

/// Vision keeps 20–60 MB of model weights resident after first use, so OCR runs in a
/// short-lived child process (this binary's `ocr` subcommand) and the memory goes away with it.
func recognizeText(file: String, _ done: @escaping (String) -> Void) {
    runAsync(Bundle.main.executablePath ?? CommandLine.arguments[0], ["ocr", file]) { _, out, _ in
        done(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

final class ClipboardModel: ObservableObject {
    @Published var items = load(Paths.clips, [Clip]())
    private var count = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var thumbs: [String: NSImage] = [:]
    static let limit = 50 // unpinned items kept

    func start() { stop(); timer = .scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() } }
    func stop() { timer?.invalidate(); timer = nil }

    func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != count else { return }
        count = pb.changeCount
        // Password managers mark secrets with these types (nspasteboard.org); never store them.
        let secret = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        if pb.types?.contains(where: { secret.contains($0.rawValue) }) == true { return }
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add(Clip(text: s))
        } else if let img = NSImage(pasteboard: pb), let tiff = img.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let name = UUID().uuidString + ".png"
            try? FileManager.default.createDirectory(atPath: Paths.clipDir, withIntermediateDirectories: true)
            guard (try? png.write(to: URL(fileURLWithPath: Paths.clipDir + "/" + name))) != nil else { return }
            let c = Clip(image: name)
            add(c)
            recognizeText(file: Paths.clipDir + "/" + name) { text in
                if let i = self.items.firstIndex(where: { $0.id == c.id }) { self.items[i].ocr = text; self.persist() }
            }
        }
    }

    func add(_ new: Clip) {
        var c = new
        if let t = c.text, let i = items.firstIndex(where: { $0.text == t }) { c = items.remove(at: i) }
        items.insert(c, at: 0)
        var unpinned = 0
        items.removeAll { item in
            guard !item.pinned else { return false }
            unpinned += 1
            if unpinned > Self.limit { removeFile(item); return true }
            return false
        }
        persist()
    }

    func copy(_ c: Clip) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let t = c.text { pb.setString(t, forType: .string) } else if let img = thumb(c) { pb.writeObjects([img]) }
        count = pb.changeCount
        add(c)
    }

    func togglePin(_ c: Clip) {
        if let i = items.firstIndex(of: c) { items[i].pinned.toggle(); persist() }
    }

    func delete(_ c: Clip) { removeFile(c); items.removeAll { $0.id == c.id }; persist() }

    func clear() { items.filter { !$0.pinned }.forEach(removeFile); items.removeAll { !$0.pinned }; persist() }

    func thumb(_ c: Clip) -> NSImage? {
        guard let name = c.image else { return nil }
        if let t = thumbs[name] { return t }
        let img = NSImage(contentsOfFile: Paths.clipDir + "/" + name)
        thumbs[name] = img
        return img
    }

    private func removeFile(_ c: Clip) {
        if let name = c.image { try? FileManager.default.removeItem(atPath: Paths.clipDir + "/" + name); thumbs[name] = nil }
    }

    private func persist() {
        try? FileManager.default.createDirectory(atPath: Paths.user, withIntermediateDirectories: true)
        save(items, Paths.clips)
    }
}

// MARK: File shelf (references only; files stay where they are)

final class Shelf: ObservableObject {
    @Published var files: [URL] = []

    func add(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { if !self.files.contains(url) { self.files.append(url) } }
            }
        }
        return true
    }

    func airDrop(_ urls: [URL]) { NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls) }
}
