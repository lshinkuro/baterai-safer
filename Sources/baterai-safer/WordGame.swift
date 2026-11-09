import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// Lainnya → Gabut → Rangkai Kata: cross words on a small board against Apple Intelligence. English only,
// the one language both the on-device model and the system dictionary share here. The board needs more
// room than the island has, so it plays in a window.

struct WordBoard {
    struct Cell: Hashable { var x, y: Int }
    struct Tile: Equatable { var cell: Cell; var letter: Character }
    enum Result: Equatable { case ok(words: [String], score: Int), bad(String) }

    static let size = 11, center = Cell(x: 5, y: 5), rackSize = 8, fullRackBonus = 20
    static let doubleWord: Set<Cell> = [Cell(x: 1, y: 1), Cell(x: 9, y: 1), Cell(x: 1, y: 9), Cell(x: 9, y: 9), Cell(x: 5, y: 1), Cell(x: 5, y: 9), Cell(x: 1, y: 5), Cell(x: 9, y: 5)]
    static let doubleLetter: Set<Cell> = [Cell(x: 3, y: 3), Cell(x: 7, y: 3), Cell(x: 3, y: 7), Cell(x: 7, y: 7), Cell(x: 3, y: 0), Cell(x: 7, y: 0), Cell(x: 3, y: 10), Cell(x: 7, y: 10), Cell(x: 0, y: 3), Cell(x: 0, y: 7), Cell(x: 10, y: 3), Cell(x: 10, y: 7)]
    static let bag = Array(repeatElement("E", count: 12).joined() + "AAAAAAAAIIIIIIIOOOOOOONNNNNNRRRRRRSSSSSSTTTTTTLLLLUUUUDDDDGGGHHHCCCMMMPPPBBYYFFWWVVKJXQZ")

    static func value(_ c: Character) -> Int {
        for (points, letters) in [(1, "EAIONRST"), (2, "LUDGH"), (3, "CMPBY"), (4, "FWVK"), (5, "JX"), (6, "QZ")] where letters.contains(c) { return points }
        return 0
    }

    var grid: [Cell: Character] = [:]

    private func inside(_ c: Cell) -> Bool { (0..<Self.size).contains(c.x) && (0..<Self.size).contains(c.y) }

    /// The unbroken run of letters through `c` along one direction.
    private func run(_ c: Cell, _ dx: Int, _ dy: Int, _ all: [Cell: Character]) -> [Cell] {
        var a = c
        while all[Cell(x: a.x - dx, y: a.y - dy)] != nil { a = Cell(x: a.x - dx, y: a.y - dy) }
        var out: [Cell] = []
        while all[a] != nil { out.append(a); a = Cell(x: a.x + dx, y: a.y + dy) }
        return out
    }

    func evaluate(_ tiles: [Tile], isWord: (String) -> Bool) -> Result {
        guard let first = tiles.first else { return .bad("Letakkan huruf dulu") }
        let placed = Dictionary(tiles.map { ($0.cell, $0.letter) }, uniquingKeysWith: { a, _ in a })
        guard placed.count == tiles.count, placed.keys.allSatisfy({ inside($0) && grid[$0] == nil }) else { return .bad("Kotak itu sudah terisi") }
        let xs = Set(placed.keys.map(\.x)), ys = Set(placed.keys.map(\.y))
        guard xs.count == 1 || ys.count == 1 else { return .bad("Huruf harus dalam satu garis") }
        let all = grid.merging(placed) { a, _ in a }
        let across = ys.count == 1 && (xs.count > 1 || run(first.cell, 1, 0, all).count > 1)
        let (dx, dy) = across ? (1, 0) : (0, 1)
        let main = run(first.cell, dx, dy, all)
        guard placed.keys.allSatisfy(main.contains) else { return .bad("Huruf harus menyambung") }
        guard main.count >= 2 else { return .bad("Kata minimal dua huruf") }

        let crosses = tiles.map { run($0.cell, dy, dx, all) }.filter { $0.count > 1 }
        if grid.isEmpty {
            guard placed[Self.center] != nil else { return .bad("Kata pertama harus melewati tengah") }
        } else {
            guard main.count > tiles.count || !crosses.isEmpty else { return .bad("Kata harus menyambung ke huruf di papan") }
        }

        var words: [String] = [], total = 0
        for cells in [main] + crosses {
            let word = String(cells.map { all[$0]! })
            guard isWord(word.lowercased()) else { return .bad(String(format: tr("%@ tidak ada di kamus"), word)) }
            words.append(word)
            var points = 0, factor = 1
            for c in cells {
                let new = placed[c] != nil
                points += Self.value(all[c]!) * (new && Self.doubleLetter.contains(c) ? 2 : 1)
                if new && Self.doubleWord.contains(c) { factor *= 2 }
            }
            total += points * factor
        }
        return .ok(words: words, score: total + (tiles.count == Self.rackSize ? Self.fullRackBonus : 0))
    }

