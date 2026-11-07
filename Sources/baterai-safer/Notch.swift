import SwiftUI
import Charts

enum NTab: Int, CaseIterable {
    case music, focus, ai, clipboard, shelf, git, stats
    var icon: String { ["music.note", "timer", "sparkles", "doc.on.clipboard", "tray.full", "arrow.triangle.branch", "gauge.medium"][rawValue] }
    var title: String { ["Musik", "Fokus", "AI", "Clipboard", "Shelf", "Git", "Stats"][rawValue] }
    var color: Color { [Color.pink, .orange, .purple, .teal, .blue, .indigo, .green][rawValue] }
}

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var tab = NTab.music
    var notch = CGSize(width: 185, height: 32)
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true } // lets text fields in the island take typing
}

/// Island window at the top-center of the notched (or main) screen. It ignores clicks while
/// collapsed, so the menu bar under it keeps working; hovering the notch expands it.
final class Notch {
    static let shared = Notch()
    static let size = CGSize(width: 680, height: 330) // window; the visible island is smaller
    let state = NotchState()
    let media = NowPlaying(), focus = Focus(), clips = ClipboardModel(), shelf = Shelf(), sys = SystemModel()
    let git = GitModel(), ai = AIModel(), pr = PRModel()
    private var panel: NotchPanel?
    private var monitors: [Any] = []

    func show() {
        guard panel == nil, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let f = screen.frame
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            state.notch = CGSize(width: f.width - l.width - r.width, height: screen.safeAreaInsets.top)
        } else {
            state.notch = CGSize(width: 185, height: NSStatusBar.system.thickness)
        }
        let p = NotchPanel(contentRect: NSRect(x: f.midX - Self.size.width / 2, y: f.maxY - Self.size.height, width: Self.size.width, height: Self.size.height),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.acceptsMouseMovedEvents = true
        p.contentView = NSHostingView(rootView: NotchView(state: state, media: media, focus: focus, ai: ai,
                                                          clips: clips, shelf: shelf, sys: sys, git: git, pr: pr))
        p.orderFrontRegardless()
        panel = p

        // Mouse-move monitoring needs no Accessibility permission (only key monitoring does).
        let handle: (NSEvent) -> Void = { [weak self] e in self?.track(dragging: e.type == .leftMouseDragged) }
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handle),
                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { handle($0); return $0 }].compactMap { $0 }
        media.start()
        clips.start()
    }

    func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        media.stop()
        clips.stop()
    }

    private func track(dragging: Bool) {
        guard let panel else { return }
        let p = NSEvent.mouseLocation, f = panel.frame, n = state.notch, o = NotchView.open
        let hot = NSRect(x: f.midX - n.width / 2 - 50, y: f.maxY - n.height - 4, width: n.width + 100, height: n.height + 4)
        let open = NSRect(x: f.midX - o.width / 2, y: f.maxY - o.height, width: o.width, height: o.height).insetBy(dx: -14, dy: -14)
        if !state.expanded, hot.contains(p) {
            if dragging { state.tab = .shelf } // dragging a file in → straight to the shelf
            set(true)
        } else if state.expanded, !open.contains(p) {
            set(false)
        }
    }

    private func set(_ open: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { state.expanded = open }
        panel?.ignoresMouseEvents = !open
    }
}

/// Flat top (flush with the screen edge), rounded bottom — the notch silhouette.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: Island building blocks (always dark)

struct NCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07)))
    }
}

struct NButton: View {
    let icon: String
    var title: String?
    var tint: Color = .white
    var prominent = false
    let run: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                if let title { Text(title).font(.system(size: 11.5, weight: .semibold)) }
            }
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, title == nil ? 0 : 11)
            .frame(minWidth: 28, minHeight: 28)
            .background(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(hover ? 0.16 : 0.09)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Chip: View {
    let text: String
    var icon: String?
    var color: Color = .gray

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
    }
}

