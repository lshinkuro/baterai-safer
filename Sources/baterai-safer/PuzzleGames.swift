import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// Lainnya → Gabut: Hangman (words from Apple Intelligence) and Sudoku. Both keep their game when the notch closes.

enum AppleAI {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// One word from the on-device model; nil when it's off, refuses, or takes too long. Often wrong, so callers check it.
    static func word(about topic: String, avoiding used: [String]) async -> String? {
        #if canImport(FoundationModels)
        guard available, #available(macOS 26.0, *) else { return nil }
        let avoid = used.isEmpty ? "" : " Do not use: \(used.joined(separator: ", "))."
        let prompt = "Reply with exactly one common English noun related to \(topic). One word, 4 to 10 letters, no explanation.\(avoid)"
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                let text = try? await LanguageModelSession().respond(to: prompt, options: GenerationOptions(temperature: 1.2)).content
                return text?.split(whereSeparator: \.isNewline).first.map { $0.filter(\.isLetter).uppercased() }
            }
            group.addTask { try? await Task.sleep(nanoseconds: 10_000_000_000); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #else
        return nil
        #endif
    }
}

func isEnglishWord(_ w: String) -> Bool {
    w.count >= 2 && NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
}

// MARK: Hangman

struct Hangman {
    static let lives = 6
    let word: String
    var guessed: Set<Character> = []

    var misses: Int { guessed.filter { !word.contains($0) }.count }
    var won: Bool { word.allSatisfy(guessed.contains) }
    var lost: Bool { misses >= Self.lives }
    mutating func guess(_ c: Character) { if !won && !lost { guessed.insert(c) } }
}

/// A word the game can use: plain letters, a sensible length, not played lately.
func hangmanWordIsUsable(_ w: String, recent: [String], isWord: (String) -> Bool) -> Bool {
    (4...10).contains(w.count) && w.allSatisfy { $0.isASCII && $0.isLetter } && !recent.contains(w) && isWord(w)
}

final class HangmanGame: ObservableObject {
    static let shared = HangmanGame()
    // The name is the clue shown to the player; the words are the fallback when Apple Intelligence can't help.
    static let themes: [(name: String, english: String, words: [String])] = [
        ("Hewan", "animals", ["ELEPHANT", "GIRAFFE", "DOLPHIN", "PENGUIN", "TIGER"]),
        ("Makanan", "food", ["NOODLE", "BISCUIT", "PANCAKE", "TOMATO", "CHEESE"]),
        ("Pekerjaan", "jobs", ["TEACHER", "DOCTOR", "FARMER", "PILOT", "BAKER"]),
        ("Alam", "nature", ["MOUNTAIN", "RIVER", "FOREST", "VOLCANO", "ISLAND"]),
        ("Olahraga", "sports", ["TENNIS", "HOCKEY", "BOXING", "SWIMMING", "ARCHERY"]),
        ("Rumah", "things in a house", ["WINDOW", "PILLOW", "MIRROR", "KETTLE", "CARPET"]),
        ("Kendaraan", "vehicles", ["BICYCLE", "TRAIN", "SUBWAY", "ROCKET", "TRUCK"]),
        ("Alat musik", "musical instruments", ["GUITAR", "PIANO", "VIOLIN", "TRUMPET", "FLUTE"]),
    ]

    @Published var game: Hangman?
    @Published var theme = "Hewan"
    @Published var fromAI = false
    @Published private(set) var loading = false
    @Published private(set) var tally = (win: 0, lose: 0)
    private var recent: [String] = []
    private var round = 0 // a word that arrives for an abandoned round is dropped

    func newWord() {
        round += 1
        let id = round, t = Self.themes.randomElement()!
        theme = t.name
        game = nil
        loading = true
        Task { @MainActor in
            var word: String?
            for _ in 0..<2 where word == nil {
                if let w = await AppleAI.word(about: t.english, avoiding: recent), hangmanWordIsUsable(w, recent: recent, isWord: isEnglishWord) { word = w }
            }
            guard id == round else { return }
            fromAI = word != nil
            let picked = word ?? (t.words.filter { !recent.contains($0) }.randomElement() ?? t.words[0])
            recent = Array((recent + [picked]).suffix(30))
            game = Hangman(word: picked)
            loading = false
        }
    }

    func guess(_ c: Character) {
        guard var g = game, !g.won, !g.lost else { return }
        g.guess(c)
        game = g
        if g.won { tally.win += 1 } else if g.lost { tally.lose += 1 }
    }
}

