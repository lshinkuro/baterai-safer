import SwiftUI

// Lainnya → Gabut: small games for a bored minute. Timers and key capture stop when the page closes.

// MARK: Ular

struct Snake {
    struct Point: Hashable { var x, y: Int }
    static let cols = 30, rows = 10

    var body = [Point(x: 5, y: 5), Point(x: 4, y: 5), Point(x: 3, y: 5)]
    var dir = Point(x: 1, y: 0)   // last direction moved
    var next = Point(x: 1, y: 0)  // queued turn
    var food = Point(x: 18, y: 5)
    var over = false
    var score: Int { body.count - 3 }

    /// Ignores a turn straight back into the neck (checked against the last move, not the last key).
    mutating func turn(_ d: Point) { if d.x != -dir.x || d.y != -dir.y { next = d } }

    /// One tick: move, grow on food, end on a wall or itself.
    mutating func step(spawn: () -> Point = { Point(x: .random(in: 0..<Snake.cols), y: .random(in: 0..<Snake.rows)) }) {
        guard !over else { return }
        dir = next
        let head = Point(x: body[0].x + dir.x, y: body[0].y + dir.y)
        // The tail moves away this tick, so stepping onto it is fine.
        if head.x < 0 || head.y < 0 || head.x >= Self.cols || head.y >= Self.rows || body.dropLast().contains(head) { over = true; return }
        body.insert(head, at: 0)
        guard head == food else { body.removeLast(); return }
        guard body.count < Self.cols * Self.rows else { over = true; return } // board full: nowhere left for food
        repeat { food = spawn() } while body.contains(food)
    }
}

final class SnakeGame: ObservableObject {
    @Published var s = Snake()
    @Published var running = false
    @Published var best = UserDefaults.standard.integer(forKey: "snakeBest")
    private var timer: Timer?
    private var keys: Any?

    func start() {
        if s.over || !running { s = Snake() }
        running = true
        // Arrow keys need the island to be the key window.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0 is NotchPanel }?.makeKey()
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let d: Snake.Point? = switch e.keyCode {
            case 123, 0: Snake.Point(x: -1, y: 0)  // ← A
            case 124, 2: Snake.Point(x: 1, y: 0)   // → D
            case 125, 1: Snake.Point(x: 0, y: 1)   // ↓ S
            case 126, 13: Snake.Point(x: 0, y: -1) // ↑ W
            default: nil
            }
            guard let d, let self else { return e }
            self.s.turn(d)
            return nil
        }
        timer = .scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    private func tick() {
        s.step()
        guard s.over else { return }
        stop()
        if s.score > best { best = s.score; UserDefaults.standard.set(best, forKey: "snakeBest") }
    }
}

