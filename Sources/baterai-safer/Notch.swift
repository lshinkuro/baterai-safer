import SwiftUI
import Charts

enum NTab: Int, CaseIterable {
    case home, music, focus, agenda, ai, notes, dev, clipboard, shelf, git, stats, ibadah, more
    var icon: String { ["house.fill", "music.note", "timer", "calendar", "sparkles", "note.text", "curlybraces", "doc.on.clipboard", "tray.full", "arrow.triangle.branch", "gauge.medium", "moon.stars.fill", "square.grid.2x2.fill"][rawValue] }
    var title: String { ["Home", "Musik", "Fokus", "Rapat", "AI", "Catatan", "Dev Utils", "Clipboard", "Shelf", "Git", "Stats", "Ibadah", "Lainnya"][rawValue] }
    var enabled: Bool { FeatureFlags.isOn("\(self)") }

    static let orderKey = "tabOrder"
    static var ordered: [NTab] { orderedTabs(UserDefaults.standard.string(forKey: orderKey) ?? "") }

    /// Dragging an icon in the island (which only sees the tabs that are on); VoiceOver in Tools → Fitur.
    func move(by d: Int, showing: (NTab) -> Bool = { _ in true }) { Self.save(movedTab(Self.ordered, self, by: d, showing: showing)) }

    /// Dragging a chip in Tools → Fitur.
    func place(at target: NTab) { Self.save(placedTab(Self.ordered, self, at: target)) }

    private static func save(_ o: [NTab]) { UserDefaults.standard.set(o.map { "\($0)" }.joined(separator: ","), forKey: orderKey) }
}

/// Takes a tab out and puts it where `target` was; the ones between close the gap.
func placedTab(_ tabs: [NTab], _ t: NTab, at target: NTab) -> [NTab] {
    var o = tabs
    guard let i = o.firstIndex(of: t), let j = o.firstIndex(of: target) else { return o }
    o.insert(o.remove(at: i), at: j)
    return o
}

/// Swaps a tab with its neighbor on that side, stepping over tabs that aren't showing.
func movedTab(_ tabs: [NTab], _ t: NTab, by d: Int, showing: (NTab) -> Bool) -> [NTab] {
    var o = tabs
    guard let i = o.firstIndex(of: t) else { return o }
    var j = i + d
    while o.indices.contains(j), !showing(o[j]) { j += d }
    if o.indices.contains(j) { o.swapAt(i, j) }
    return o
}

/// The saved tab order; tabs it doesn't name (added in a later version) go at the end.
func orderedTabs(_ saved: String) -> [NTab] {
    let s = saved.split(separator: ",").compactMap { n in NTab.allCases.first { "\($0)" == n } }
    return s + NTab.allCases.filter { !s.contains($0) }
}

/// An icon being dragged along a strip of tabs: neighbors swap as it passes them.
struct TabDrag {
    var tab: NTab?
    var offset: CGFloat = 0 // from the slot the icon has swapped into
    private var moved = 0   // slots swapped across so far

    /// `x` is the whole drag so far, in a coordinate space that doesn't move with the icon.
    mutating func update(_ t: NTab, _ x: CGFloat, step: CGFloat, showing: @escaping (NTab) -> Bool) {
        tab = t
        let want = Int((x / step).rounded())
        if want != moved {
            let d = want > moved ? 1 : -1, tabs = NTab.ordered.filter(showing)
            if let i = tabs.firstIndex(of: t), tabs.indices.contains(i + d) {
                withAnimation(Motion.snap) { t.move(by: d, showing: showing) }
                moved += d
            }
        }
        offset = max(-step, min(step, x - CGFloat(moved) * step)) // stops at either end of the strip
    }
}

enum ScrollGesture { case up, down, left, right }

/// Which way the fingers went, whatever the natural-scrolling setting; nil until it's a clear swipe.
func scrollGesture(dx: CGFloat, dy: CGFloat, inverted: Bool) -> ScrollGesture? {
    guard max(abs(dx), abs(dy)) >= 30 else { return nil }
    let sign: CGFloat = inverted ? 1 : -1
    return abs(dx) > abs(dy) ? (dx * sign > 0 ? .right : .left) : (dy * sign > 0 ? .down : .up)
}

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var mini = false             // mini music player below the notch (scroll down)
    @Published var pinned = false           // stays open when the pointer leaves
    @Published var tab = NTab.home
    @Published var toast: String?           // short message dropped below the notch
    var toastIcon = "checkmark.circle.fill"
    var notch = CGSize(width: 185, height: 32)
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true } // lets text fields in the island take typing
}

/// Island window at the top-center of the notched (or main) screen. It ignores clicks while
/// collapsed, so the menu bar under it keeps working; hovering the notch expands it.
final class Notch {
    static let shared = Notch()
    static let size = CGSize(width: 760, height: 340) // window; the visible island is smaller
    let state = NotchState()
    let media = NowPlaying(), focus = Focus(), clips = ClipboardModel(), shelf = Shelf(), sys = SystemModel()
    let git = GitModel(), ai = AIModel(), pr = PRModel(), notes = NotesModel(), meet = MeetingModel()
    private var panel: NotchPanel?
    private var monitors: [Any] = []
    private var heldOpen = false              // opened by shortcut: stay open until the mouse visits and leaves
    private var previous: NSRunningApplication? // gets keyboard focus back when the island closes
    private var meetingTimer: Timer?
    private var meetingPause = MeetingPause()
    private var fullCharge = FullChargeAlert()
    private var scrollSum = CGSize.zero
    private var scrollLocked = Date.distantPast
    /// Open on click instead of hover (Tools → Fitur).
    static var clickToOpen: Bool { UserDefaults.standard.bool(forKey: "notchClick") }

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
        p.contentView = NSHostingView(rootView: NotchView(state: state, media: media, focus: focus, ai: ai, meet: meet,
                                                          clips: clips, shelf: shelf, sys: sys, git: git, pr: pr, notes: notes))
        p.orderFrontRegardless()
        panel = p