struct HangmanView: View {
    @ObservedObject var g = HangmanGame.shared
    static let rows = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    var body: some View {
        HStack(spacing: 16) {
            figure.frame(width: 104, height: 150)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Chip(text: g.theme, color: Palette.accent)
                    Text(tr(status)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("Menang \(g.tally.win) · Kalah \(g.tally.lose)").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit().lineLimit(1)
                }
                word.frame(height: 30)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 3), count: 13), alignment: .leading, spacing: 3) {
                    ForEach(Self.rows, id: \.self) { key($0) }
                }
                HStack(spacing: 8) {
                    NButton(icon: "arrow.clockwise", title: "Kata baru", tint: Palette.accent, prominent: over) { g.newWord() }
                    Text(tr(g.loading ? "Meminta kata ke Apple Intelligence…" : g.fromAI ? "Kata bahasa Inggris dari Apple Intelligence" : "Kata bahasa Inggris bawaan, Apple Intelligence tidak tersedia"))
                        .font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .onAppear { if g.game == nil && !g.loading { g.newWord() } }
    }

    var over: Bool { g.game.map { $0.won || $0.lost } ?? false }

    var status: String {
        guard let game = g.game else { return "Memilih kata…" }
        if game.won { return "Kamu menang!" }
        if game.lost { return "Kamu kalah" }
        return String(format: tr("Sisa %@ nyawa"), "\(Hangman.lives - game.misses)")
    }

    var figure: some View {
        let misses = g.game?.misses ?? 0
        return Canvas { ctx, size in
            let w = size.width, h = size.height
            func line(_ points: [CGPoint], _ color: Color) {
                var p = Path()
                p.addLines(points)
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            let frame = Color.white.opacity(0.3), body = misses >= Hangman.lives ? Palette.red : Color.white
            line([CGPoint(x: 8, y: h - 3), CGPoint(x: w * 0.6, y: h - 3)], frame)
            line([CGPoint(x: 24, y: h - 3), CGPoint(x: 24, y: 4), CGPoint(x: w * 0.66, y: 4), CGPoint(x: w * 0.66, y: 24)], frame)
            let x = w * 0.66
            if misses > 0 { ctx.stroke(Path(ellipseIn: CGRect(x: x - 13, y: 24, width: 26, height: 26)), with: .color(body), lineWidth: 3) }
            if misses > 1 { line([CGPoint(x: x, y: 50), CGPoint(x: x, y: 96)], body) }
            if misses > 2 { line([CGPoint(x: x, y: 62), CGPoint(x: x - 20, y: 82)], body) }
            if misses > 3 { line([CGPoint(x: x, y: 62), CGPoint(x: x + 20, y: 82)], body) }
            if misses > 4 { line([CGPoint(x: x, y: 96), CGPoint(x: x - 18, y: 128)], body) }
            if misses > 5 { line([CGPoint(x: x, y: 96), CGPoint(x: x + 18, y: 128)], body) }
        }
        .accessibilityElement()
        .accessibilityLabel(String(format: tr("Salah %@ dari %@"), "\(misses)", "\(Hangman.lives)"))
    }

    @ViewBuilder var word: some View {
        if let game = g.game {
            HStack(spacing: 5) {
                ForEach(Array(game.word.enumerated()), id: \.offset) { _, c in
                    let shown = game.guessed.contains(c)
                    VStack(spacing: 2) {
                        Text(shown || game.lost ? String(c) : " ").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(shown ? Color.white : Palette.red)
                        Rectangle().fill(.white.opacity(0.35)).frame(height: 2)
                    }
                    .frame(width: 22)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(game.word.map { game.guessed.contains($0) || game.lost ? String($0) : "–" }.joined(separator: " "))
        } else {
            ProgressView().controlSize(.small)
        }
    }

    func key(_ c: Character) -> some View {
        let used = g.game?.guessed.contains(c) ?? false, hit = used && (g.game?.word.contains(c) ?? false)
        return Button { g.guess(c) } label: {
            Text(String(c)).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hit ? Palette.onAccent : used ? .white.opacity(0.25) : .white)
                .frame(width: 26, height: 26)
                .background(hit ? Palette.accent : Color.white.opacity(used ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain) // not .disabled: it would fade the letters already found
    }
}

// MARK: Sudoku

/// Board index 0 is the top-left cell, row by row; 0 is an empty cell.
struct Sudoku {
    static let blanks = 45
    let solution: [Int]
    let givens: [Bool]
    var cells: [Int]

    var solved: Bool { cells == solution }

    static func options(_ b: [Int], _ i: Int) -> [Int] {
        var used = Set<Int>()
        for k in 0..<9 {
            used.insert(b[i / 9 * 9 + k])
            used.insert(b[i % 9 + k * 9])
            used.insert(b[i / 27 * 27 + (i % 9) / 3 * 3 + k % 3 + k / 3 * 9])
        }
        return (1...9).filter { !used.contains($0) }
    }

    /// Fills `b`, always trying the emptiest choice first, counting solutions up to `limit`; `b` holds a solution only when the limit stopped the search.
    static func solve(_ b: inout [Int], limit: Int, found: inout Int, shuffled: Bool = false) -> Bool {
        var best: (i: Int, values: [Int])?
        for i in 0..<81 where b[i] == 0 {
            let values = options(b, i)
            if best == nil || values.count < best!.values.count { best = (i, values) }
            if values.count <= 1 { break }
        }
        guard let best else { found += 1; return found >= limit }
        for v in shuffled ? best.values.shuffled() : best.values {
            b[best.i] = v
            if solve(&b, limit: limit, found: &found, shuffled: shuffled) { return true }
        }
        b[best.i] = 0
        return false
    }

    /// A random puzzle with exactly one solution.
    static func generate() -> Sudoku {
        var full = [Int](repeating: 0, count: 81), n = 0
        _ = solve(&full, limit: 1, found: &n, shuffled: true)
        var puzzle = full, removed = 0
        for i in (0..<81).shuffled() where removed < blanks {
            let keep = puzzle[i]
            puzzle[i] = 0
            var copy = puzzle, count = 0
            _ = solve(&copy, limit: 2, found: &count)
            if count == 1 { removed += 1 } else { puzzle[i] = keep }
        }
        return Sudoku(solution: full, givens: puzzle.map { $0 != 0 }, cells: puzzle)
    }

    func conflict(_ i: Int) -> Bool {
        guard cells[i] != 0 else { return false }
        var b = cells
        let v = b[i]
        b[i] = 0
        return !Self.options(b, i).contains(v)
    }
}

final class SudokuGame: ObservableObject {
    static let shared = SudokuGame()
    @Published var s = Sudoku.generate()
    @Published var selected: Int?

    func set(_ v: Int) {
        guard let i = selected, !s.givens[i], !s.solved else { return }
        s.cells[i] = v
    }

    func newPuzzle() { s = Sudoku.generate(); selected = nil }
}

struct SudokuView: View {
    @ObservedObject var g = SudokuGame.shared
    let cell: CGFloat = 22

    var body: some View {
        HStack(spacing: 18) {
            board
            VStack(alignment: .leading, spacing: 8) {
                Text(tr(g.s.solved ? "Selesai! 🎉" : g.selected == nil ? "Pilih kotak kosong" : "Pilih angka")).font(.system(size: 15, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 5), alignment: .leading, spacing: 4) {
                    ForEach(1...9, id: \.self) { digit($0) }
                    Button { g.set(0) } label: {
                        Image(systemName: "delete.left").font(.system(size: 13, weight: .semibold)).frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous)).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).tip("Hapus angka")
                }
                NButton(icon: "arrow.clockwise", title: "Sudoku baru", tint: Palette.accent, prominent: g.s.solved) { withAnimation(Motion.ease) { g.newPuzzle() } }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    var board: some View {
        VStack(spacing: 0) {
            ForEach(0..<9, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { c in square(r * 9 + c) }
                }
            }
        }
        .overlay {
            // Heavier lines around the 3×3 boxes.
            Canvas { ctx, size in
                var p = Path()
                for k in 1...2 {
                    let x = size.width * CGFloat(k) / 3, y = size.height * CGFloat(k) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                }
                ctx.stroke(p, with: .color(.white.opacity(0.4)), lineWidth: 1.5)
            }
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1.5))
    }

    func square(_ i: Int) -> some View {
        let v = g.s.cells[i], on = g.selected == i, picked = g.selected.map { g.s.cells[$0] } ?? 0
        let fill = on ? Palette.accent.opacity(0.5) : v != 0 && v == picked ? Palette.accent.opacity(0.2) : Color.white.opacity(0.05)
        return Button { g.selected = i } label: {
            Text(v == 0 ? "" : "\(v)").font(.system(size: 13, weight: g.s.givens[i] ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(g.s.conflict(i) ? Palette.red : g.s.givens[i] ? Color.white : Palette.accent)
                .frame(width: cell, height: cell)
                .background(fill)
                .overlay(Rectangle().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: tr("Baris %@ kolom %@"), "\(i / 9 + 1)", "\(i % 9 + 1)"))
        .accessibilityValue(v == 0 ? tr("Kosong") : "\(v)")
    }

    func digit(_ n: Int) -> some View {
        let full = g.s.cells.filter { $0 == n }.count >= 9
        return Button { g.set(n) } label: {
            Text("\(n)").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                .foregroundStyle(full ? .white.opacity(0.25) : .white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
