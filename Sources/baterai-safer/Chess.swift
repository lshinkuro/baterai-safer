import SwiftUI

// Lainnya → Gabut → Catur: the player is white, the computer searches on a background queue.

/// Board index 0 is a8 and 63 is h1. Pieces: 1 pawn, 2 knight, 3 bishop, 4 rook, 5 queen, 6 king; positive is white.
struct Chess {
    struct Move: Equatable { var from, to: Int }
    static let levels: [(name: String, depth: Int, slip: Double)] = [("Mudah", 1, 0.3), ("Medium", 2, 0.05), ("Sulit", 5, 0)]
    static let values = [0, 100, 320, 330, 500, 900, 0], mate = 100_000, infinity = 1_000_000
    static let knight = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]
    static let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)], diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

    var b = [-4, -2, -3, -5, -6, -3, -2, -4] + [Int](repeating: -1, count: 8) + [Int](repeating: 0, count: 32)
        + [Int](repeating: 1, count: 8) + [4, 2, 3, 5, 6, 3, 2, 4]
    var white = true
    var castle = 15   // 1 white short, 2 white long, 4 black short, 8 black long
    var ep = -1       // square a pawn just skipped
    var quiet = 0     // half moves since a capture or pawn move

    var side: Int { white ? 1 : -1 }
    var key: [Int] { b + [side, castle, ep] }

    func piece(_ r: Int, _ c: Int) -> Int? { r >= 0 && r < 8 && c >= 0 && c < 8 ? b[r * 8 + c] : nil }

    func attacked(_ i: Int, by s: Int) -> Bool {
        let r = i / 8, c = i % 8
        if piece(r + s, c - 1) == s || piece(r + s, c + 1) == s { return true }
        if Self.knight.contains(where: { piece(r + $0.0, c + $0.1) == 2 * s }) { return true }
        func ray(_ d: (Int, Int), _ slider: Int) -> Bool {
            var k = 1
            while let p = piece(r + d.0 * k, c + d.1 * k) {
                if p == 0 { k += 1; continue }
                return p * s > 0 && (abs(p) == slider || abs(p) == 5 || (abs(p) == 6 && k == 1))
            }
            return false
        }
        return Self.orthogonal.contains { ray($0, 4) } || Self.diagonal.contains { ray($0, 3) }
    }

    func inCheck(_ s: Int) -> Bool { b.firstIndex(of: 6 * s).map { attacked($0, by: -s) } ?? false }

    /// Moves that obey how pieces travel; they may still leave the own king in check.
    func pseudo() -> [Move] {
        var out = [Move]()
        out.reserveCapacity(48)
        let s = side
        func walk(_ i: Int, _ dirs: [(Int, Int)], slide: Bool) {
            for d in dirs {
                var r = i / 8 + d.0, c = i % 8 + d.1
                while let p = piece(r, c), p * s <= 0 {
                    out.append(Move(from: i, to: r * 8 + c))
                    if p != 0 || !slide { break }
                    r += d.0; c += d.1
                }
            }
        }
        for i in 0..<64 where b[i] * s > 0 {
            switch abs(b[i]) {
            case 1:
                let f = i - 8 * s
                if b[f] == 0 {
                    out.append(Move(from: i, to: f))
                    if i / 8 == (white ? 6 : 1), b[f - 8 * s] == 0 { out.append(Move(from: i, to: f - 8 * s)) }
                }
                for dc in [-1, 1] where (0..<8).contains(i % 8 + dc) {
                    let t = f + dc
                    if b[t] * s < 0 || t == ep { out.append(Move(from: i, to: t)) }
                }
            case 2: walk(i, Self.knight, slide: false)
            case 3: walk(i, Self.diagonal, slide: true)
            case 4: walk(i, Self.orthogonal, slide: true)
            case 5: walk(i, Self.orthogonal + Self.diagonal, slide: true)
            default:
                walk(i, Self.orthogonal + Self.diagonal, slide: false)
                let (short, long) = white ? (1, 2) : (4, 8)
                if castle & short != 0, b[i + 1] == 0, b[i + 2] == 0, !attacked(i, by: -s), !attacked(i + 1, by: -s) { out.append(Move(from: i, to: i + 2)) }
                if castle & long != 0, b[i - 1] == 0, b[i - 2] == 0, b[i - 3] == 0, !attacked(i, by: -s), !attacked(i - 1, by: -s) { out.append(Move(from: i, to: i - 2)) }
            }
        }
        return out
    }

    func after(_ m: Move) -> Chess {
        var n = self
        let p = b[m.from], s = p > 0 ? 1 : -1
        n.ep = -1
        n.quiet = abs(p) == 1 || b[m.to] != 0 ? 0 : quiet + 1
        n.b[m.from] = 0
        n.b[m.to] = p
        if abs(p) == 1 {
            if m.to == ep { n.b[m.to + 8 * s] = 0 }
            if abs(m.to - m.from) == 16 { n.ep = (m.from + m.to) / 2 }
            if m.to < 8 || m.to >= 56 { n.b[m.to] = 5 * s } // shortcut: always promotes to a queen, add a chooser if underpromotion is wanted
        }
        if abs(p) == 6, abs(m.to - m.from) == 2 {
            let short = m.to > m.from
            n.b[short ? m.to + 1 : m.to - 2] = 0
            n.b[short ? m.to - 1 : m.to + 1] = 4 * s
        }
        // Leaving or capturing on a king or rook home square ends the matching right.
        for i in [m.from, m.to] {
            switch i {
            case 0: n.castle &= ~8
            case 4: n.castle &= ~12
            case 7: n.castle &= ~4
            case 56: n.castle &= ~2
            case 60: n.castle &= ~3
            case 63: n.castle &= ~1
            default: break
            }
        }
        n.white.toggle()
        return n
    }

    func legal() -> [Move] { let s = side; return pseudo().filter { !after($0).inCheck(s) } }

    /// The result text once the game is over, nil while it goes on.
    func outcome(repeated: Bool) -> String? {
        if legal().isEmpty { return inCheck(side) ? (white ? "Komputer menang" : "Kamu menang!") : "Seri" }
        let rest = b.filter { $0 != 0 && abs($0) != 6 }
        let bare = rest.count <= 1 && rest.allSatisfy { abs($0) == 2 || abs($0) == 3 }
        return repeated || quiet >= 100 || bare ? "Seri" : nil
    }

    /// Score for the side to move: material, centre control, pawn progress and a king that hides until the endgame.
    func eval() -> Int {
        let late = b.lazy.filter { $0 != 0 }.count <= 10
        var score = 0
        for i in 0..<64 where b[i] != 0 {
            let p = b[i], s = p > 0 ? 1 : -1, r = i / 8, c = i % 8
            let centre = 7 - (abs(2 * r - 7) + abs(2 * c - 7)) / 2
            var v = Self.values[abs(p)]
            switch abs(p) {
            case 1: v += (s > 0 ? 7 - r : r) * 6 + centre
            case 2, 3: v += centre * 5
            case 6: v += late ? centre * 4 : -centre * 6
            default: break
            }
            score += s * v
        }
        return score * side
    }

    /// Biggest victim first, cheapest attacker first, so alpha-beta cuts early.
    func ordered(_ moves: [Move]) -> [Move] {
        moves.map { m in (m, abs(b[m.to]) * 10 - (b[m.to] != 0 ? abs(b[m.from]) : 0)) }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Plays captures out so the score isn't taken in the middle of an exchange.
    func quiesce(_ a: Int, _ beta: Int) -> Int {
        let stand = eval()
        if stand >= beta { return stand }
        var alpha = max(a, stand)
        let s = side
        for m in ordered(pseudo().filter { b[$0.to] != 0 }) {
            let n = after(m)
            if n.inCheck(s) { continue }
            let v = -n.quiesce(-beta, -alpha)
            if v >= beta { return v }
            alpha = max(alpha, v)
        }
        return alpha
    }

    func search(_ depth: Int, _ a: Int, _ beta: Int, ply: Int, capturesOut: Bool) -> Int {
        if depth == 0 { return capturesOut ? quiesce(a, beta) : eval() }
        var alpha = a, any = false
        let s = side
        for m in ordered(pseudo()) {
            let n = after(m)
            if n.inCheck(s) { continue }
            any = true
            let v = -n.search(depth - 1, -beta, -alpha, ply: ply + 1, capturesOut: capturesOut)
            if v >= beta { return v }
            alpha = max(alpha, v)
        }
        if !any { return inCheck(s) ? -(Self.mate - ply) : 0 }
        return alpha
    }

    /// shortcut: the search ignores repetition, so it can draw a won game; track the path if that shows up in play.
    func bestMove(depth: Int) -> Move? {
        var best: Move?, alpha = -Self.infinity
        let s = side
        // Shuffled first so equal moves differ from game to game.
        for m in ordered(pseudo().shuffled()) {
            let n = after(m)
            if n.inCheck(s) { continue }
            let v = -n.search(depth - 1, -Self.infinity, -alpha, ply: 1, capturesOut: depth > 1)
            if best == nil || v > alpha { alpha = v; best = m }
        }
        return best
    }
}

