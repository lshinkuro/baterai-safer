import SwiftUI

// Experimental: how many Claude Code tokens we use, read from its local session logs.

struct UsageReport: Equatable {
    var days: [String: Int] = [:]      // "yyyy-MM-dd" → tokens
    var models: [String: Int] = [:]
    var today = (input: 0, output: 0, cache: 0)
    var ours = 0                       // tokens from this app's own AI chat
    var total: Int { days.values.reduce(0, +) }

    static func == (a: UsageReport, b: UsageReport) -> Bool {
        a.days == b.days && a.models == b.models && a.ours == b.ours
    }
}

/// Folds Claude Code session lines (JSONL) into `r`. Claude logs each message once per content
/// block, so lines are de-duplicated on message id + request id.
func addClaudeUsage(_ text: Substring, since: Date, today: String, ours: Bool, into r: inout UsageReport, seen: inout Set<String>) {
    for line in text.split(separator: "\n") where line.contains("\"usage\"") {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let m = o["message"] as? [String: Any], let u = m["usage"] as? [String: Any],
              let ts = (o["timestamp"] as? String).flatMap(isoDate), ts >= since else { continue }
        let key = "\(m["id"] ?? "")|\(o["requestId"] ?? "")"
        guard seen.insert(key).inserted else { continue }
        let n = { (k: String) in u[k] as? Int ?? 0 }
        let input = n("input_tokens"), output = n("output_tokens"), cache = n("cache_creation_input_tokens") + n("cache_read_input_tokens")
        let sum = input + output + cache, day = dayKey(ts)
        r.days[day, default: 0] += sum
        r.models[m["model"] as? String ?? "?", default: 0] += sum
        if ours { r.ours += sum }
        if day == today { r.today.input += input; r.today.output += output; r.today.cache += cache }
    }
}

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()
func isoDate(_ s: String) -> Date? { isoFormatter.date(from: s) }

func tokens(_ n: Int) -> String {
    n >= 1_000_000_000 ? String(format: "%.1fB", Double(n) / 1e9)
        : n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6)
        : n >= 1000 ? String(format: "%.1fK", Double(n) / 1e3) : "\(n)"
}

final class UsageModel: ObservableObject {
    static let shared = UsageModel()
    @Published var report = UsageReport()
    @Published var loading = false
    static let dir = NSHomeDirectory() + "/.claude/projects"
    // Claude Code names a project folder after its cwd with every non-alphanumeric replaced by "-".
    static let ourFolder = String(AIModel.cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })

    private var last = Date.distantPast

    /// Reads ~200 MB of logs, so page opens reuse a result younger than a minute.
    func refresh(force: Bool = false, done: (() -> Void)? = nil) {
        guard !loading, force || Date().timeIntervalSince(last) > 60 else { return }
        loading = true
        last = Date()
        DispatchQueue.global(qos: .utility).async {
            let since = Calendar.current.startOfDay(for: Date().addingTimeInterval(-6 * 86400)), today = dayKey(Date())
            var r = UsageReport(), seen = Set<String>()
            let fm = FileManager.default
            for folder in (try? fm.contentsOfDirectory(atPath: Self.dir)) ?? [] {
                let path = Self.dir + "/" + folder
                for f in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where f.hasSuffix(".jsonl") {
                    let file = path + "/" + f
                    // Logs total hundreds of MB; skip sessions untouched this week.
                    guard let mod = (try? fm.attributesOfItem(atPath: file))?[.modificationDate] as? Date, mod >= since,
                          let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                    addClaudeUsage(text[...], since: since, today: today, ours: folder == Self.ourFolder, into: &r, seen: &seen)
                }
            }
            DispatchQueue.main.async { self.report = r; self.loading = false; done?() }
        }
    }
}

struct UsagePage: View {
    @ObservedObject var u: UsageModel

    var body: some View {
        let r = u.report
        let days = (0..<7).reversed().map { i -> (String, Int) in
            let d = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            return (d.formatted(.dateTime.weekday(.abbreviated).locale(appLocale)), r.days[dayKey(d)] ?? 0)
        }
        let top = r.models.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(3)
        HStack(spacing: 10) {
            NCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HARI INI").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                    Text(tokens(r.today.input + r.today.output + r.today.cache)).font(.system(size: 30, weight: .semibold))
                    Text("token Claude Code").font(.system(size: 11)).foregroundStyle(.gray)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Chip(text: "in \(tokens(r.today.input))", color: .gray)
                        Chip(text: "out \(tokens(r.today.output))", color: .gray)
                    }
                    Chip(text: "cache \(tokens(r.today.cache))", color: .gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: 170)

            NCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("7 HARI · \(tokens(r.total))").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                        Spacer()
                        if u.loading { ProgressView().controlSize(.mini) }
                        Button { u.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(.gray).tip("Muat ulang")
                    }
                    let peak = max(days.map(\.1).max() ?? 0, 1)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(days, id: \.0) { d in
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 4).fill(Palette.accent.gradient)
                                    .frame(height: max(2, 70 * CGFloat(d.1) / CGFloat(peak)))
                                Text(d.0).font(.system(size: 9)).foregroundStyle(.gray)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 86, alignment: .bottom)
                    ForEach(top, id: \.key) { m in
                        HStack {
                            Text(m.key).lineLimit(1)
                            Spacer()
                            Text(tokens(m.value)).monospacedDigit().foregroundStyle(.gray)
                        }
                        .font(.system(size: 11))
                    }
                    Text("Dari chat Poni: \(tokens(r.ours))").font(.system(size: 10)).foregroundStyle(Palette.accent)
                }
            }

        }
        .onAppear { u.refresh() }
    }
}