        // Mouse-move monitoring needs no Accessibility permission (only key monitoring does).
        let handle: (NSEvent) -> Void = { [weak self] e in self?.track(dragging: e.type == .leftMouseDragged) }
        monitors = [NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handle),
                    NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.scrolled(e) },
                    NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.scrolled(e); return e },
                    NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in self?.focusTextField(e); return e },
                    // While collapsed the panel ignores the mouse, so clicks reach other apps; watch them globally.
                    NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.click() },
                    NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { handle($0); return $0 },
                    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                        guard e.keyCode == 53, let self, self.state.expanded else { return e } // Esc closes
                        self.set(false)
                        return nil
                    }].compactMap { $0 }
        HotKeys.register()
        applyFeatures()
        Volumes.shared.start()
        if UserDefaults.standard.bool(forKey: "downloadAlert") { Downloads.shared.start() }
        meetingTimer = .scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.checkMeeting(); self?.checkCharge() }
    }

    func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        HotKeys.unregister()
        meetingTimer?.invalidate()
        meetingTimer = nil
        Downloads.shared.stop()
        meet.stop()
        media.stop()
        clips.stop()
    }

    private var areas: (hot: NSRect, open: NSRect, mini: NSRect)? {
        guard let panel else { return nil }
        let f = panel.frame, n = state.notch, o = NotchView.open, m = NotchView.mini(n)
        return (NSRect(x: f.midX - n.width / 2 - 50, y: f.maxY - n.height - 4, width: n.width + 100, height: n.height + 4),
                NSRect(x: f.midX - o.width / 2, y: f.maxY - o.height, width: o.width, height: o.height).insetBy(dx: -14, dy: -14),
                NSRect(x: f.midX - m.width / 2, y: f.maxY - m.height, width: m.width, height: m.height).insetBy(dx: -14, dy: -14))
    }

    private func track(dragging: Bool) {
        guard let (hot, open, mini) = areas else { return }
        let p = NSEvent.mouseLocation
        if state.mini {
            if !mini.contains(p) { setMini(false) }
            return
        }
        // Dragging a file in opens straight to the shelf, in either mode.
        if !state.expanded, hot.contains(p), dragging || !Self.clickToOpen {
            if dragging && NTab.shelf.enabled { state.tab = .shelf }
            set(true)
        } else if state.expanded, open.contains(p) {
            heldOpen = false
        } else if state.expanded, !heldOpen, !Self.clickToOpen, !state.pinned, !dragging { // closing mid-drag cancels a file dragged out of the shelf
            set(false)
        }
    }

    /// Over the notch: down opens the mini player, up goes from it to the full island, left/right change track.
    private func scrolled(_ e: NSEvent) {
        guard e.momentumPhase.isEmpty, NTab.music.enabled, let (hot, _, mini) = areas,
              (state.mini ? mini : hot).contains(NSEvent.mouseLocation) else { return }
        if e.phase == .began { scrollSum = .zero }
        let scale: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 10 // a mouse wheel reports lines, not points
        scrollSum.width += e.scrollingDeltaX * scale
        scrollSum.height += e.scrollingDeltaY * scale
        guard Date() > scrollLocked else { scrollSum = .zero; return }
        guard let g = scrollGesture(dx: scrollSum.width, dy: scrollSum.height, inverted: e.isDirectionInvertedFromDevice) else { return }
        scrollSum = .zero
        scrollLocked = Date().addingTimeInterval(0.7) // one swipe, one action
        switch g {
        case .left: media.send("previous track")
        case .right: media.send("next track")
        case .down:
            guard !state.mini else { return }
            guard media.app != nil, !media.title.isEmpty else { flash("Tidak ada musik", icon: "music.note"); return }
            if state.expanded { set(false) }
            setMini(true)
        case .up:
            guard state.mini else { return }
            state.tab = .music
            set(true)
        }
    }

    private func setMini(_ on: Bool) {
        withAnimation(Motion.snap) { state.mini = on }
        panel?.ignoresMouseEvents = !on
    }

    /// A non-activating panel doesn't get the keyboard from a plain click, so typing would go to the app in front.
    private func focusTextField(_ e: NSEvent) {
        guard let panel, e.window === panel, state.expanded else { return }
        let hit = panel.contentView?.hitTest(e.locationInWindow)
        guard hit is NSTextField || hit is NSTextView else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
    }

    /// Click mode: a click on the notch opens it, a click anywhere outside the island closes it.
    private func click() {
        guard Self.clickToOpen, let (hot, open, _) = areas else { return }
        let p = NSEvent.mouseLocation
        if !state.expanded, hot.contains(p) { set(true) } else if state.expanded, !open.contains(p), !state.pinned { set(false) }
    }

    /// ⌃⌥S: start or pause a focus session without opening the island.
    func toggleFocus() {
        guard NTab.focus.enabled else { return }
        focus.toggle()
        let task = focus.intention.trimmingCharacters(in: .whitespaces)
        flash(focus.running ? (focus.onBreak ? "Istirahat dimulai" : "Fokus dimulai" + (task.isEmpty ? "" : " · \(task)")) : "Dijeda · \(focus.clock)")
    }

    /// "Unplug" cue when the battery reaches the charge limit (Lainnya → Notif baterai penuh).
    private func checkCharge() {
        guard UserDefaults.standard.object(forKey: "fullChargeAlert") as? Bool ?? true else { return }
        let b = Battery.read(), limit = load(Paths.config, Config()).limit
        if fullCharge.step(percent: b.percent, ac: b.ac, target: limit) {
            flash(fullChargeMessage(percent: b.percent))
            NSSound(named: "Glass")?.play()
        }
    }

    /// ⌃⌥M: mute or unmute the default microphone for every app.
    func toggleMic() {
        guard let on = AudioSwitch.mic.toggle() else { flash("Tidak ada mikrofon"); return }
        flash(on ? "Mic dibisukan" : "Mic aktif")
    }

    /// Pauses focus when a calendar meeting starts and, once it ends, points at ⌃⌥S to resume.
    private func checkMeeting() {
        let now = Date(), m = meet.next
        let live = m.flatMap { $0.start <= now && now < $0.end ? $0.start : nil }
        switch meetingPause.step(meeting: live, focusing: focus.running && !focus.onBreak) {
        case .pause:
            focus.toggle()
            flash("Fokus dijeda · \(m?.title ?? "rapat") dimulai")
        case .offerResume: flash("Rapat selesai · ⌃⌥S untuk lanjut fokus")
        case .none: break
        }
    }

    /// Starts or stops each feature's background work to match the user's switches.
    func applyFeatures() {
        guard panel != nil else { return }
        if NTab.clipboard.enabled { clips.start() } else { clips.stop() }   // pasteboard check every 0.5 s
        // These ask for permissions (Automation, Calendar, Location, Notifications): wait for the welcome screen.
        if Onboarding.done {
            if NTab.music.enabled { media.start() } else { media.stop() }   // AppleScript poll every second
            if FeatureFlags.isOn("meeting") { meet.start() } else { meet.stop() }
            if NTab.ibadah.enabled { Ibadah.shared.start() } else { Ibadah.shared.stop() } // reminders
        }
        if !state.tab.enabled, let first = NTab.ordered.first(where: \.enabled) { state.tab = first }
    }

    /// Select an area of the screen; its text lands on the clipboard.
    func ocr() {
        if state.expanded { set(false) }
        captureText { text in
            self.flash(text.isEmpty ? "Tidak ada teks terbaca" : "Teks disalin · \(text.split(separator: "\n").count) baris")
        }
    }

    func flash(_ message: String, icon: String = "checkmark.circle.fill", seconds: Double = 2.5) {
        state.toastIcon = icon
        withAnimation(Motion.snap) { state.toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if self.state.toast == message { withAnimation(Motion.ease) { self.state.toast = nil } }
        }
    }

    /// Shortcut: open on `tab` (nil keeps the current one), or close if already showing it.
    func toggle(_ tab: NTab?) {
        guard panel != nil, tab?.enabled != false else { return }
        if state.expanded && (tab == nil || state.tab == tab) { set(false); return }
        if let tab { state.tab = tab }
        if !state.expanded { set(true) }
        heldOpen = true
        // Take keyboard focus so the AI / clipboard fields can be typed into right away.
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previous = front }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private func set(_ open: Bool) {
        withAnimation(Motion.snap) { state.expanded = open; if open { state.mini = false } }
        panel?.ignoresMouseEvents = !open
        if open {
            if let front = NSWorkspace.shared.frontmostApplication, front != .current { previous = front }
        } else {
            heldOpen = false
            // Typing went to the island; hand focus back to the app the user was in.
            if NSApp.isActive || panel?.isKeyWindow == true { previous?.activate() }
            previous = nil
        }
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
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.045), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}

/// The system tooltip needs an active window, and the island usually isn't one.
private struct HoverTip: ViewModifier {
    let text: String
    @Local private var hover = false

    func body(content: Content) -> some View {
        content
            .onHover { hover = $0 }
            .overlay(alignment: .top) {
                if hover {
                    Text(tr(text)).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color(white: 0.2), in: Capsule())
                        .offset(y: -24)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(Motion.ease, value: hover)
            .accessibilityLabel(tr(text))
    }
}

extension View {
    func hoverTip(_ text: String) -> some View { modifier(HoverTip(text: text)) }
}

struct NButton: View {
    let icon: String
    var title: String?
    var tint: Color = .white
    var prominent = false
    let run: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                if let title { Text(tr(title)).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(prominent ? Palette.onAccent : tint)
            .padding(.horizontal, title == nil ? 0 : 11)
            .frame(minWidth: 28, minHeight: 28)
            .background(prominent ? AnyShapeStyle(Palette.accent.opacity(hover ? 0.85 : 1)) : AnyShapeStyle(Color.white.opacity(hover ? 0.14 : 0.08)), in: Capsule())
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
            Text(tr(text))
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.16), in: Capsule())
    }
}