    /// Highest-scoring legal spot for any of `words` using these rack letters.
    func bestMove(_ words: [String], rack: [Character], isWord: (String) -> Bool) -> (tiles: [Tile], score: Int)? {
        var best: (tiles: [Tile], score: Int)?
        for word in words.map({ Array($0.uppercased()) }) where word.count >= 2 && word.count <= Self.size {
            for y in 0..<Self.size { for x in 0..<Self.size { for (dx, dy) in [(1, 0), (0, 1)] {
                var left = rack, tiles: [Tile] = [], fits = true
                for (i, letter) in word.enumerated() {
                    let c = Cell(x: x + i * dx, y: y + i * dy)
                    guard inside(c) else { fits = false; break }
                    if let there = grid[c] {
                        if there != letter { fits = false; break }
                    } else if let r = left.firstIndex(of: letter) {
                        left.remove(at: r)
                        tiles.append(Tile(cell: c, letter: letter))
                    } else { fits = false; break }
                }
                guard fits, !tiles.isEmpty, case .ok(_, let score) = evaluate(tiles, isWord: isWord), score > (best?.score ?? 0) else { continue }
                best = (tiles, score)
            } } }
        }
        return best
    }
}

/// Dictionary words the rack can make, borrowing at most one letter from the board.
func wordsFrom(_ dictionary: [String], rack: [Character], board: Set<Character>) -> [String] {
    dictionary.filter { w in
        var left = rack, borrowed = false
        for c in w.uppercased() {
            if let i = left.firstIndex(of: c) { left.remove(at: i) } else if !borrowed && board.contains(c) { borrowed = true } else { return false }
        }
        return true
    }
}

enum AppleAI {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Word ideas from the on-device model; empty when it's off, refuses, or takes too long. Often wrong, so callers check them.
    static func words(rack: [Character], board: Set<Character>) async -> [String] {
        #if canImport(FoundationModels)
        guard available, #available(macOS 26.0, *) else { return [] }
        let extra = board.isEmpty ? "" : " You may also use one of these letters once: \(String(board.sorted()))."
        let prompt = "List up to 20 common English words made only from the letters \(String(rack))\(extra) Prefer long words. Lowercase, one per line, nothing else."
        return await withTaskGroup(of: [String].self) { group in
            group.addTask {
                let text = (try? await LanguageModelSession().respond(to: prompt).content) ?? ""
                return text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { $0.allSatisfy(\.isLetter) }
            }
            group.addTask { try? await Task.sleep(nanoseconds: 20_000_000_000); return [] }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }
        #else
        return []
        #endif
    }
}