// MARK: Game

final class ChessGame: ObservableObject {
    static let shared = ChessGame() // shared so a closed notch doesn't lose the game

    @Published private(set) var pos = Chess()
    @Published private(set) var last: Chess.Move?
    @Published private(set) var thinking = false
    @Published private(set) var result: String?
    @Published private(set) var tally = (win: 0, lose: 0, draw: 0)
    @Published var selected: Int?
    @Published var level = UserDefaults.standard.integer(forKey: "chessLevel") {
        didSet { UserDefaults.standard.set(level, forKey: "chessLevel") }
    }
    private var seen = [Chess().key: 1]
    private var round = 0 // a reply computed for an abandoned game is dropped

    var targets: [Int] { selected.map { s in pos.legal().filter { $0.from == s }.map(\.to) } ?? [] }

    func tap(_ i: Int) {
        guard !thinking, result == nil else { return }
        if let s = selected, let m = pos.legal().first(where: { $0.from == s && $0.to == i }) {
            commit(m)
            if result == nil { reply() }
        } else {
            selected = pos.b[i] > 0 && selected != i ? i : nil
        }
    }

    func reset() {
        round += 1
        pos = Chess(); seen = [pos.key: 1]
        last = nil; selected = nil; result = nil; thinking = false
    }

    private func commit(_ m: Chess.Move) {
        pos = pos.after(m)
        last = m
        selected = nil
        seen[pos.key, default: 0] += 1
        result = pos.outcome(repeated: seen[pos.key]! >= 3)
        switch result {
        case "Kamu menang!": tally.win += 1
        case "Komputer menang": tally.lose += 1
        case "Seri": tally.draw += 1
        default: break
        }
    }