struct Placeholder: View {
    let icon: String, title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
            Text(tr(title)).font(.system(size: 13, weight: .semibold))
            if let subtitle { Text(tr(subtitle)).font(.system(size: 11)).foregroundStyle(.gray).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Equalizer: View {
    var color: Color = Palette.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: Motion.reduced)) { ctx in
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
    static let open = CGSize(width: 720, height: 300)
    static func mini(_ n: CGSize) -> CGSize { CGSize(width: n.width + 210, height: n.height + 66) }
    @ObservedObject var state: NotchState
    @ObservedObject var media: NowPlaying
    @ObservedObject var focus: Focus
    @ObservedObject var ai: AIModel
    @ObservedObject var meet: MeetingModel
    let clips: ClipboardModel, shelf: Shelf, sys: SystemModel, git: GitModel, pr: PRModel, notes: NotesModel
    @Local private var dropping = false
    @Local private var drag = TabDrag()
    @Namespace private var ns
    @AppStorage(FeatureFlags.key) private var featuresOff = "" // re-render when features change
    @AppStorage(NTab.orderKey) private var tabOrder = ""
    @AppStorage("accent") private var accentID = "mint"

    var soon: Meeting? { meet.next.flatMap { $0.isSoon(Date()) ? $0 : nil } }
    var live: Bool { media.playing || focus.running || ai.running || soon != nil }
    /// The focus intention, shown beside the camera while it's the live activity on display.
    var task: String {
        guard focus.running, !focus.onBreak, !ai.running, soon == nil else { return "" }
        return focus.intention.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        let n = state.notch
        let radius: CGFloat = state.expanded ? 26 : state.mini ? 18 : 10
        let size = state.expanded ? Self.open
            : state.mini ? Self.mini(n)
            : state.toast != nil ? CGSize(width: n.width + 200, height: n.height + 30)
            : CGSize(width: n.width + (live ? 96 : 0) + (task.isEmpty ? 0 : 160), height: n.height)
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
            .clipShape(NotchShape(radius: radius))
            .overlay(NotchShape(radius: radius).stroke(Color.white.opacity(state.expanded ? 0.08 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(state.expanded ? 0.55 : 0), radius: 18, y: 8)

            // Sized and clipped out here, so content on its way out shrinks with the island.
            ZStack(alignment: .top) {
                if state.expanded {
                    expanded(n)
                        .id(accentID)
                        .frame(width: Self.open.width, height: Self.open.height)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if state.mini {
                    MiniPlayer(m: media)
                        .frame(width: size.width, height: size.height - n.height)
                        .padding(.top, n.height)
                        .foregroundStyle(.white)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        if live { collapsed.frame(width: size.width, height: n.height) } else if state.toast != nil { Color.clear.frame(height: n.height) }
                        if let t = state.toast {
                            // A check means "done" (green); anything else is a nudge, in the accent.
                            Label(tr(t), systemImage: state.toastIcon).font(.system(size: 12, weight: .bold))
                                .foregroundStyle(state.toastIcon == "checkmark.circle.fill" ? Palette.green : Palette.accent).lineLimit(1).frame(height: 26)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(NotchShape(radius: radius))
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
                    Image(systemName: "sparkles").foregroundStyle(Palette.accent)
                } else if let m = soon {
                    Image(systemName: m.link == nil ? "calendar" : "video.fill").foregroundStyle(Color(nsColor: m.color ?? .systemBlue))
                } else if focus.running {
                    HStack(spacing: 6) {
                        Image(systemName: "timer").foregroundStyle(Palette.accent)
                        if !task.isEmpty { Text(task).lineLimit(1).foregroundStyle(.white.opacity(0.85)) }
                    }
                } else if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "music.note").foregroundStyle(Palette.accent)
                }
            }
            .frame(width: task.isEmpty ? 22 : 110, alignment: .leading)
            Spacer()
            if ai.running {
                ProgressView().controlSize(.mini).tint(Palette.accent)
            } else if let m = soon {
                Text(m.start <= Date() ? "live" : m.when(Date()).replacingOccurrences(of: " lagi", with: ""))
                    .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Palette.accent)
            } else if focus.running {
                Text(focus.clock).font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(Palette.accent)
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
                    let tabs = NTab.ordered.filter(\.enabled)
                    // Narrow the buttons when many tabs are on, so none slide under the camera housing.
                    let w = min(26, ((Self.open.width - n.width) / 2 - 26) / CGFloat(max(tabs.count, 1)) - 1)
                    ForEach(tabs, id: \.self) { t in
                        let on = state.tab == t, grabbed = drag.tab == t
                        Button { withAnimation(Motion.snap) { state.tab = t } } label: {
                            PinchIcon(icon: t.icon, color: on ? Palette.onAccent : Color.gray, grabbed: grabbed)
                                .frame(width: w, height: 22)
                                .background {
                                    if on { Capsule().fill(Palette.accent).matchedGeometryEffect(id: "tab", in: ns) }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).tip(t.title)
                        .offset(x: grabbed ? drag.offset : 0)
                        .zIndex(grabbed ? 1 : 0)
                        // Press and slide: the icon pops up and neighbors swap as it passes them.
                        .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("tabs"))
                            .onChanged { drag.update(t, $0.translation.width, step: w + 1, showing: \.enabled) }
                            .onEnded { _ in withAnimation(Motion.snap) { drag = TabDrag() } })
                    }
                }
                .coordinateSpace(name: "tabs")
                .padding(2)
                .background(Color.white.opacity(0.07), in: Capsule())
                Spacer(minLength: n.width + 12)
                HStack(spacing: 8) {
                    if let m = meet.next, m.start.timeIntervalSinceNow < 3600 {
                        MeetingChip(m: m) { meet.join() } // takes the title's place; there isn't room for all
                        QuickToggles(state: state, micOnly: true)
                    } else {
                        Text(tr(state.tab.title)).font(.system(size: 12, weight: .bold)).lineLimit(1)
                        QuickToggles(state: state)
                    }
                    if NTab.more.enabled { UpdateChip(state: state) }
                    Button { state.pinned.toggle() } label: {
                        Image(systemName: state.pinned ? "pin.fill" : "pin").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(state.pinned ? Palette.accent : Color.gray)
                            .frame(width: 20, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).tip(state.pinned ? "Lepas kunci" : "Kunci agar tidak tertutup otomatis")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(n.height, 30))
            .padding(.horizontal, 18)

            Group {
                switch state.tab {
                case .home: HomeView(m: media, f: focus)
                case .music: MusicView(m: media)
                case .focus: FocusView(f: focus, n: notes)
                case .agenda: AgendaView()
                case .ai: AIView(ai: ai)
                case .notes: NotesView(n: notes, ai: ai)
                case .dev: DevView()
                case .clipboard: ClipView(c: clips)
                case .shelf: ShelfView(s: shelf, dropping: dropping)
                case .git: GitView(g: git, pr: pr, ai: ai)
                case .stats: StatsView(s: sys)
                case .ibadah: IbadahView()
                case .more: MoreView()
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

/// Lifts under the pointer with a little spring, like the Dock; further while it's being dragged.
struct PinchIcon: View {
    let icon: String
    let color: Color
    var grabbed = false
    @Local private var hover = false

    var body: some View {
        Image(systemName: icon).font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .scaleEffect(grabbed ? 1.45 : hover ? 1.28 : 1)
            .animation(Motion.snap, value: hover)
            .animation(Motion.snap, value: grabbed)
            .onHover { hover = $0 }
    }
}

/// Mic, speaker and camera switches beside the camera housing.
struct QuickToggles: View {
    @ObservedObject var state: NotchState
    var micOnly = false
    @AppStorage("morePage") private var morePage = ""
    @Local private var tick = 0 // shows a tap right away instead of at the next timeline beat

    var body: some View {
        // Polled because ⌃⌥M and other apps change these too.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 0) {
                let mic = AudioSwitch.mic.muted, speaker = AudioSwitch.speaker.muted
                button(mic ? "mic.slash.fill" : "mic.fill", mic ? "Aktifkan mic" : "Bisukan mic", mic ? Palette.red : .gray) {
                    Notch.shared.toggleMic(); tick += 1
                }
                if !micOnly {
                    button(speaker ? "speaker.slash.fill" : "speaker.wave.2.fill", speaker ? "Aktifkan speaker" : "Bisukan speaker", speaker ? Palette.red : .gray) {
                        if AudioSwitch.speaker.toggle() == nil { Notch.shared.flash("Speaker ini tidak bisa dibisukan", icon: "speaker.slash.fill") }
                        tick += 1
                    }
                    if NTab.more.enabled { camera }
                }
            }
        }
        .id(tick)
    }

    // macOS has no switch that turns the camera off for every app; this one is Poni's own mirror.
    var camera: some View {
        let on = state.tab == .more && morePage == "camera"
        return button("video.fill", on ? "Matikan kamera" : "Nyalakan kamera", on ? Palette.accent : .gray) {
            if on { morePage = "" } else { morePage = "camera"; state.tab = .more }
        }
    }

    func button(_ icon: String, _ tip: String, _ color: Color, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                .frame(width: 20, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).tip(tip)
    }
}

func mmss(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

// MARK: Tabs

struct AlbumArt: View {
    @ObservedObject var m: NowPlaying
    var size: CGFloat
    var radius: CGFloat = 10

    var body: some View {
        Group {
            if let art = m.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.23)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

func musicControl(_ icon: String, _ size: CGFloat, _ name: String, tint: Color = .white, _ run: @escaping () -> Void) -> some View {
    Button(action: run) { Image(systemName: icon).font(.system(size: size)).foregroundStyle(tint).frame(width: 36, height: 30).contentShape(Rectangle()) }
        .buttonStyle(.plain).tip(name)
}

/// Scrolled down from the notch; moving the pointer away closes it.
struct MiniPlayer: View {
    @ObservedObject var m: NowPlaying

    var body: some View {
        HStack(spacing: 10) {
            AlbumArt(m: m, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(m.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                musicControl("backward.fill", 13, "Sebelumnya") { m.send("previous track") }
                musicControl(m.playing ? "pause.fill" : "play.fill", 18, m.playing ? "Jeda" : "Putar") { m.togglePlay() }
                musicControl("forward.fill", 13, "Berikutnya") { m.send("next track") }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct MusicView: View {
    @ObservedObject var m: NowPlaying
    @Local private var scrub: Double? // 0...1 while the progress bar is being dragged
    @Local private var readingLyrics = false // pointer over the lyrics: don't scroll them away

    var body: some View {
        if m.app == nil || m.title.isEmpty {
            let players = NowPlaying.installed
            VStack(spacing: 14) {
                Placeholder(icon: "music.note", title: m.app == nil ? "Tidak ada musik" : "\(m.app!) dijeda",
                            subtitle: players.isEmpty ? "Pasang Spotify atau Apple Music" : "Lanjutkan lagu terakhir langsung dari sini")
                    .frame(height: 140)
                HStack(spacing: 8) {
                    ForEach(players, id: \.id) { p in
                        NButton(icon: "play.fill", title: String(format: tr("Putar di %@"), p.name), tint: Palette.accent, prominent: p.id == players.first?.id) { m.play(p.id) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let pos = scrub.map { $0 * m.duration } ?? m.now(ctx.date)
                let i = m.lyrics.lastIndex { $0.t <= pos + 0.3 }
                HStack(spacing: 18) {
                    AlbumArt(m: m, size: 150, radius: 16)
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 6)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.title).font(.system(size: 18, weight: .bold)).lineLimit(1)
                                Text(m.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                            }
                            Spacer()
                            if m.playing { Equalizer(color: .white.opacity(0.8)) }
                        }

                        Group {
                            if m.lyrics.isEmpty {
                                Text(m.lyricsStatus).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                            } else {
                                lyrics(i)
                            }
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18)).frame(height: 4)
                                Capsule().fill(Color.white).frame(width: g.size.width * (m.duration > 0 ? pos / m.duration : 0), height: 4)
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { scrub = min(1, max(0, $0.location.x / g.size.width)) }
                                .onEnded { _ in
                                    if let scrub { m.seek(scrub * m.duration) }
                                    scrub = nil
                                })
                        }
                        .frame(height: 12)
                        HStack {
                            Text(mmss(pos))
                            Spacer()
                            Text("-" + mmss(max(0, m.duration - pos)))
                        }
                        .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 2)

                        HStack(spacing: 18) {
                            musicControl("shuffle", 13, m.shuffle ? "Matikan acak" : "Putar acak", tint: m.shuffle ? Palette.accent : .gray) { m.toggleShuffle() }
                            musicControl("backward.fill", 17, "Sebelumnya") { m.send("previous track") }
                            musicControl(m.playing ? "pause.fill" : "play.fill", 26, m.playing ? "Jeda" : "Putar") { m.togglePlay() }
                            musicControl("forward.fill", 17, "Berikutnya") { m.send("next track") }
                            musicControl(m.repeatMode == "one" ? "repeat.1" : "repeat", 13, m.repeatMode == "off" ? "Ulangi semua" : m.repeatMode == "all" ? "Ulangi satu lagu" : "Matikan ulangi",
                                         tint: m.repeatMode == "off" ? .gray : Palette.accent) { m.cycleRepeat() }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    /// Scrollable; clicking a line jumps the song there.
    func lyrics(_ current: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(m.lyrics.indices, id: \.self) { l in
                        Button { m.seek(m.lyrics[l].t) } label: {
                            Text(m.lyrics[l].line.isEmpty ? "♪" : m.lyrics[l].line)
                                .font(.system(size: l == current ? 15 : 12, weight: l == current ? .semibold : .regular))
                                .foregroundStyle(.white.opacity(l == current ? 1 : 0.45))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(l)
                    }
                }
            }
            .onHover { readingLyrics = $0 }
            .onAppear { if let current { proxy.scrollTo(current, anchor: .top) } }
            .onChange(of: current) { i in
                if let i, !readingLyrics { withAnimation(Motion.ease) { proxy.scrollTo(i, anchor: .top) } }
            }
        }
    }
}

struct FocusView: View {
    @ObservedObject var f: Focus
    let n: NotesModel
    @Local private var done = ""

    var body: some View {
        let color: Color = f.onBreak ? Palette.green : Palette.accent
        HStack(spacing: 14) {
            NCard {
                VStack(spacing: 12) {
                    Ring(value: f.remaining / f.total, color: color, label: f.clock, caption: f.onBreak ? (f.longBreak ? "istirahat panjang" : "istirahat") : String(format: tr("fokus %@/4"), "\(f.finished + 1)"), size: 128, line: 10)
                    HStack(spacing: 8) {
                        NButton(icon: "arrow.counterclockwise") { f.reset() }.tip("Ulang")
                        NButton(icon: f.running ? "pause.fill" : "play.fill", title: f.running ? "Jeda" : "Mulai", tint: color, prominent: true) { f.toggle() }
                        NButton(icon: "forward.end.fill") { f.next() }.tip(f.onBreak ? "Lewati istirahat" : "Lewati ke istirahat")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 210)

            if let task = f.reflecting {
                reflection(task)
            } else {
                VStack(spacing: 8) {
                    setup
                    history
                }
            }
        }
    }

    // Intention, length and blocking: set before starting, read-only while a session runs.
    var setup: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "scope").foregroundStyle(Palette.accent)
                    TextField("Mau mengerjakan apa?", text: $f.intention).textFieldStyle(.plain).disabled(f.running)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.09), in: Capsule())
                HStack(spacing: 2) {
                    ForEach(Focus.durations, id: \.self) { m in
                        Button { f.minutes = m } label: {
                            Text("\(m)m").font(.system(size: 11, weight: .bold))
                                .foregroundStyle(f.minutes == m ? Palette.onAccent : Color.gray)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(f.minutes == m ? Palette.accent.opacity(0.9) : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if !Focus.durations.contains(f.minutes) {
                        Text("\(f.minutes)m").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Palette.accent.opacity(0.9), in: Capsule())
                    }
                    // Custom length in 5-minute steps.
                    Stepper("", value: $f.minutes, in: 5...180, step: 5).labelsHidden().controlSize(.mini)
                        .help("Atur durasi sendiri")
                }
                .padding(2)
                .background(Color.white.opacity(0.07), in: Capsule())
                .disabled(f.running).opacity(f.running ? 0.5 : 1)
            }
            HStack(spacing: 8) {
                Toggle("Blokir pengganggu", isOn: $f.blockOn).toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 11, weight: .semibold))
                Menu {
                    let running = NSWorkspace.shared.runningApplications
                        .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
                    ForEach(running, id: \.processIdentifier) { app in
                        if let id = app.bundleIdentifier {
                            Button { toggleBlock(id) } label: {
                                if f.blockApps.contains(id) { Label(app.localizedName ?? id, systemImage: "checkmark") } else { Text(app.localizedName ?? id) }
                            }
                        }
                    }
                } label: {
                    Text("\(f.blockApps.count) aplikasi").font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).fixedSize()
                Spacer()
                if f.blocking { Chip(text: "aktif", icon: "hand.raised.fill", color: Palette.accent) }
            }
        }
    }

    var history: some View {
        NCard(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label("\(f.streak) hari", systemImage: "flame.fill").foregroundStyle(Palette.accent)
                    Label("\(f.today) menit hari ini", systemImage: "clock.fill").foregroundStyle(Palette.accent)
                    Spacer()
                    Text("7 HARI").foregroundStyle(.gray)
                }
                .font(.system(size: 10, weight: .bold))
                Chart(f.last7, id: \.day) { d in
                    BarMark(x: .value("Hari", d.day), y: .value("Menit", d.minutes), width: .ratio(0.55))
                        .foregroundStyle(Palette.accent.gradient).cornerRadius(4)
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

    // After a session: one line of "what got done", saved to the Jurnal Fokus note.
    func reflection(_ task: String) -> some View {
        NCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sesi selesai 🎉").font(.system(size: 15, weight: .bold))
                Text(task.isEmpty ? "\(f.minutes) menit fokus" : "\(task) · \(f.minutes) menit").font(.system(size: 12)).foregroundStyle(.gray)
                TextField("Apa yang selesai?", text: $done).textFieldStyle(.plain).onSubmit(saveReflection)
                    .font(.system(size: 12))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text("Tersimpan di catatan Jurnal Fokus").font(.system(size: 10)).foregroundStyle(.gray)
                    Spacer()
                    NButton(icon: "xmark", title: "Lewati") { f.reflecting = nil; done = "" }
                    NButton(icon: "checkmark", title: "Simpan", tint: Palette.accent, prominent: true, run: saveReflection)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func saveReflection() {
        n.journal(journalLine(f.reflecting ?? "", done, minutes: f.minutes, at: Date()))
        f.reflecting = nil
        done = ""
    }

    func toggleBlock(_ id: String) {
        if let i = f.blockApps.firstIndex(of: id) { f.blockApps.remove(at: i) } else { f.blockApps.append(id) }
    }
}

struct AIView: View {
    @ObservedObject var ai: AIModel
    var windowed = false // shown in AIWindow instead of the notch
    @FocusState private var focused: Bool
    @AppStorage("aiPage") private var page = 0
    @Local private var history = false // notch: saved conversations in place of the chat
    @AppStorage(FeatureFlags.key) private var featuresOff = "" // re-render when the usage page is toggled

    // Pages swap the whole area instead of splitting it, so each keeps the full notch size.
    var body: some View {
        if FeatureFlags.isOn("ailab") {
            VStack(spacing: 10) {
                HStack(spacing: 2) {
                    ForEach(Array(["Chat", "Pemakaian"].enumerated()), id: \.offset) { i, title in
                        Button { withAnimation(Motion.ease) { page = i } } label: {
                            Text(tr(title)).font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(page == i ? Palette.onAccent : Color.gray)
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(page == i ? Palette.accent.opacity(0.9) : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.07), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                switch page {
                case 1: UsagePage(u: UsageModel.shared)
                default: chat
                }
            }
        } else {
            chat
        }
    }

    @ViewBuilder var chat: some View {
        if ai.clis.isEmpty {
            Placeholder(icon: "sparkles", title: "Belum ada CLI AI", subtitle: "Pasang Claude Code atau Kiro CLI")
        } else if windowed {
            HStack(alignment: .top, spacing: 16) {
                AIHistory(ai: ai).frame(width: 230)
                conversation
            }
        } else {
            conversation
        }
    }

    var conversation: some View {
            VStack(spacing: 10) {
                if history && !windowed {
                    AIHistory(ai: ai) { withAnimation(Motion.ease) { history = false } }
                } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if ai.chat.isEmpty {
                                Placeholder(icon: "sparkles", title: String(format: tr("Tanya %@"), ai.selected),
                                            subtitle: "Percakapan berlanjut sampai kamu mulai yang baru (✎)")
                                    .frame(height: 170)
                            }
                            ForEach(ai.chat) { x in
                                Text(x.prompt).font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color.white.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                                        .frame(width: 22, height: 22).background(Palette.accent.opacity(0.2), in: Circle())
                                    if x.answer.isEmpty {
                                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("\(ai.selected) berpikir…").foregroundStyle(.gray) }
                                            .font(.system(size: 12)).padding(.top, 3)
                                    } else {
                                        let parts = x.failed ? (text: x.answer, visual: nil) : extractVisual(x.answer)
                                        VStack(alignment: .leading, spacing: 8) {
                                            if !parts.text.isEmpty {
                                                Text((try? AttributedString(markdown: parts.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(parts.text))
                                                    .font(.system(size: 12)).foregroundStyle(x.failed ? Palette.red : .white.opacity(0.92))
                                                    .lineSpacing(2)
                                                    .textSelection(.enabled)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .contextMenu { Button("Salin jawaban") { copyText(x.answer) } }
                                            }
                                            if let v = parts.visual { VisualCard(v: v, height: windowed ? 380 : 200) }
                                        }
                                        .padding(.top, 3)
                                    }
                                }
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                    }
                    .onChange(of: ai.chat.map(\.answer)) { _ in withAnimation { proxy.scrollTo("end") } }
                }
                }
                HStack(spacing: 8) {
                    Picker("", selection: $ai.selected) { ForEach(ai.clis, id: \.name) { Text($0.name).tag($0.name) } }
                        .labelsHidden().fixedSize().controlSize(.small)
                    NButton(icon: "paintbrush.pointed", title: "Visual", tint: ai.visual ? Palette.accent : .white, prominent: ai.visual) { ai.visual.toggle() }
                        .tip("Minta AI menggambar: diagram, chart, flowchart, ikon (SVG)")
                    HStack(spacing: 6) {
                        TextField(ai.visual ? "Gambarkan… mis. flowchart login" : "Tanya \(ai.selected)…", text: $ai.prompt).textFieldStyle(.plain).onSubmit { ai.ask() }
                            .focused($focused).onAppear { focused = true }
                        if ai.running {
                            Button { ai.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 20)) }.buttonStyle(.plain).tip("Hentikan")
                        } else {
                            Button { ai.ask() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.accent) }
                                .buttonStyle(.plain).tip("Kirim").disabled(ai.prompt.isEmpty).opacity(ai.prompt.isEmpty ? 0.4 : 1)
                        }
                    }
                    .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
                    .background(Color.white.opacity(0.09), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                    if !windowed {
                        NButton(icon: "clock.arrow.circlepath", tint: history ? Palette.accent : .white) { withAnimation(Motion.ease) { history.toggle() } }
                            .tip("Riwayat percakapan")
                    }
                    NButton(icon: "square.and.pencil") { ai.reset(); history = false }.tip("Percakapan baru")
                    if !windowed {
                        NButton(icon: "arrow.up.left.and.arrow.down.right") { AIWindow.show() }.tip("Buka di jendela besar")
                    }
                }
            }
    }
}

/// Saved conversations, newest first: a list in the notch, a sidebar in the AI window.
struct AIHistory: View {
    @ObservedObject var ai: AIModel
    var picked: () -> Void = {}

    var body: some View {
        if ai.sessions.isEmpty {
            Placeholder(icon: "clock.arrow.circlepath", title: "Belum ada riwayat", subtitle: "Percakapan tersimpan otomatis di Mac ini")
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(ai.sessions) { s in row(s) }
                }
            }
        }
    }

    func row(_ s: AISession) -> some View {
        HStack(spacing: 6) {
            Button { ai.open(s); picked() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(s.cli)
                        Text("·")
                        Text(s.updated, format: Date.RelativeFormatStyle(presentation: .named, locale: appLocale))
                    }
                    .font(.system(size: 10)).foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu { Button(role: .destructive) { remove(s) } label: { Label(tr("Hapus"), systemImage: "trash") } } label: {
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tip("Hapus")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.white.opacity(s.id == ai.current ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu { Button(tr("Hapus")) { remove(s) } }
    }

    func remove(_ s: AISession) {
        if confirm(String(format: tr("Hapus %@?"), s.title), "Percakapan ini dihapus dari riwayat Poni.", "Hapus") { ai.delete(s) }
    }
}

/// A resizable dark window around a notch feature that needs more room (AI chat, Al-Qur'an).
/// Created once per id and kept, so its state survives closing; the green button makes it full screen.
/// Rebuilds its content when the accent changes (the accent is a static, not observable state).
struct AccentScope<C: View>: View {
    @AppStorage("accent") private var accentID = "mint"
    @ViewBuilder let content: C
    var body: some View { content.id(accentID) }
}

enum AppWindow {
    private static var windows: [String: NSWindow] = [:]

    static func close(_ id: String) { windows[id]?.close() }

    static func show<V: View>(_ id: String, title: String, size: NSSize, @ViewBuilder content: () -> V) {
        if Notch.shared.state.expanded { Notch.shared.toggle(nil) } // close the island first
        if windows[id] == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = title
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.isReleasedWhenClosed = false
            w.collectionBehavior.insert(.fullScreenPrimary)
            w.minSize = NSSize(width: 560, height: 420)
            w.contentView = NSHostingView(rootView: AccentScope { content() }
                .padding(.horizontal, 20).padding(.top, 36).padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .foregroundStyle(.white).background(Color.black)
                .environment(\.colorScheme, .dark))
            w.center()
            windows[id] = w
        }
        // After the notch hands focus back to the previous app, take it for the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            windows[id]?.makeKeyAndOrderFront(nil)
        }
    }
}

/// Git and PR review in a resizable window: same models as the notch.
enum GitWindow {
    static func show() { AppWindow.show("git", title: "Git", size: NSSize(width: 980, height: 640)) { GitView(g: Notch.shared.git, pr: Notch.shared.pr, ai: Notch.shared.ai, windowed: true) } }
}

/// The AI chat in a window: same AIModel as the notch, so the conversation carries over both ways.
enum AIWindow {
    static func show() { AppWindow.show("ai", title: "Poni AI", size: NSSize(width: 920, height: 680)) { AIView(ai: Notch.shared.ai, windowed: true) } }
}

func copyText(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

struct ClipView: View {
    @ObservedObject var c: ClipboardModel
    @Local private var query = ""
    @Local private var copied: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        let shown = c.items.filter { query.isEmpty || ($0.text ?? $0.ocr ?? "").localizedCaseInsensitiveContains(query) }
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.gray)
                    TextField("Cari, termasuk teks di dalam gambar", text: $query).textFieldStyle(.plain)
                        .focused($focused).onAppear { focused = true }
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.white.opacity(0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
                NButton(icon: "trash", title: "Bersihkan") { c.clear() }.help("Hapus semua kecuali yang di-pin")
            }
            if shown.isEmpty {
                Placeholder(icon: "doc.on.clipboard", title: c.items.isEmpty ? "Clipboard kosong" : "Tidak ada yang cocok",
                            subtitle: c.items.isEmpty ? "Teks dan gambar yang kamu copy muncul di sini" : nil)
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
                        Image(systemName: "text.alignleft").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.accent.opacity(0.15))
                    }
                }
                .frame(width: 40, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(copied == item.id ? "Disalin ✓" : (item.text ?? (item.ocr?.isEmpty == false ? item.ocr! : "Gambar")))
                        .font(.system(size: 12)).lineLimit(1)
                        .foregroundStyle(copied == item.id ? Palette.green : .white)
                    if item.image != nil { Text(item.ocr?.isEmpty == false ? "Gambar · teks terbaca" : "Gambar").font(.system(size: 10)).foregroundStyle(.gray) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hover || item.pinned {
                    Button { c.togglePin(item) } label: { Image(systemName: item.pinned ? "pin.fill" : "pin") }
                        .buttonStyle(.plain).foregroundStyle(item.pinned ? Palette.accent : .gray).tip("Pin")
                }
                if hover {
                    Button { c.delete(item) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.gray).tip("Hapus")
                }
            }
            .font(.system(size: 11))
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                    .background((dropping ? Palette.accent : Color.white.opacity(0.1)).gradient, in: Circle())
                Text(dropping ? "Lepas untuk menyimpan" : "Seret file ke notch").font(.system(size: 13, weight: .semibold))
                Text("Simpan sementara, lalu seret keluar atau kirim lewat AirDrop").font(.system(size: 11)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(dropping ? Palette.accent : Color.white.opacity(0.2)))
            .animation(Motion.ease, value: dropping)
        } else {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(s.files, id: \.self) { url in tile(url) }
                    }
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    Text("\(s.files.count) file · seret keluar untuk memindahkan").font(.system(size: 11)).foregroundStyle(.gray)
                    Spacer()
                    NButton(icon: "xmark", title: "Kosongkan") { s.files = [] }
                    NButton(icon: "dot.radiowaves.left.and.right", title: "AirDrop", tint: Palette.accent, prominent: true) { s.airDrop(s.files) }
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
                        .buttonStyle(.plain).foregroundStyle(.white, .gray).tip("Keluarkan dari Shelf")
                }
            }
        }
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrag { NSItemProvider(object: url as NSURL) } // a file URL, which Finder and other apps accept as the file itself
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
            stat("Baterai", "battery.75percent", Double(b.percent) / 100, b.percent <= 20 && !b.ac ? Palette.red : b.ac ? Palette.green : Palette.amber, tr(b.ac ? "dicas" : "tidak dicas"))
            stat("CPU", "cpu", s.cpu, s.cpu > 0.85 ? Palette.red : Palette.accent, String(format: tr("%@ core"), "\(ProcessInfo.processInfo.activeProcessorCount)"))
            stat("Memori", "memorychip", mem, mem > 0.85 ? Palette.red : Palette.accent, String(format: tr("%@ sisa"), bytes(s.memTotal - s.memUsed)))
            stat("Disk", "internaldrive", disk, disk > 0.85 ? Palette.red : Palette.accent, String(format: tr("%@ bebas"), bytes(s.diskFree)))
        }
        .onAppear { s.start() }
        .onDisappear { s.stop() }
    }

    func stat(_ title: String, _ icon: String, _ v: Double, _ color: Color, _ caption: String) -> some View {
        NCard {
            VStack(spacing: 8) {
                Label(tr(title), systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.gray)
                Ring(value: v, color: color, label: "\(Int(v * 100))%", size: 92, line: 9)
                Text(caption).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct GitView: View {
    @ObservedObject var g: GitModel
    @ObservedObject var pr: PRModel
    let ai: AIModel
    var windowed = false // shown in GitWindow instead of the notch
    @AppStorage("gitPane") private var showPR = false
    @Local private var composing: Repo?
    @Local private var connecting: String? // "bitbucket" / "sonar"
    @AppStorage(GitModel.openerKey) private var opener = GitModel.terminal

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
                    if pr.bitbucketConnected {
                        Menu {
                            Button("Putuskan Bitbucket") { Bitbucket.disconnect(); pr.bitbucketConnected = false; pr.refresh(repos: g.repos.map(\.path)) }
                        } label: { Label("Bitbucket", systemImage: "checkmark.circle.fill") }
                            .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11, weight: .semibold))
                    } else {
                        NButton(icon: "link", title: "Bitbucket") { connecting = "bitbucket" }
                    }
                    NButton(icon: "arrow.clockwise") { pr.refresh(repos: g.repos.map(\.path)) }.tip("Muat ulang PR")
                } else {
                    NButton(icon: "arrow.clockwise") { g.refresh() }.tip("Segarkan status")
                    NButton(icon: "plus", title: "Tambah repo") { g.add() }
                }
                if !windowed {
                    NButton(icon: "arrow.up.left.and.arrow.down.right") { GitWindow.show() }.tip("Buka di jendela besar")
                }
            }
            if showPR {
                if connecting == "bitbucket" {
                    ConnectForm(title: "Hubungkan Bitbucket Server",
                                help: "Buat HTTP access token di Bitbucket: avatar → Manage account → HTTP access tokens, izin Repository: Write (komentar, approve, merge). Token disimpan di Keychain.",
                                placeholder: "https://bitbucket.perusahaan.com", connect: Bitbucket.connect,
                                done: { connecting = nil; pr.bitbucketConnected = Bitbucket.connected; pr.refresh(repos: g.repos.map(\.path)) },
                                url: Bitbucket.base ?? "")
                } else if connecting == "sonar" {
                    ConnectForm(title: "Hubungkan SonarQube",
                                help: "Buat user token di SonarQube: avatar → My Account → Security → Generate Token (tipe User). Dipakai hanya untuk membaca temuan & aturan. Token disimpan di Keychain.",
                                placeholder: "https://sonarqube.perusahaan.com", connect: Sonar.connect,
                                done: { connecting = nil; pr.sonarConnected = Sonar.connected },
                                url: Sonar.base ?? "")
                } else {
                    PRPane(pr: pr, ai: ai, repos: g.repos.map(\.path), listWidth: windowed ? 300 : 200) { connecting = "sonar" }
                }
            } else if let r = composing {
                CommitPane(g: g, ai: ai, repo: r) { composing = nil }
            } else {
                repoList
            }
        }
        .onAppear {
            g.refresh()
            // The pane is remembered between launches, so it can open without a click on the PR tab.
            if showPR, pr.prs.isEmpty, !pr.loading { pr.refresh(repos: g.repos.map(\.path)) }
        }
    }

    func pane(_ title: String, count: Int, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(Motion.ease) { run() } }) {
            HStack(spacing: 5) {
                Text(tr(title))
                if count > 0 { Text("\(count)").font(.system(size: 10, weight: .bold)).padding(.horizontal, 5).background(Color.white.opacity(0.18), in: Capsule()) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(on ? Palette.onAccent : Color.gray)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(on ? Palette.accent.opacity(0.9) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var repoList: some View {
        if g.repos.isEmpty {
            Placeholder(icon: "arrow.triangle.branch", title: "Belum ada repo", subtitle: "Klik Tambah repo untuk memantau branch dan perubahan")
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
            Image(systemName: "folder.fill").font(.system(size: 14)).foregroundStyle(Palette.accent)
                .frame(width: 34, height: 34).background(Palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(r.name).font(.system(size: 13, weight: .semibold))
                    Chip(text: r.status.branch, icon: "arrow.triangle.branch", color: Palette.accent)
                }
                HStack(spacing: 6) {
                    Chip(text: r.status.changes == 0 ? "bersih" : "\(r.status.changes) berubah", icon: r.status.changes == 0 ? "checkmark" : "pencil",
                         color: r.status.changes > 0 ? Palette.amber : Palette.green)
                    if r.status.ahead > 0 { Chip(text: "\(r.status.ahead)", icon: "arrow.up", color: Palette.green) }
                    if r.status.behind > 0 { Chip(text: "\(r.status.behind)", icon: "arrow.down", color: Palette.accent) }
                    if !r.message.isEmpty {
                        Text(r.message).font(.system(size: 10)).foregroundStyle(r.failed ? Palette.red : .gray).lineLimit(1).help(r.message)
                    }
                }
            }
            Spacer()
            if r.busy {
                ProgressView().controlSize(.small)
            } else {
                if r.status.changes > 0 {
                    NButton(icon: "checkmark.circle", title: "Commit", tint: Palette.green) { composing = r }
                }
                NButton(icon: "arrow.triangle.2.circlepath") { g.run(r, "fetch") }.tip("Fetch")
                NButton(icon: "arrow.down") { g.run(r, "pull") }.tip("Pull (fast-forward)")
                NButton(icon: "arrow.up") { g.run(r, "push") }.tip("Push")
            }
            Menu {
                Button(String(format: tr("Buka di %@"), GitModel.appName(opener))) { g.open(r, app: opener) }
                Button("Buka di VS Code") { g.open(r, app: "com.microsoft.VSCode") }
                Button("Ganti aplikasi terminal…") { if let id = g.chooseOpener() { opener = id } }
                Button("Tampilkan di Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) }
                Divider()
                Button("Hapus dari daftar") { g.remove(r) }
            } label: { Image(systemName: "ellipsis") }
                .tip("Lainnya").menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct PRPane: View {
    @ObservedObject var pr: PRModel
    let ai: AIModel
    let repos: [String]
    var listWidth: CGFloat = 200
    let connectSonar: () -> Void
    @Local private var editing = false
    @AppStorage("prRepoFilter") private var repoFilter = "" // "" = all projects

    var body: some View {
        if !pr.error.isEmpty && pr.prs.isEmpty {
            Placeholder(icon: "exclamationmark.triangle.fill", title: "Tidak bisa memuat PR", subtitle: pr.error)
        } else if pr.prs.isEmpty {
            Placeholder(icon: "checkmark.seal.fill", title: pr.loading ? "Memuat PR…" : "Tidak ada PR terbuka",
                        subtitle: "PR yang minta review-mu, PR milikmu, dan PR di repo yang dipantau")
        } else {
            let projects = Array(Set(pr.prs.map(\.repo))).sorted()
            let shown = pr.prs.filter { repoFilter.isEmpty || $0.repo == repoFilter }
            HStack(spacing: 10) {
                VStack(spacing: 6) {
                    if projects.count > 1 {
                        Menu {
                            Button(tr("Semua project")) { repoFilter = "" }
                            Divider()
                            ForEach(projects, id: \.self) { r in
                                Button("\(r) (\(pr.prs.filter { $0.repo == r }.count))") { repoFilter = r }
                            }
                        } label: {
                            Label(repoFilter.isEmpty ? tr("Semua project") : repoFilter, systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .menuStyle(.borderlessButton).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.07), in: Capsule())
                        .tip("Filter PR per project")
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(shown) { p in listRow(p) }
                        }
                    }
                }
                .frame(width: listWidth)
                detail
            }
            .onAppear { if !repoFilter.isEmpty && !projects.contains(repoFilter) { repoFilter = "" } } // project has no open PRs anymore
        }
    }

    func listRow(_ p: PR) -> some View {
        let on = pr.selected == p
        return Button { pr.select(p) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.title).font(.system(size: 11, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(verbatim: "\(p.repo.components(separatedBy: "/").last ?? "")#\(p.number)").foregroundStyle(.gray)
                    if p.host == .bitbucket { Chip(text: "bitbucket", color: Palette.accent) }
                    if p.reviewRequested { Chip(text: "review", color: Palette.accent) }
                    if p.isDraft { Chip(text: "draft") }
                }
                .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(on ? Palette.accent.opacity(0.35) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? Palette.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder var detail: some View {
        if let p = pr.selected, repoFilter.isEmpty || p.repo == repoFilter {
            NCard(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(p.title).font(.system(size: 12, weight: .bold)).lineLimit(1)
                            Text(verbatim: "\(p.repo)#\(p.number) · @\(p.author)").font(.system(size: 10)).foregroundStyle(.gray)
                        }
                        Spacer()
                        NButton(icon: "safari") { NSWorkspace.shared.open(URL(string: p.url)!) }.tip("Buka di browser")
                    }
                    if let d = pr.detail {
                        HStack(spacing: 5) {
                            switch d.checks {
                            case "pass": Chip(text: "CI lulus", icon: "checkmark.circle.fill", color: Palette.green)
                            case "fail": Chip(text: "CI gagal", icon: "xmark.circle.fill", color: Palette.red)
                            case "pending": Chip(text: "CI berjalan", icon: "clock.fill", color: Palette.amber)
                            default: EmptyView()
                            }
                            Chip(text: "+\(d.additions)", color: Palette.green)
                            Chip(text: "−\(d.deletions)", color: Palette.red)
                            Chip(text: "\(d.changedFiles) file")
                            if d.conflicted { Chip(text: "konflik", icon: "exclamationmark.triangle.fill", color: Palette.amber) }
                        }
                        reviewArea(p, d)
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if !pr.message.isEmpty {
                        Text(pr.message).font(.system(size: 10)).foregroundStyle(pr.failed ? Palette.red : .gray).lineLimit(2).help(pr.message)
                    }
                }
            }
        } else {
            NCard {
                Placeholder(icon: "text.magnifyingglass", title: "Pilih PR", subtitle: "Lalu minta AI me-review diff-nya")
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
                contextBar(p)
                NButton(icon: "sparkles", title: "Review dengan \(pr.reviewCLI)", tint: Palette.accent, prominent: true) { pr.aiReview(ai, repos: repos) }
                Text(pr.reviewCLI == "Claude" ? "Diff dikirim ke Claude tanpa akses tool apa pun" : "Kiro tidak diberi izin tool, tapi isolasinya belum dicek seketat Claude")
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Group {
                if editing {
                    TextEditor(text: $pr.review).font(.system(size: 11, design: .monospaced)).scrollContentBackground(.hidden)
                } else {
                    ScrollView {
                        Text((try? AttributedString(markdown: pr.review, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(pr.review))
                            .font(.system(size: 11)).lineSpacing(2).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 6) {
                Menu {
                    Button("Komentar") { send(p, "comment", "komentar") }
                    Button("Approve") { send(p, "approve", "approve") }
                    Button("Minta perubahan") { send(p, "request-changes", "permintaan perubahan") }
                } label: { Label("Kirim review", systemImage: "paperplane.fill") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if !pr.contextNote.isEmpty { Text(pr.contextNote).font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1) }
                NButton(icon: editing ? "checkmark" : "pencil") { editing.toggle() }.help(editing ? "Selesai mengedit" : "Edit review")
                NButton(icon: "doc.on.doc") { copyText(pr.review) }.tip("Salin review")
                Menu {
                    ForEach(p.host == .github ? [("merge", "Merge commit"), ("squash", "Squash & merge"), ("rebase", "Rebase & merge")]
                                              : [("merge", "Merge (strategi repo)")], id: \.0) { m in
                        Button(m.1) {
                            if confirm("Merge PR #\(p.number)?", "\(p.repo): \(p.title)\nMetode: \(m.1). Ini tidak bisa dibatalkan dari sini.", "Merge") { pr.merge(m.0) }
                        }
                    }
                } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(!d.canMerge || d.checks == "fail")
                    .help(!d.canMerge ? "PR belum bisa di-merge" : d.checks == "fail" ? "CI gagal" : "Merge PR")
            }
        }
    }

    /// What goes into the review: which AI, team guides, SonarQube.
    func contextBar(_ p: PR) -> some View {
        let guides = Guides.files(p.repo)
        let key = Sonar.projectKey(p, repos: repos)
        return HStack(spacing: 6) {
            Menu {
                ForEach(ai.clis, id: \.name) { c in
                    Button { pr.reviewCLI = c.name } label: { Label(c.name, systemImage: pr.reviewCLI == c.name ? "checkmark" : "") }
                }
            } label: { Label(pr.reviewCLI, systemImage: "sparkles") }
                .menuStyle(.borderlessButton).fixedSize()
            Menu {
                ForEach(guides, id: \.self) { f in
                    Button { Guides.set(p.repo, guides.filter { $0 != f }); pr.objectWillChange.send() } label: { Label((f as NSString).lastPathComponent, systemImage: "xmark") }
                }
                if !guides.isEmpty { Divider() }
                Button("Tambah file panduan / aturan…") {
                    let slug = (p.repo.components(separatedBy: "/").last ?? "").lowercased()
                    Guides.add(p.repo, near: repos.first { ($0 as NSString).lastPathComponent.lowercased() == slug })
                    pr.objectWillChange.send()
                }
            } label: { Label(guides.isEmpty ? "Panduan" : "Panduan (\(guides.count))", systemImage: "books.vertical") }
                .menuStyle(.borderlessButton).fixedSize()
            if pr.sonarConnected {
                Menu {
                    Text(key.map { "Project: \($0)" } ?? "Project key belum diatur")
                    Button("Ubah project key…") {
                        if let k = ask("Project key SonarQube", "Untuk \(p.repo). Lihat sonar.projectKey di sonar-project.properties.", key ?? "") {
                            Sonar.setProjectKey(p, k.isEmpty ? nil : k); pr.objectWillChange.send()
                        }
                    }
                    Divider()
                    Button("Putuskan SonarQube") { Sonar.disconnect(); pr.sonarConnected = false }
                } label: { Label(key == nil ? "Sonar ?" : "Sonar", systemImage: key == nil ? "exclamationmark.circle" : "checkmark.shield") }
                    .menuStyle(.borderlessButton).fixedSize()
            } else {
                Button { connectSonar() } label: { Label("Sonar", systemImage: "link") }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white.opacity(0.85))
    }

    func send(_ p: PR, _ event: String, _ label: String) {
        if confirm("Kirim \(label) ke PR #\(p.number)?", "Review ini akan terlihat publik di \(p.repo) atas nama akun GitHub-mu.", "Kirim") { pr.post(event) }
    }
}

struct CommitPane: View {
    @ObservedObject var g: GitModel
    let ai: AIModel
    let repo: Repo
    let close: () -> Void
    @Local private var files: [String] = []
    @Local private var message = ""
    @Local private var push = false
    @Local private var thinking = false
    @Local private var busy = false
    @Local private var result = ""
    @Local private var resultOK = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                NButton(icon: "chevron.left") { close() }.tip("Kembali")
                Text(repo.name).font(.system(size: 13, weight: .bold))
                Chip(text: repo.status.branch, icon: "arrow.triangle.branch", color: Palette.accent)
                Spacer()
                Text("\(files.count) file akan di-commit").font(.system(size: 11)).foregroundStyle(.gray)
            }
            HStack(spacing: 10) {
                NCard(padding: 8) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(files, id: \.self) { f in
                                let code = String(f.prefix(2)).trimmingCharacters(in: .whitespaces)
                                HStack(spacing: 6) {
                                    Text(code == "??" ? "A" : String(code.prefix(1)))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(code == "??" || code.hasPrefix("A") ? Palette.green : code.hasPrefix("D") ? Palette.red : Palette.amber)
                                        .frame(width: 14)
                                    Text(String(f.dropFirst(3))).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.head)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 220)
                VStack(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $message).font(.system(size: 11)).scrollContentBackground(.hidden)
                        if message.isEmpty {
                            Text(thinking ? "AI sedang membaca diff…" : "Pesan commit").font(.system(size: 11)).foregroundStyle(.gray)
                                .padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    HStack(spacing: 8) {
                        if thinking {
                            ProgressView().controlSize(.small)
                        } else {
                            NButton(icon: "sparkles", title: "Tulis dengan AI", tint: Palette.accent) {
                                thinking = true
                                g.aiMessage(repo, ai: ai) { ok, text in thinking = false; if ok { message = text } else { result = text } }
                            }
                        }
                        Toggle("Push", isOn: $push).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
                        Spacer()
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            NButton(icon: "checkmark", title: push ? "Commit & Push" : "Commit", tint: Palette.green, prominent: true) {
                                busy = true
                                g.commit(repo, message: message, push: push) { ok, text in
                                    busy = false
                                    resultOK = ok
                                    result = text
                                    if ok { message = ""; g.changes(repo) { files = $0 } }
                                }
                            }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || files.isEmpty)
                            .opacity(message.isEmpty || files.isEmpty ? 0.5 : 1)
                        }
                    }
                    if !result.isEmpty {
                        Text(result).font(.system(size: 11)).foregroundStyle(resultOK ? Palette.green : Palette.red).lineLimit(2).help(result)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .onAppear { g.changes(repo) { files = $0 } }
    }
}

/// URL + token form; `connect` verifies before anything is stored.
struct ConnectForm: View {
    let title: String, help: String, placeholder: String
    let connect: (String, String, @escaping (Bool, String) -> Void) -> Void
    let done: () -> Void
    @Local var url: String
    @Local private var token = ""
    @Local private var status = ""
    @Local private var statusOK = false
    @Local private var busy = false

    var body: some View {
        NCard {
            VStack(alignment: .leading, spacing: 9) {
                Label(tr(title), systemImage: "link").font(.system(size: 13, weight: .bold))
                Text(help).font(.system(size: 11)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
                field("globe", TextField(placeholder, text: $url))
                field("key.fill", SecureField("Token", text: $token))
                HStack {
                    if !status.isEmpty { Text(status).font(.system(size: 11)).foregroundStyle(statusOK ? Palette.green : Palette.red).lineLimit(2).help(status) }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    NButton(icon: "xmark", title: "Batal") { done() }
                    NButton(icon: "checkmark", title: "Simpan & tes", tint: Palette.accent, prominent: true) {
                        busy = true
                        status = ""
                        connect(url, token.trimmingCharacters(in: .whitespacesAndNewlines)) { ok, msg in
                            busy = false
                            statusOK = ok
                            status = msg
                            if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { done() } }
                        }
                    }
                    .disabled(token.isEmpty || url.isEmpty || busy)
                }
            }
        }
    }

    func field<F: View>(_ icon: String, _ f: F) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.gray).frame(width: 14)
            f.textFieldStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.09), in: Capsule())
    }
}

struct MeetingChip: View {
    let m: Meeting
    let join: () -> Void

    var body: some View {
        Button(action: join) {
            HStack(spacing: 5) {
                Image(systemName: m.link == nil ? "calendar" : "video.fill")
                Text(m.title).lineLimit(1).frame(maxWidth: 60, alignment: .leading)
                Text(m.when(Date())).foregroundStyle(.white.opacity(0.8)).fixedSize()
                if m.link != nil {
                    Text("Join").font(.system(size: 11, weight: .semibold)).fixedSize().padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: Capsule()).foregroundStyle(Palette.accent)
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.onAccent)
            .padding(.leading, 9).padding(.trailing, 4).padding(.vertical, 4)
            .background(Palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("\(m.title) — \(m.link == nil ? "buka Kalender" : "gabung rapat")")
    }
}

struct NotesView: View {
    @ObservedObject var n: NotesModel
    let ai: AIModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                NButton(icon: "plus", title: "Baru", tint: Palette.accent) { n.add(); focused = true }
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(n.notes) { note in
                            let on = note.id == n.selected
                            Button { n.selected = note.id } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                                    Text(note.updated, format: Date.RelativeFormatStyle(presentation: .named, locale: appLocale)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(on ? AnyShapeStyle(Color.white.opacity(0.14)) : AnyShapeStyle(Color.white.opacity(0.05)),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Hapus", role: .destructive) { n.delete(note.id) } }
                        }
                    }
                }
            }
            .frame(width: 170)

            if let note = n.current {
                NCard(padding: 10) {
                    VStack(spacing: 8) {
                        if note.readOnly {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                Text("Ada gambar atau tabel: edit di Notes supaya tidak rusak").lineLimit(1)
                                Spacer()
                                NButton(icon: "arrow.up.forward.app", title: "Buka di Notes", tint: Palette.accent) { n.openInNotes(note.id) }
                            }
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                        }
                        TextEditor(text: Binding(get: { n.current?.text ?? "" }, set: { n.update($0) }))
                            .font(.system(size: 12)).scrollContentBackground(.hidden).focused($focused).disabled(note.readOnly)
                        HStack(spacing: 6) {
                            syncStatus(note)
                            Spacer()
                            if n.thinking { ProgressView().controlSize(.small) }
                            NButton(icon: "sparkles", title: "Rapikan dengan AI", tint: Palette.accent) { n.tidy(ai) }.disabled(n.thinking)
                            NButton(icon: "doc.on.doc") { copyText(note.text) }.tip("Salin catatan")
                            NButton(icon: "trash", tint: Palette.red) { n.delete(note.id) }.help("Hapus catatan")
                        }
                    }
                }
            } else {
                NCard { Placeholder(icon: "note.text", title: "Belum ada catatan", subtitle: "Klik Baru, atau ⌃⌥N dari mana saja") }
            }
        }
        .onAppear { if n.notes.isEmpty { n.add() }; focused = true; n.sync() }
    }

    @ViewBuilder func syncStatus(_ note: Note) -> some View {
        Group {
            if n.denied {
                Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!) } label: {
                    Label("Tersimpan lokal · izinkan Notes", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain).help("System Settings → Privacy & Security → Automation → Poni → Notes")
            } else if n.syncing || note.dirty || (!note.synced && !note.text.isEmpty) {
                Label("Menyinkron…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.white.opacity(0.5))
            } else if note.synced {
                Label("Apple Notes", systemImage: "checkmark.icloud.fill").foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.system(size: 10))
    }
}

struct DevView: View {
    @Local private var input = ""
    @Local private var copied = ""
    @FocusState private var focused: Bool

    var body: some View {
        let results = conversions(input)
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                NCard(padding: 8) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $input).font(.system(size: 11, design: .monospaced)).scrollContentBackground(.hidden).focused($focused)
                        if input.isEmpty {
                            Text("Tempel JSON, JWT, Base64, URL, timestamp, atau teks apa pun").font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.4)).padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                }
                HStack(spacing: 6) {
                    NButton(icon: "doc.on.clipboard", title: "Tempel", tint: Palette.accent) { input = NSPasteboard.general.string(forType: .string) ?? "" }
                        .hoverTip("Tempel dari clipboard")
                    NButton(icon: "clock") { input = String(Int(Date().timeIntervalSince1970)) }.hoverTip("Timestamp sekarang")
                    NButton(icon: "number") { input = UUID().uuidString; copyText(input); copied = "UUID" }.hoverTip("Buat & salin UUID baru")
                    Spacer()
                    if !input.isEmpty { NButton(icon: "xmark") { input = "" }.hoverTip("Kosongkan") }
                }
            }
            .frame(width: 290)

            ScrollView {
                VStack(spacing: 6) {
                    if results.isEmpty {
                        Placeholder(icon: "curlybraces", title: "Dev Utils", subtitle: "Hasil konversi muncul otomatis. Semua diproses di Mac ini.")
                            .frame(height: 200)
                    }
                    ForEach(results, id: \.id) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.gray)
                                Spacer()
                                Button(copied == r.title ? "Disalin ✓" : "Salin") { copyText(r.output); copied = r.title }
                                    .buttonStyle(.plain).font(.system(size: 11, weight: .bold)).foregroundStyle(copied == r.title ? Palette.green : .white.opacity(0.7))
                                    .hoverTip("Salin hasil ini")
                            }
                            Text(r.output).font(.system(size: 11, design: .monospaced)).lineLimit(8).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(9)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .onAppear {
            focused = true
            // Start from whatever was just copied if it looks like something to convert.
            if input.isEmpty, let c = NSPasteboard.general.string(forType: .string), c.count < 20_000,
               conversions(c).contains(where: { !["Base64 encode", "URL encode", "SHA-256", "MD5"].contains($0.title) }) { input = c }
        }
        .onChange(of: input) { _ in copied = "" }
    }
}