func isEnglishWord(_ w: String) -> Bool {
    w.count >= 2 && NSSpellChecker.shared.checkSpelling(of: w, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
}

final class WordGameModel: ObservableObject {
    static let shared = WordGameModel()

    @Published var board = WordBoard()
    @Published var rack: [Character] = []
    @Published var placed: [WordBoard.Tile] = []
    @Published var selected: Int?
    @Published var myScore = 0
    @Published var aiScore = 0
    @Published var thinking = false
    @Published var message = ""
    @Published var failed = false
    @Published var over = false
    @Published var lastAI: Set<WordBoard.Cell> = []
    private var aiRack: [Character] = []
    private var bag: [Character] = []
    private var passes = 0
    private var game = 0 // a reply for a game that's been restarted is dropped

    var tilesLeft: Int { bag.count }
    var busy: Bool { thinking || over }

    init() { new() }

    func new() {
        game += 1
        board = WordBoard(); placed = []; selected = nil; lastAI = []
        myScore = 0; aiScore = 0; passes = 0; thinking = false; over = false; failed = false
        message = tr("Pilih huruf, lalu klik kotak di papan.")
        bag = WordBoard.bag.shuffled()
        rack = draw(WordBoard.rackSize)
        aiRack = draw(WordBoard.rackSize)
    }

    private func draw(_ n: Int) -> [Character] {
        let out = Array(bag.prefix(n))
        bag.removeFirst(out.count)
        return out
    }

    private func say(_ text: String, failed f: Bool = false) { message = text; failed = f }

    func tapRack(_ i: Int) { guard !busy else { return }; selected = selected == i ? nil : i }

    func tapCell(_ c: WordBoard.Cell) {
        guard !busy else { return }
        if let i = placed.firstIndex(where: { $0.cell == c }) {
            rack.append(placed.remove(at: i).letter)
        } else if let s = selected, board.grid[c] == nil {
            placed.append(WordBoard.Tile(cell: c, letter: rack.remove(at: s)))
            selected = rack.isEmpty ? nil : min(s, rack.count - 1)
        }
    }

    func recall() { rack += placed.map(\.letter); placed = [] }

    func play() {
        guard !busy else { return }
        switch board.evaluate(placed, isWord: isEnglishWord) {
        case .bad(let why): say(tr(why), failed: true)
        case .ok(let words, let score):
            for t in placed { board.grid[t.cell] = t.letter }
            placed = []; selected = nil; lastAI = []; passes = 0
            myScore += score
            rack += draw(WordBoard.rackSize - rack.count)
            say(String(format: tr("%@ · +%@ poin"), words.joined(separator: ", "), "\(score)"))
            finishIfDone() ? () : aiTurn()
        }
    }

    func exchange() {
        guard !busy else { return }
        recall()
        guard bag.count >= rack.count else { say(tr("Huruf di kantong tidak cukup untuk ditukar"), failed: true); return }
        let old = rack
        rack = draw(rack.count)
        bag = (bag + old).shuffled()
        selected = nil
        passed(tr("Huruf ditukar."))
    }

    func pass() {
        guard !busy else { return }
        recall()
        selected = nil
        passed(tr("Kamu melewati giliran."))
    }

    private func passed(_ text: String) {
        passes += 1
        say(text)
        finishIfDone() ? () : aiTurn()
    }

    @discardableResult private func finishIfDone() -> Bool {
        guard passes >= 4 || (bag.isEmpty && (rack.isEmpty || aiRack.isEmpty)) else { return false }
        over = true
        say(myScore == aiScore ? tr("Permainan selesai: seri!") : myScore > aiScore ? tr("Permainan selesai: kamu menang!") : tr("Permainan selesai: Apple Intelligence menang."))
        return true
    }

    private func aiTurn() {
        thinking = true
        let now = game, board = self.board, hand = aiRack, letters = Set(board.grid.values)
        Task { @MainActor in
            let ideas = await AppleAI.words(rack: hand, board: letters)
            guard now == self.game else { return }
            let checked = Array(Set(ideas)).filter(isEnglishWord) // NSSpellChecker stays on the main thread
            let (move, byAI) = await Task.detached { () -> ((tiles: [WordBoard.Tile], score: Int)?, Bool) in
                // Read per turn rather than kept: the word list would otherwise sit in memory all day.
                let text = (try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)) ?? ""
                let dictionary = text.split(separator: "\n").filter { (2...WordBoard.rackSize).contains($0.count) && $0.first!.isLowercase }.map(String.init)
                let known = Set(dictionary).union(checked)
                if let m = board.bestMove(checked, rack: hand, isWord: known.contains) { return (m, true) }
                // Short random words keep the stand-in beatable.
                let spare = wordsFrom(dictionary, rack: hand, board: letters).filter { $0.count <= 5 }.shuffled().prefix(60)
                return (board.bestMove(Array(spare), rack: hand, isWord: known.contains), false)
            }.value
            guard now == self.game else { return }
            self.finishAITurn(move, byAI: byAI)
        }
    }

    private func finishAITurn(_ move: (tiles: [WordBoard.Tile], score: Int)?, byAI: Bool) {
        thinking = false
        guard let move else {
            passes += 1
            say(tr("Lawan melewati giliran."))
            finishIfDone()
            return
        }
        for t in move.tiles {
            board.grid[t.cell] = t.letter
            if let i = aiRack.firstIndex(of: t.letter) { aiRack.remove(at: i) }
        }
        lastAI = Set(move.tiles.map(\.cell))
        aiScore += move.score
        passes = 0
        aiRack += draw(WordBoard.rackSize - aiRack.count)
        say(String(format: tr(byAI ? "Apple Intelligence: +%@ poin" : "Kamus lokal: +%@ poin"), "\(move.score)"))
        finishIfDone()
    }
}

enum WordGameWindow {
    static func show() { AppWindow.show("wordgame", title: tr("Rangkai Kata"), size: NSSize(width: 780, height: 640)) { WordGameView(g: .shared) } }
}