struct Placeholder: View {
    let icon: String, title: String
    var subtitle: String?
    var color: Color = .gray

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(color.gradient, in: Circle())
                .shadow(color: color.opacity(0.5), radius: 12)
            Text(title).font(.system(size: 13, weight: .semibold))
            if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.gray).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Equalizer: View {
    var color: Color = .green

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(color.gradient)
                        .frame(width: 3, height: 4 + 10 * abs(sin(t * (2.3 + Double(i) * 0.8) + Double(i) * 1.7)))
                }
            }
            .frame(height: 14)
        }
    }
}

// MARK: Island

struct NotchView: View {
    static let open = CGSize(width: 620, height: 290)
    @ObservedObject var state: NotchState
    @ObservedObject var media: NowPlaying
    @ObservedObject var focus: Focus
    @ObservedObject var ai: AIModel
    let clips: ClipboardModel, shelf: Shelf, sys: SystemModel, git: GitModel, pr: PRModel
    @State private var dropping = false
    @Namespace private var ns

    var live: Bool { media.playing || focus.running || ai.running }

    var body: some View {
        let n = state.notch
        let size = state.expanded ? Self.open : CGSize(width: n.width + (live ? 96 : 0), height: n.height)
        ZStack(alignment: .top) {
            ZStack {
                Color.black
                // Album art glow behind the music tab.
                if state.expanded, state.tab == .music, let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .blur(radius: 60).opacity(0.45).saturation(1.4)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(NotchShape(radius: state.expanded ? 26 : 10))
            .overlay(NotchShape(radius: state.expanded ? 26 : 10).stroke(Color.white.opacity(state.expanded ? 0.08 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(state.expanded ? 0.55 : 0), radius: 18, y: 8)

            if state.expanded {
                expanded(n)
                    .frame(width: Self.open.width, height: Self.open.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if live {
                collapsed.frame(width: size.width, height: n.height).transition(.opacity)
            }
        }
        .frame(width: Notch.size.width, height: Notch.size.height, alignment: .top)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { shelf.add($0) }
        .environment(\.colorScheme, .dark)
    }

    // Live activity beside the camera housing while collapsed.
    var collapsed: some View {
        HStack {
            Group {
                if ai.running {
                    Image(systemName: "sparkles").foregroundStyle(.purple)
                } else if focus.running {
                    Image(systemName: "timer").foregroundStyle(.orange)
                } else if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "music.note").foregroundStyle(.pink)
                }
            }
            .frame(width: 22)
            Spacer()
            if ai.running {
                ProgressView().controlSize(.mini).tint(.purple)
            } else if focus.running {
                Text(focus.clock).font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.orange)
            } else {
                Equalizer()
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
    }

    func expanded(_ n: CGSize) -> some View {
        VStack(spacing: 0) {
            // Top row sits beside the camera housing: tabs left, status right.
            HStack(spacing: 0) {
                HStack(spacing: 1) {
                    ForEach(NTab.allCases, id: \.self) { t in
                        let on = state.tab == t
                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.tab = t } } label: {
                            Image(systemName: t.icon).font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(on ? Color.white : Color.white.opacity(0.45))
                                .frame(width: 26, height: 22)
                                .background {
                                    if on { Capsule().fill(t.color.gradient).matchedGeometryEffect(id: "tab", in: ns) }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).help(t.title)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.07), in: Capsule())
                Spacer(minLength: n.width + 12)
                HStack(spacing: 8) {
                    Text(state.tab.title).font(.system(size: 12, weight: .bold))
                    StatusClock()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(n.height, 30))
            .padding(.horizontal, 18)

            Group {
                switch state.tab {
                case .music: MusicView(m: media)
                case .focus: FocusView(f: focus)
                case .ai: AIView(ai: ai)
                case .clipboard: ClipView(c: clips)
                case .shelf: ShelfView(s: shelf, dropping: dropping)
                case .git: GitView(g: git, pr: pr, ai: ai)
                case .stats: StatsView(s: sys)
                }
            }
            .id(state.tab)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
        }
        .foregroundStyle(.white)
    }
}

struct StatusClock: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let b = Battery.read()
            HStack(spacing: 5) {
                Image(systemName: b.ac ? "battery.100percent.bolt" : "battery.\(min(100, (b.percent + 12) / 25 * 25))percent")
                    .foregroundStyle(b.percent <= 20 && !b.ac ? .red : .green)
                Text("\(b.percent)%")
                Text(ctx.date, format: .dateTime.hour().minute()).foregroundStyle(.gray)
            }
            .font(.system(size: 11, weight: .semibold)).monospacedDigit()
        }
    }
}

func mmss(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

// MARK: Tabs

struct MusicView: View {
    @ObservedObject var m: NowPlaying

    var body: some View {
        if m.app == nil || m.title.isEmpty {
            Placeholder(icon: "music.note", title: m.app == nil ? "Tidak ada musik" : "\(m.app!) dijeda",
                        subtitle: "Putar lagu di Spotify atau Apple Music", color: .pink)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let pos = m.now(ctx.date)
                let i = m.lyrics.lastIndex { $0.t <= pos + 0.3 }
                HStack(spacing: 18) {
                    Group {
                        if let art = m.artwork {
                            Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08))
                        }
                    }
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                                Text(m.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            }
                            Spacer()
                            if m.playing { Equalizer(color: .white.opacity(0.8)) }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let i {
                                Text(m.lyrics[i].line.isEmpty ? "♪" : m.lyrics[i].line)
                                    .font(.system(size: 15, weight: .semibold)).lineLimit(2)
                                    .id(i).transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)), removal: .opacity))
                                if i + 1 < m.lyrics.count {
                                    Text(m.lyrics[i + 1].line).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                                }
                            } else {
                                Text(m.lyrics.isEmpty ? m.lyricsStatus : "♪").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .animation(.easeOut(duration: 0.3), value: i)

                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18))
                                Capsule().fill(Color.white).frame(width: g.size.width * (m.duration > 0 ? pos / m.duration : 0))
                            }
                        }
                        .frame(height: 4)
                        HStack {
                            Text(mmss(pos))
                            Spacer()
                            Text("-" + mmss(max(0, m.duration - pos)))
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)

                        HStack(spacing: 34) {
                            control("backward.fill", 17) { m.send("previous track") }
                            control(m.playing ? "pause.fill" : "play.fill", 26) { m.send("playpause") }
                            control("forward.fill", 17) { m.send("next track") }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    func control(_ icon: String, _ size: CGFloat, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: icon).font(.system(size: size)).frame(width: 36, height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
}

struct FocusView: View {
    @ObservedObject var f: Focus

    var body: some View {
        let color: Color = f.onBreak ? .green : .orange
        HStack(spacing: 14) {
            NCard {
                VStack(spacing: 12) {
                    Ring(value: f.remaining / f.total, color: color, label: f.clock, caption: f.onBreak ? "istirahat" : "fokus", size: 128, line: 10)
                    HStack(spacing: 8) {
                        NButton(icon: "arrow.counterclockwise") { f.reset() }.help("Ulang")
                        NButton(icon: f.running ? "pause.fill" : "play.fill", title: f.running ? "Jeda" : "Mulai", tint: color, prominent: true) { f.toggle() }
                        NButton(icon: "forward.end.fill") { f.next() }.help(f.onBreak ? "Lewati istirahat" : "Lewati ke istirahat")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 210)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    stat("flame.fill", .orange, "\(f.streak)", "hari beruntun")
                    stat("clock.fill", .blue, "\(f.today)", "menit hari ini")
                }
                .frame(height: 64)
                NCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("7 HARI TERAKHIR").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.gray)
                        Chart(f.last7, id: \.day) { d in
                            BarMark(x: .value("Hari", d.day), y: .value("Menit", d.minutes), width: .ratio(0.55))
                                .foregroundStyle(Color.orange.gradient).cornerRadius(4)
                        }
                        .chartYAxis(.hidden)
                        .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.gray) } }
                        .overlay {
                            if f.last7.allSatisfy({ $0.minutes == 0 }) {
                                Text("Selesaikan 1 sesi fokus untuk mulai streak").font(.system(size: 11)).foregroundStyle(.gray)
                            }
                        }
                    }
                }
            }
        }
    }

    func stat(_ icon: String, _ color: Color, _ value: String, _ label: String) -> some View {
        NCard(padding: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(color)
                    .frame(width: 32, height: 32).background(color.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(label).font(.system(size: 10)).foregroundStyle(.gray)
                }
            }
        }
    }
}