struct SnakeView: View {
    @StateObject private var g = SnakeGame()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Skor \(g.s.score)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                Text("Terbaik \(g.best)").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
                Spacer()
                NButton(icon: "play.fill", title: g.running && !g.s.over ? "Ulang" : "Mulai", tint: Palette.accent, prominent: true) { g.stop(); g.start() }
            }
            GeometryReader { geo in
                let cell = min(geo.size.width / CGFloat(Snake.cols), geo.size.height / CGFloat(Snake.rows))
                let w = cell * CGFloat(Snake.cols), h = cell * CGFloat(Snake.rows)
                Canvas { ctx, _ in
                    func rect(_ p: Snake.Point) -> CGRect { CGRect(x: CGFloat(p.x) * cell, y: CGFloat(p.y) * cell, width: cell, height: cell).insetBy(dx: 1, dy: 1) }
                    ctx.fill(Path(ellipseIn: rect(g.s.food).insetBy(dx: 1.5, dy: 1.5)), with: .color(Palette.accent))
                    for (i, p) in g.s.body.enumerated() {
                        ctx.fill(Path(roundedRect: rect(p), cornerRadius: cell * 0.3), with: .color(i == 0 ? .white : .white.opacity(0.55)))
                    }
                }
                .frame(width: w, height: h)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                .overlay {
                    if !g.running || g.s.over {
                        Text(g.s.over ? "Game over · skor \(g.s.score)" : "Mulai, lalu arahkan dengan ← ↑ → ↓ atau WASD")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 12).padding(.vertical, 6).background(.black.opacity(0.6), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { g.stop() }
    }
}

// MARK: Kartu Kembar

struct Memory {
    static let icons = ["star.fill", "heart.fill", "bolt.fill", "leaf.fill", "moon.fill", "flame.fill", "drop.fill", "bell.fill"]
    var cards: [String]
    var open: [Int] = []          // face up, not yet matched (at most 2)
    var matched: Set<Int> = []
    var moves = 0
    var won: Bool { matched.count == cards.count }

    init(shuffled: Bool = true) { cards = Self.icons + Self.icons; if shuffled { cards.shuffle() } }

    /// Turns a card up; a third card hides an unmatched pair first.
    mutating func flip(_ i: Int) {
        guard !matched.contains(i), !open.contains(i) else { return }
        if open.count == 2 { open = [] }
        open.append(i)
        guard open.count == 2 else { return }
        moves += 1
        if cards[open[0]] == cards[open[1]] { matched.formUnion(open); open = [] }
    }
}

struct MemoryView: View {
    @Local private var m = Memory()
    @AppStorage("memoryBest") private var best = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(m.won ? "Beres dalam \(m.moves) langkah!" : "Langkah \(m.moves)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                if best > 0 { Text("Terbaik \(best)").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit() }
                Spacer()
                NButton(icon: "shuffle", title: "Acak ulang", tint: Palette.accent, prominent: m.won) { withAnimation(Motion.ease) { m = Memory() } }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(m.cards.indices, id: \.self) { i in
                    let up = m.open.contains(i) || m.matched.contains(i), done = m.matched.contains(i)
                    Button { tap(i) } label: {
                        Image(systemName: m.cards[i]).font(.system(size: 20, weight: .medium))
                            .foregroundStyle(done ? Palette.accent : .white)
                            .opacity(up ? 1 : 0)
                            .frame(maxWidth: .infinity, minHeight: 66)
                            .background(done ? Palette.accent.opacity(0.14) : Color.white.opacity(up ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(Motion.ease, value: up)
                }
            }
        }
    }

    func tap(_ i: Int) {
        m.flip(i)
        if m.won, best == 0 || m.moves < best { best = m.moves }
        // A missed pair turns back by itself after a moment.
        let pair = m.open
        if pair.count == 2 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { if m.open == pair { m.open = [] } } }
    }
}

// MARK: X-O

enum XO {
    static let lines = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]

    static func winner(_ b: [Character?]) -> Character? {
        lines.first { l in b[l[0]] != nil && b[l[0]] == b[l[1]] && b[l[1]] == b[l[2]] }.flatMap { b[$0[0]] }
    }

    /// Perfect move for the computer ("O") by minimax; the view mixes in mistakes so it can be beaten.
    static func bestMove(_ b: [Character?]) -> Int? {
        func score(_ b: [Character?], _ turn: Character) -> Int {
            if let w = winner(b) { return w == "O" ? 1 : -1 }
            let free = b.indices.filter { b[$0] == nil }
            if free.isEmpty { return 0 }
            let s = free.map { i -> Int in var n = b; n[i] = turn; return score(n, turn == "O" ? "X" : "O") }
            return turn == "O" ? s.max()! : s.min()!
        }
        let free = b.indices.filter { b[$0] == nil }
        let scored = free.map { i -> (Int, Int) in var n = b; n[i] = "O"; return (i, score(n, "X")) }
        return scored.max { $0.1 < $1.1 }?.0
    }
}

struct XOView: View {
    @Local private var b = [Character?](repeating: nil, count: 9)
    @Local private var tally = (win: 0, lose: 0, draw: 0)

    var result: String? {
        if let w = XO.winner(b) { return w == "X" ? "Kamu menang!" : "Komputer menang" }
        return b.allSatisfy { $0 != nil } ? "Seri" : nil
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { c in cell(r * 3 + c) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(result ?? "Giliranmu (X)")).font(.system(size: 15, weight: .semibold))
                Text("Menang \(tally.win) · Kalah \(tally.lose) · Seri \(tally.draw)").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
                NButton(icon: "arrow.counterclockwise", title: "Main lagi", tint: Palette.accent, prominent: result != nil) {
                    withAnimation(Motion.ease) { b = Array(repeating: nil, count: 9) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    func cell(_ i: Int) -> some View {
        Button { play(i) } label: {
            Text(b[i].map(String.init) ?? "").font(.system(size: 26, weight: .semibold))
                .foregroundStyle(b[i] == "X" ? Color.white : Palette.accent)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(b[i] != nil || result != nil)
    }

    func play(_ i: Int) {
        b[i] = "X"
        if result == nil {
            // One move in four is random, so a careful player can win.
            let free = b.indices.filter { b[$0] == nil }
            if let j = Int.random(in: 0..<4) == 0 ? free.randomElement() : XO.bestMove(b) { b[j] = "O" }
        }
        switch result {
        case "Kamu menang!": tally.win += 1
        case "Komputer menang": tally.lose += 1
        case "Seri": tally.draw += 1
        default: break
        }
    }
}

// MARK: Page

struct GamesPage: View {
    @AppStorage("game") private var game = 0
    // Only games that fit the notch belong here. The first value is what "game" stores, so don't renumber.
    static let games = [(0, "Ular", "scribble.variable"), (1, "Kartu Kembar", "square.grid.2x2"), (2, "X-O", "number"), (4, "Catur", "crown"), (5, "Hangman", "textformat.abc"), (6, "Sudoku", "square.grid.3x3")]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                ForEach(Self.games, id: \.0) { g in
                    let on = game == g.0
                    Button { game = g.0 } label: {
                        Label(tr(g.1), systemImage: g.2).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(on ? Palette.onAccent : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(on ? Palette.accent : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 140)
            Group {
                switch game {
                case 0: SnakeView()
                case 1: MemoryView()
                case 4: ChessView()
                case 5: HangmanView()
                case 6: SudokuView()
                default: XOView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