struct WordGameView: View {
    @ObservedObject var g: WordGameModel

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - 230, geo.size.height - 62)
            let cell = floor((side - CGFloat(WordBoard.size - 1) * 2) / CGFloat(WordBoard.size))
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 10) {
                    VStack(spacing: 2) {
                        ForEach(0..<WordBoard.size, id: \.self) { y in
                            HStack(spacing: 2) {
                                ForEach(0..<WordBoard.size, id: \.self) { x in square(WordBoard.Cell(x: x, y: y), cell) }
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach(g.rack.indices, id: \.self) { i in
                            Button { g.tapRack(i) } label: { tile(g.rack[i], size: 44, fill: g.selected == i ? Palette.accent : Color.white.opacity(0.14), ink: g.selected == i ? Palette.onAccent : .white) }
                                .buttonStyle(.plain).accessibilityLabel(String(g.rack[i]))
                        }
                    }
                    .frame(height: 44)
                }
                .frame(width: side)
                panel
            }
        }
    }

    func square(_ c: WordBoard.Cell, _ size: CGFloat) -> some View {
        let new = g.placed.first { $0.cell == c }?.letter, fixed = g.board.grid[c]
        return Button { g.tapCell(c) } label: {
            Group {
                if let new {
                    tile(new, size: size, fill: Palette.accent, ink: Palette.onAccent)
                } else if let fixed {
                    tile(fixed, size: size, fill: Color.white.opacity(0.16), ink: .white)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(g.lastAI.contains(c) ? Palette.accent : .clear, lineWidth: 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.05)).frame(width: size, height: size)
                        .overlay {
                            if WordBoard.doubleWord.contains(c) { Text("2K").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.accent) }
                            else if WordBoard.doubleLetter.contains(c) { Text("2H").font(.system(size: 9, weight: .bold)).foregroundStyle(.gray) }
                            else if c == WordBoard.center { Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray) }
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((new ?? fixed).map(String.init) ?? "\(c.x + 1), \(c.y + 1)")
    }

    func tile(_ letter: Character, size: CGFloat, fill: Color, ink: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill).frame(width: size, height: size)
            .overlay(Text(String(letter)).font(.system(size: floor(size * 0.5), weight: .semibold)).foregroundStyle(ink))
            .overlay(alignment: .bottomTrailing) {
                Text("\(WordBoard.value(letter))").font(.system(size: 9, weight: .medium)).foregroundStyle(ink.opacity(0.7)).padding(2)
            }
    }

    var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                score("Kamu", g.myScore)
                score(AppleAI.available ? "Apple AI" : "Kamus", g.aiScore)
            }
            HStack(spacing: 6) {
                if g.thinking { ProgressView().controlSize(.small) }
                Text(g.thinking ? tr("Lawan sedang berpikir…") : g.message).font(.system(size: 12))
                    .foregroundStyle(g.failed && !g.thinking ? Palette.red : .white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 34, alignment: .topLeading)
            NButton(icon: "checkmark", title: "Mainkan", tint: Palette.accent, prominent: true) { g.play() }.disabled(g.busy || g.placed.isEmpty)
            HStack(spacing: 6) {
                NButton(icon: "arrow.uturn.backward", title: "Tarik") { g.recall() }.disabled(g.placed.isEmpty)
                NButton(icon: "arrow.2.squarepath", title: "Tukar") { g.exchange() }.disabled(g.busy)
            }
            NButton(icon: "forward.fill", title: "Lewati") { g.pass() }.disabled(g.busy)
            Text(String(format: tr("%@ huruf di kantong"), "\(g.tilesLeft)")).font(.system(size: 11)).foregroundStyle(.gray)
            if !AppleAI.available {
                Text(tr("Apple Intelligence tidak aktif, lawanmu memakai kamus lokal.")).font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("2K menggandakan kata, 2H menggandakan huruf. Kata dalam bahasa Inggris.")).font(.system(size: 11)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            NButton(icon: "arrow.clockwise", title: "Main baru") { g.new() }
        }
        .frame(width: 212, alignment: .leading)
    }

    func score(_ who: String, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tr(who)).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
            Text("\(n)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inside the island: the board itself opens in a window.
struct WordGameIntro: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Rangkai kata silang di papan, bergantian melawan Apple Intelligence. Kata dalam bahasa Inggris."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
            NButton(icon: "play.fill", title: "Main", tint: Palette.accent, prominent: true) { WordGameWindow.show() }
        }
    }
}