struct AIView: View {
    @ObservedObject var ai: AIModel

    var body: some View {
        if ai.clis.isEmpty {
            Placeholder(icon: "sparkles", title: "Belum ada CLI AI", subtitle: "Pasang Claude Code atau Kiro CLI", color: .purple)
        } else {
            VStack(spacing: 10) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if ai.chat.isEmpty {
                                Placeholder(icon: "sparkles", title: "Tanya \(ai.selected)",
                                            subtitle: "Percakapan berlanjut sampai kamu mulai yang baru (✎)", color: .purple)
                                    .frame(height: 170)
                            }
                            ForEach(ai.chat) { x in
                                Text(x.prompt).font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing),
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(.purple)
                                        .frame(width: 22, height: 22).background(Color.purple.opacity(0.2), in: Circle())
                                    if x.answer.isEmpty {
                                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("\(ai.selected) berpikir…").foregroundStyle(.gray) }
                                            .font(.system(size: 12)).padding(.top, 3)
                                    } else {
                                        Text((try? AttributedString(markdown: x.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(x.answer))
                                            .font(.system(size: 12)).foregroundStyle(x.failed ? .red : .white.opacity(0.92))
                                            .lineSpacing(2)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.top, 3)
                                            .contextMenu { Button("Salin jawaban") { copyText(x.answer) } }
                                    }
                                }
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                    }
                    .onChange(of: ai.chat.map(\.answer)) { _ in withAnimation { proxy.scrollTo("end") } }
                }
                HStack(spacing: 8) {
                    Picker("", selection: $ai.selected) { ForEach(ai.clis, id: \.name) { Text($0.name).tag($0.name) } }
                        .labelsHidden().fixedSize().controlSize(.small)
                    HStack(spacing: 6) {
                        TextField("Tanya \(ai.selected)…", text: $ai.prompt).textFieldStyle(.plain).onSubmit { ai.ask() }
                        if ai.running {
                            Button { ai.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 20)) }.buttonStyle(.plain).help("Hentikan")
                        } else {
                            Button { ai.ask() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundStyle(.purple) }
                                .buttonStyle(.plain).disabled(ai.prompt.isEmpty).opacity(ai.prompt.isEmpty ? 0.4 : 1)
                        }
                    }
                    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
                    .background(Color.white.opacity(0.09), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                    NButton(icon: "square.and.pencil") { ai.reset() }.help("Percakapan baru")
                }
            }
        }
    }
}