    private func reply() {
        thinking = true
        let start = pos, l = Chess.levels[level], id = round
        let due = DispatchTime.now() + .random(in: 1.2...2.5) // an instant reply feels rude, so it always takes a moment
        DispatchQueue.global(qos: .userInitiated).async {
            let m = Double.random(in: 0..<1) < l.slip ? start.legal().randomElement() : start.bestMove(depth: l.depth)
            DispatchQueue.main.asyncAfter(deadline: due) {
                guard id == self.round else { return }
                self.thinking = false
                if let m { self.commit(m) }
            }
        }
    }
}

enum ChessWindow {
    static func show() { AppWindow.show("chess", title: tr("Catur"), size: NSSize(width: 820, height: 620)) { ChessView(windowed: true) } }
}

struct ChessView: View {
    @ObservedObject var g = ChessGame.shared
    var windowed = false
    static let glyphs = ["", "♟", "♞", "♝", "♜", "♛", "♚"]
    static let names = ["", "Pion", "Kuda", "Gajah", "Benteng", "Ratu", "Raja"]

    var status: String { g.result ?? (g.thinking ? "Komputer berpikir…" : g.pos.inCheck(1) ? "Skak! Giliranmu" : "Giliranmu") }

    var body: some View {
        if windowed {
            GeometryReader { geo in layout(cell: max(30, ((min(geo.size.width - 270, geo.size.height)) / 8).rounded(.down))) }
        } else {
            layout(cell: 25)
        }
    }

    func layout(cell: CGFloat) -> some View {
        let targets = g.targets
        return HStack(spacing: 18) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { c in square(r * 8 + c, target: targets.contains(r * 8 + c), cell: cell) }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 1))
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(status)).font(.system(size: 15, weight: .semibold))
                Text("Menang \(g.tally.win) · Kalah \(g.tally.lose) · Seri \(g.tally.draw)").font(.system(size: 11)).foregroundStyle(.gray).monospacedDigit()
                HStack(spacing: 4) {
                    ForEach(Chess.levels.indices, id: \.self) { i in
                        Button { g.level = i } label: {
                            Text(tr(Chess.levels[i].name)).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(g.level == i ? Palette.onAccent : .gray)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(g.level == i ? Palette.accent : Color.white.opacity(0.05), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 6) {
                    NButton(icon: "arrow.counterclockwise", title: "Main lagi", tint: Palette.accent, prominent: g.result != nil) {
                        withAnimation(Motion.ease) { g.reset() }
                    }
                    if !windowed { NButton(icon: "arrow.up.left.and.arrow.down.right") { ChessWindow.show() }.tip("Buka di jendela besar") }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    func square(_ i: Int, target: Bool, cell: CGFloat) -> some View {
        let p = g.pos.b[i], light = (i / 8 + i % 8) % 2 == 0
        let inCheck = abs(p) == 6 && g.result == nil && g.pos.side * p > 0 && g.pos.inCheck(g.pos.side)
        let fill = inCheck ? Palette.red.opacity(0.5)
            : g.selected == i ? Palette.accent.opacity(0.45)
            : g.last?.from == i || g.last?.to == i ? Palette.accent.opacity(0.2)
            : Color.white.opacity(light ? 0.14 : 0.05)
        return Button { g.tap(i) } label: {
            // U+FE0E keeps the pawn from rendering as an emoji.
            Text(p == 0 ? "" : Self.glyphs[abs(p)] + "\u{FE0E}").font(.system(size: (cell * 0.8).rounded()))
                .foregroundStyle(p > 0 ? Color.white : Palette.accent)
                .frame(width: cell, height: cell)
                .background(fill)
                .overlay { if target { Circle().fill(Palette.accent.opacity(p == 0 ? 0.8 : 0.45)).frame(width: cell * (p == 0 ? 0.28 : 0.84), height: cell * (p == 0 ? 0.28 : 0.84)) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(squareName(i, p))
    }

    func squareName(_ i: Int, _ p: Int) -> String {
        let name = "\(["a", "b", "c", "d", "e", "f", "g", "h"][i % 8])\(8 - i / 8)"
        return p == 0 ? name : "\(name) \(tr(Self.names[abs(p)])) \(tr(p > 0 ? "putih" : "hitam"))"
    }
}