func copyText(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct ClipView: View {
    @ObservedObject var c: ClipboardModel
    @State private var query = ""
    @State private var copied: UUID?

    var body: some View {
        let shown = c.items.filter { query.isEmpty || ($0.text ?? $0.ocr ?? "").localizedCaseInsensitiveContains(query) }
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                    TextField("Cari, termasuk teks di dalam gambar", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                NButton(icon: "trash", title: "Bersihkan") { c.clear() }.help("Hapus semua kecuali yang di-pin")
            }
            if shown.isEmpty {
                Placeholder(icon: "doc.on.clipboard", title: c.items.isEmpty ? "Clipboard kosong" : "Tidak ada yang cocok",
                            subtitle: c.items.isEmpty ? "Teks dan gambar yang kamu copy muncul di sini" : nil, color: .teal)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(shown) { item in row(item) }
                    }
                }
            }
        }
    }

    func row(_ item: Clip) -> some View {
        HoverRow { hover in
            HStack(spacing: 10) {
                Group {
                    if let img = c.thumb(item) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "text.alignleft").font(.system(size: 11, weight: .semibold)).foregroundStyle(.teal)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.teal.opacity(0.15))
                    }
                }
                .frame(width: 40, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(copied == item.id ? "Disalin ✓" : (item.text ?? (item.ocr?.isEmpty == false ? item.ocr! : "Gambar")))
                        .font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(copied == item.id ? .green : .white)
                    if item.image != nil { Text(item.ocr?.isEmpty == false ? "Gambar · teks terbaca" : "Gambar").font(.system(size: 9.5)).foregroundStyle(.gray) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hover || item.pinned {
                    Button { c.togglePin(item) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }
                        .buttonStyle(.plain).foregroundStyle(item.pinned ? .yellow : .gray).help("Pin")
                }
                if hover {
                    Button { c.delete(item) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.gray)
                }
            }
            .font(.system(size: 11))
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            c.copy(item)
            copied = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if copied == item.id { copied = nil } }
        }
    }
}

struct ShelfView: View {
    @ObservedObject var s: Shelf
    let dropping: Bool

    var body: some View {
        if s.files.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 22, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background((dropping ? Color.blue : Color.white.opacity(0.1)).gradient, in: Circle())
                Text(dropping ? "Lepas untuk menyimpan" : "Seret file ke notch").font(.system(size: 13, weight: .semibold))
                Text("Simpan sementara, lalu seret keluar atau kirim lewat AirDrop").font(.system(size: 11)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(dropping ? Color.blue : Color.white.opacity(0.2)))
            .animation(.easeInOut(duration: 0.15), value: dropping)
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(s.files, id: \.self) { url in tile(url) }
                    }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    Text("\(s.files.count) file · seret keluar untuk memindahkan").font(.system(size: 10.5)).foregroundStyle(.gray)
                    Spacer()
                    NButton(icon: "xmark", title: "Kosongkan") { s.files = [] }
                    NButton(icon: "dot.radiowaves.left.and.right", title: "AirDrop", tint: .blue, prominent: true) { s.airDrop(s.files) }
                }
            }
        }
    }

    func tile(_ url: URL) -> some View {
        HoverRow { hover in
            VStack(spacing: 6) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 56, height: 56)
                Text(url.lastPathComponent).font(.system(size: 10, weight: .medium)).lineLimit(2).multilineTextAlignment(.center).frame(width: 84)
            }
            .padding(6)
            .overlay(alignment: .topTrailing) {
                if hover {
                    Button { s.files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)) }
                        .buttonStyle(.plain).foregroundStyle(.white, .gray)
                }
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("AirDrop") { s.airDrop([url]) }
            Button("Tampilkan di Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}

struct StatsView: View {
    @ObservedObject var s: SystemModel

    var body: some View {
        let b = Battery.read(), mem = s.memUsed / s.memTotal, disk = s.diskTotal > 0 ? 1 - s.diskFree / s.diskTotal : 0
        HStack(spacing: 10) {
            stat("Baterai", "battery.75percent", Double(b.percent) / 100, b.percent <= 20 ? .red : .green, b.ac ? "dicas" : "tidak dicas")
            stat("CPU", "cpu", s.cpu, level(s.cpu), "\(ProcessInfo.processInfo.activeProcessorCount) core")
            stat("Memori", "memorychip", mem, level(mem), "\(bytes(s.memTotal - s.memUsed)) sisa")
            stat("Disk", "internaldrive", disk, level(disk), "\(bytes(s.diskFree)) bebas")
        }
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }

    func stat(_ title: String, _ icon: String, _ v: Double, _ color: Color, _ caption: String) -> some View {
        NCard {
            VStack(spacing: 8) {
                Label(title, systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.gray)
                Ring(value: v, color: color, label: "\(Int(v * 100))%", size: 92, line: 9)
                Text(caption).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct GitView: View {
    @ObservedObject var g: GitModel
    @ObservedObject var pr: PRModel
    let ai: AIModel
    @AppStorage("gitPane") private var showPR = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    pane("Repo", count: g.repos.count, on: !showPR) { showPR = false }
                    pane("Pull Request", count: pr.prs.count, on: showPR) { showPR = true; if pr.prs.isEmpty { pr.refresh(repos: g.repos.map(\.path)) } }
                }
                .padding(2)
                .background(Color.white.opacity(0.07), in: Capsule())
                Spacer()
                if showPR {
                    if pr.loading { ProgressView().controlSize(.small) }
                    NButton(icon: "arrow.clockwise") { pr.refresh(repos: g.repos.map(\.path)) }.help("Muat ulang PR")
                } else {
                    NButton(icon: "arrow.clockwise") { g.refresh() }.help("Segarkan status")
                    NButton(icon: "plus", title: "Tambah repo") { g.add() }
                }
            }
            if showPR { PRPane(pr: pr, ai: ai) } else { repoList }
        }
        .onAppear { g.refresh() }
    }

    func pane(_ title: String, count: Int, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { run() } }) {
            HStack(spacing: 5) {
                Text(title)
                if count > 0 { Text("\(count)").font(.system(size: 9.5, weight: .bold)).padding(.horizontal, 5).background(Color.white.opacity(0.18), in: Capsule()) }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(on ? Color.white : Color.gray)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(on ? Color.indigo.opacity(0.9) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var repoList: some View {
        if g.repos.isEmpty {
            Placeholder(icon: "arrow.triangle.branch", title: "Belum ada repo", subtitle: "Klik Tambah repo untuk memantau branch dan perubahan", color: .indigo)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(g.repos) { r in repoRow(r) }
                }
            }
        }
    }

    func repoRow(_ r: Repo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(.indigo)
                .frame(width: 34, height: 34).background(Color.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(r.name).font(.system(size: 13, weight: .semibold))
                    Chip(text: r.status.branch, icon: "arrow.triangle.branch", color: .purple)
                }
                HStack(spacing: 6) {
                    Chip(text: r.status.changes == 0 ? "bersih" : "\(r.status.changes) berubah", icon: r.status.changes == 0 ? "checkmark" : "pencil",
                         color: r.status.changes > 0 ? .orange : .green)
                    if r.status.ahead > 0 { Chip(text: "\(r.status.ahead)", icon: "arrow.up", color: .green) }
                    if r.status.behind > 0 { Chip(text: "\(r.status.behind)", icon: "arrow.down", color: .blue) }
                    if !r.message.isEmpty {
                        Text(r.message).font(.system(size: 10)).foregroundStyle(r.message.hasPrefix("Gagal") ? .red : .gray).lineLimit(1)
                    }
                }
            }
            Spacer()
            if r.busy {
                ProgressView().controlSize(.small)
            } else {
                NButton(icon: "arrow.triangle.2.circlepath") { g.run(r, "fetch") }.help("Fetch")
                NButton(icon: "arrow.down") { g.run(r, "pull") }.help("Pull (fast-forward)")
                NButton(icon: "arrow.up") { g.run(r, "push") }.help("Push")
            }
            Menu {
                Button("Buka di Terminal") { g.open(r, app: "com.apple.Terminal") }
                Button("Buka di VS Code") { g.open(r, app: "com.microsoft.VSCode") }
                Button("Tampilkan di Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) }
                Divider()
                Button("Hapus dari daftar") { g.remove(r) }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PRPane: View {
    @ObservedObject var pr: PRModel
    let ai: AIModel
    @State private var editing = false

    var body: some View {
        if !pr.error.isEmpty && pr.prs.isEmpty {
            Placeholder(icon: "exclamationmark.triangle.fill", title: "Tidak bisa memuat PR", subtitle: pr.error, color: .red)
        } else if pr.prs.isEmpty {
            Placeholder(icon: "checkmark.seal.fill", title: pr.loading ? "Memuat PR…" : "Tidak ada PR terbuka",
                        subtitle: "PR yang minta review-mu, PR milikmu, dan PR di repo yang dipantau", color: .green)
        } else {
            HStack(spacing: 10) {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(pr.prs) { p in listRow(p) }
                    }
                }
                .frame(width: 200)
                detail
            }
        }
    }

    func listRow(_ p: PR) -> some View {
        let on = pr.selected == p
        return Button { pr.select(p) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(verbatim: "\(p.repo.components(separatedBy: "/").last ?? "")#\(p.number)").foregroundStyle(.gray)
                    if p.reviewRequested { Chip(text: "review", color: .purple) }
                    if p.isDraft { Chip(text: "draft") }
                }
                .font(.system(size: 9.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(on ? Color.indigo.opacity(0.35) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Color.indigo : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var detail: some View {
        if let p = pr.selected {
            NCard(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
                            Text(verbatim: "\(p.repo)#\(p.number) · @\(p.author.login)").font(.system(size: 10)).foregroundStyle(.gray)
                        }
                        Spacer()
                        NButton(icon: "safari") { NSWorkspace.shared.open(URL(string: p.url)!) }.help("Buka di browser")
                    }
                    if let d = pr.detail {
                        HStack(spacing: 5) {
                            switch d.checks {
                            case "pass": Chip(text: "CI lulus", icon: "checkmark.circle.fill", color: .green)
                            case "fail": Chip(text: "CI gagal", icon: "xmark.circle.fill", color: .red)
                            case "pending": Chip(text: "CI berjalan", icon: "clock.fill", color: .yellow)
                            default: EmptyView()
                            }
                            Chip(text: "+\(d.additions)", color: .green)
                            Chip(text: "−\(d.deletions)", color: .red)
                            Chip(text: "\(d.changedFiles) file")
                            if d.mergeable == "CONFLICTING" { Chip(text: "konflik", icon: "exclamationmark.triangle.fill", color: .orange) }
                        }
                        reviewArea(p, d)
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if !pr.message.isEmpty {
                        Text(pr.message).font(.system(size: 10)).foregroundStyle(pr.message.hasPrefix("Gagal") ? .red : .gray).lineLimit(2)
                    }
                }
            }
        } else {
            NCard {
                Placeholder(icon: "text.magnifyingglass", title: "Pilih PR", subtitle: "Lalu minta AI me-review diff-nya", color: .indigo)
            }
        }
    }

    @ViewBuilder func reviewArea(_ p: PR, _ d: PRDetail) -> some View {
        if pr.reviewing {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("AI sedang membaca diff…").font(.system(size: 11)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pr.review.isEmpty {
            VStack(spacing: 8) {
                NButton(icon: "sparkles", title: "Review dengan AI", tint: .purple, prominent: true) { pr.aiReview(ai) }
                Text("Diff dikirim ke Claude tanpa akses tool apa pun").font(.system(size: 9.5)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Group {
                if editing {
                    TextEditor(text: $pr.review).font(.system(size: 11, design: .monospaced)).scrollContentBackground(.hidden)
                } else {
                    ScrollView {
                        Text((try? AttributedString(markdown: pr.review, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(pr.review))
                            .font(.system(size: 11.5)).lineSpacing(2).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 6) {
                Menu {
                    Button("Komentar") { send(p, "comment", "komentar") }
                    Button("Approve") { send(p, "approve", "approve") }
                    Button("Minta perubahan") { send(p, "request-changes", "permintaan perubahan") }
                } label: { Label("Kirim review", systemImage: "paperplane.fill") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                NButton(icon: editing ? "checkmark" : "pencil") { editing.toggle() }.help(editing ? "Selesai mengedit" : "Edit review")
                NButton(icon: "doc.on.doc") { copyText(pr.review) }.help("Salin review")
                Menu {
                    ForEach([("merge", "Merge commit"), ("squash", "Squash & merge"), ("rebase", "Rebase & merge")], id: \.0) { m in
                        Button(m.1) {
                            if confirm("Merge PR #\(p.number)?", "\(p.repo): \(p.title)\nMetode: \(m.1). Ini tidak bisa dibatalkan dari sini.", "Merge") { pr.merge(m.0) }
                        }
                    }
                } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(d.mergeable != "MERGEABLE" || d.checks == "fail")
                    .help(d.mergeable != "MERGEABLE" ? "PR belum bisa di-merge" : d.checks == "fail" ? "CI gagal" : "Merge PR")
            }
        }
    }

    func send(_ p: PR, _ event: String, _ label: String) {
        if confirm("Kirim \(label) ke PR #\(p.number)?", "Review ini akan terlihat publik di \(p.repo) atas nama akun GitHub-mu.", "Kirim") { pr.post(event) }
    }
}
