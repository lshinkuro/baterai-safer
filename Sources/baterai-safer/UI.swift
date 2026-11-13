import SwiftUI

// Shared building blocks for all tabs.

/// Drop-in for `@State`. In recent SDKs `@State` needs the SwiftUI macro plugin, which ships only
/// with Xcode; Homebrew builds with Command Line Tools, where a plain `State` value still works.
@propertyWrapper struct Local<Value>: DynamicProperty {
    private let state: State<Value>
    init(wrappedValue: Value) { state = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Two-stop color; heroes use it for a faint glow, everything else takes the accent.
struct Theme {
    let a: Color, b: Color
    var gradient: LinearGradient { LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static var accent: Theme { Theme(a: Palette.accent, b: Palette.accent2) }
    static let rose = Theme(a: Color(hex: 0xF43F5E), b: Color(hex: 0xE11D48))
}

/// Vivid colors for icons, bars and badges (instead of the stock system palette).
enum Palette {
    static let green = Color(hex: 0x22C55E), teal = Color(hex: 0x14B8A6), blue = Color(hex: 0x3B82F6)
    static let indigo = Color(hex: 0x6366F1), violet = Color(hex: 0xA855F7), pink = Color(hex: 0xEC4899)
    static let red = Color(hex: 0xF43F5E), orange = Color(hex: 0xF97316), amber = Color(hex: 0xF59E0B)
    static let yellow = Color(hex: 0xEAB308), sky = Color(hex: 0x0EA5E9), slate = Color(hex: 0x64748B)
    static let cycle = [blue, pink, amber, teal, violet, orange, green, sky, red, indigo]
    /// Accent choices (Tools → Tampilan). All light enough for dark text on top yet visible on a light
    /// background (so no white/gray), and none close to the amber/red that mean "warning"/"error".
    static let accents: [(id: String, name: String, color: Color)] = [
        ("mint", "Mint", Color(hex: 0x34D399)), ("sky", "Langit", Color(hex: 0x38BDF8)), ("violet", "Ungu", Color(hex: 0xA78BFA)),
        ("pink", "Pink", Color(hex: 0xF472B6)), ("lime", "Lime", Color(hex: 0xA3E635)),
    ]
    /// Two-stop accents, same rules as `accents` for both stops. Text, toggles and hairlines take the
    /// first stop; only filled shapes (`accentFill`) show the blend.
    static let gradients: [(id: String, name: String, a: Color, b: Color)] = [
        ("aurora", "Aurora", Color(hex: 0x34D399), Color(hex: 0x38BDF8)), ("lavender", "Lavender", Color(hex: 0xA78BFA), Color(hex: 0xF472B6)),
        ("ocean", "Laut", Color(hex: 0x38BDF8), Color(hex: 0x818CF8)), ("citrus", "Citrus", Color(hex: 0xA3E635), Color(hex: 0x34D399)),
        // Deep tones only as the second stop: a solid maroon or navy vanishes on the black notch.
        ("maroon", "Marun", Color(hex: 0xFB7185), Color(hex: 0x9F1239)), ("navy", "Dongker", Color(hex: 0x60A5FA), Color(hex: 0x1E3A8A)),
    ]
    /// The one brand color; everything else stays neutral. Views rebuild on change via `.id(accentID)`.
    private(set) static var accent = color(UserDefaults.standard.string(forKey: "accent"))
    /// Second stop of a gradient accent; the accent itself for a solid one.
    private(set) static var accent2 = color2(UserDefaults.standard.string(forKey: "accent"))
    static var accentFill: LinearGradient { LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing) }
    static func color(_ id: String?) -> Color {
        if let h = customHue(id) { return custom(h) }
        if let g = gradients.first(where: { $0.id == id }) { return g.a }
        return accents.first { $0.id == id }?.color ?? accents[0].color
    }
    static func color2(_ id: String?) -> Color { gradients.first { $0.id == id }?.b ?? color(id) }
    /// A custom accent is stored as "hue:0.53".
    static func customHue(_ id: String?) -> Double? { id.flatMap { $0.hasPrefix("hue:") ? Double($0.dropFirst(4)) : nil } }
    /// Fixed saturation and brightness keep every hue light enough for dark text on top, like `accents`.
    static func custom(_ hue: Double) -> Color { Color(hue: hue, saturation: 0.6, brightness: 0.95) }
    static func setAccent(_ id: String) { accent = color(id); accent2 = color2(id); UserDefaults.standard.set(id, forKey: "accent") }
    static let onAccent = Color.black.opacity(0.85) // text and icons on an accent fill
    /// Light catching the top edge of an accent fill; stroke it over `Palette.accentFill`.
    static let sheen = LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0)], startPoint: .top, endPoint: .center)
    static let hairline = Color.primary.opacity(0.08)
}

extension NSImage {
    /// Poni's face (the notch is the bangs) as a template glyph, so the menu bar tints it like an SF Symbol.
    static let poni: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let body = NSBezierPath(roundedRect: NSRect(x: 1.7, y: 1.7, width: 14.6, height: 12.6), xRadius: 4, yRadius: 4)
            body.lineWidth = 1.4; body.stroke()
            NSBezierPath(roundedRect: NSRect(x: 5.5, y: 11.2, width: 7, height: 3.6), xRadius: 1.4, yRadius: 1.4).fill()
            for x in [6.2, 11.8] { NSBezierPath(ovalIn: NSRect(x: x - 0.95, y: 6.6, width: 1.9, height: 2.5)).fill() }
            let smile = NSBezierPath()
            smile.appendArc(withCenter: NSPoint(x: 9, y: 6.4), radius: 2.5, startAngle: 215, endAngle: 325)
            smile.lineWidth = 1.2; smile.lineCapStyle = .round; smile.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }()
}

/// The language the app is showing (Indonesian or English), for dates and weekday names.
let appLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "id")

/// Translates a string that arrives at runtime (component titles, model messages); literals in `Text` translate themselves.
func tr(_ s: String) -> String { NSLocalizedString(s, comment: "") }

extension View {
    /// Tooltip that is also the VoiceOver name; for buttons that show only an icon.
    func tip(_ text: String) -> some View { help(tr(text)).accessibilityLabel(tr(text)) }
}

/// The app's two animation curves; nil (instant) when Reduce Motion is on.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var snap: Animation? { reduced ? nil : .spring(response: 0.32, dampingFraction: 0.8) } // taps, open/close
    static var ease: Animation? { reduced ? nil : .easeInOut(duration: 0.2) }                    // fades, value changes
}

private struct AccentKey: EnvironmentKey { static var defaultValue: Theme { .accent } }
extension EnvironmentValues {
    var accent: Theme {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}

/// The App Store build (`-DLITE`): no root helper, private API or other apps' data, so it can live in the sandbox.
enum Lite {
    #if LITE
    static let on = true
    #else
    static let on = false
    #endif
    static let cutTabs: Set<NTab> = on ? [.music, .ai, .clipboard, .shelf, .git, .stats] : []
    static let cutTools: Set<String> = on ? ["charge", "downloads", "drives", "update"] : []
}

/// Features switched off by the user, stored comma-separated so `@AppStorage(FeatureFlags.key)` can observe it.
enum FeatureFlags {
    static let key = "featuresOff"
    static func off() -> Set<String> { Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",").map(String.init)) }
    static func isOn(_ f: String) -> Bool { !off().contains(f) }
    static func set(_ f: String, _ on: Bool) {
        var o = off()
        if on { o.remove(f) } else { o.insert(f) }
        UserDefaults.standard.set(o.sorted().joined(separator: ","), forKey: key)
    }
}

enum Tab: Int, CaseIterable {
    case battery, system, cleaner, tools
    var title: String { ["Baterai", "Sistem", "Cleaner", "Tools"][rawValue] }
    var icon: String { ["bolt.fill", "cpu.fill", "sparkles", "square.grid.2x2.fill"][rawValue] }
        /// Baterai and Tools (where features are switched back on) can't be turned off.
    var enabled: Bool { Lite.on ? self == .tools : self == .battery || self == .tools || FeatureFlags.isOn("panel.\(self)") }
}

struct TabBar: View {
    @Binding var tab: Int
    let tabs: [Tab]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { t in
                let on = tab == t.rawValue
                Button { withAnimation(Motion.snap) { tab = t.rawValue } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 10, weight: .semibold))
                        Text(tr(t.title)).font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Palette.onAccent : Color.secondary)
                    .background {
                        if on { Capsule().fill(Palette.accentFill).overlay(Capsule().strokeBorder(Palette.sheen, lineWidth: 1)).matchedGeometryEffect(id: "sel", in: ns) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// Headline card: near-black in both appearances, with a faint glow in the theme's color.
struct Hero<Content: View>: View {
    @Environment(\.accent) private var accent
    var theme: Theme?
    @ViewBuilder let content: Content

    var body: some View {
        let t = theme ?? accent, shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0x232427), Color(hex: 0x0F1011)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [t.a.opacity(0.26), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}

struct Card<Content: View>: View {
    let title: String?, icon: String?
    let content: Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
                    Text(tr(title).uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8)
                }
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: shape)
        .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
    }
}

/// Neutral rounded-square symbol (rows, lists).
struct IconBadge: View {
    let icon: String
    var size: CGFloat = 24
    var tint: Color? // colored only when it means something (a switch that is on)

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary.opacity(0.75)))
            .frame(width: size, height: size)
            .background((tint ?? .primary).opacity(tint == nil ? 0.07 : 0.16), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .animation(Motion.ease, value: tint == nil)
    }
}

struct Switch: View {
    let title: String, icon: String
    @Binding var on: Bool

    init(_ title: String, _ icon: String, _ on: Binding<Bool>) {
        self.title = title; self.icon = icon; _on = on
    }

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, tint: on ? Palette.accent : nil)
            Text(tr(title)).font(.system(size: 13))
            Spacer()
            Toggle(tr(title), isOn: $on).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Palette.accent)
        }
    }
}

/// Stat tile: quiet card, big number, small caps label. `tone` says how good the value is;
/// `fraction` adds a thin bar showing where it sits on its scale.
struct Tile: View {
    let icon: String, title: String, value: String
    var tone: Color?
    var fraction: Double?
    var help = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tone ?? .secondary)
            Spacer(minLength: 6)
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText()).animation(Motion.ease, value: value) // digits roll, Live Activity style
            Text(tr(title).uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
            if let fraction {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in Capsule().fill(tone ?? Palette.accent).frame(width: g.size.width * min(max(fraction, 0), 1)) }
                    }
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: shape)
        .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
        .help(help)
    }
}

/// A battery body with liquid fill and an optional limit line — the app's signature.
struct BatteryGlyph: View {
    let level: Double // 0...1
    var limit: Double?
    var charging = false
    var color: Color = .white

    var body: some View {
        let v = min(max(level, 0), 1)
        VStack(spacing: 3) {
            Capsule().fill(.white.opacity(0.55)).frame(width: 18, height: 5)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.18))
                    // While charging the top of the charge ripples; the timeline is paused (no redraws) otherwise.
                    // 12 fps: a slow ripple doesn't need more, and each frame redraws the hero.
                    TimelineView(.animation(minimumInterval: 1 / 12, paused: !charging || Motion.reduced)) { ctx in
                        Wave(phase: charging ? ctx.date.timeIntervalSinceReferenceDate * 2.4 : 0, amplitude: charging && !Motion.reduced ? 2.5 : 0)
                            .fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    }
                    .frame(height: max(8, (g.size.height - 8) * v))
                    .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 10, bottomTrailing: 10, topTrailing: 4), style: .continuous))
                    .padding(4)
                    if let limit {
                        Rectangle().fill(.white).frame(height: 2)
                            .overlay(alignment: .trailing) { Text("\(Int(limit * 100))").font(.system(size: 8, weight: .semibold)).offset(x: 16) }
                            .offset(y: -(g.size.height - 8) * limit - 4)
                            .opacity(0.9)
                    }
                    if charging {
                        Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black.opacity(0.35))
                            .frame(maxHeight: .infinity)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 2))
            }
        }
        .frame(width: 52, height: 96)
        .animation(Motion.snap, value: v)
    }
}

/// Reports whether the hosting window is on screen (occlusion state), e.g. a MenuBarExtra window
/// that is ordered out rather than closed.
struct WindowVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> Watcher { Watcher(changed) }
    func updateNSView(_ v: Watcher, context: Context) {}

    final class Watcher: NSView {
        let changed: (Bool) -> Void
        private var token: NSObjectProtocol?
        init(_ changed: @escaping (Bool) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        deinit { token.map(NotificationCenter.default.removeObserver) }

        override func viewDidMoveToWindow() {
            token.map(NotificationCenter.default.removeObserver)
            guard let window else { return }
            token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in
                if let window { self?.changed(window.occlusionState.contains(.visible)) }
            }
        }
    }
}

/// A rectangle whose top edge is a sine wave; `amplitude` 0 is a flat top.
struct Wave: Shape {
    var phase: Double, amplitude: Double

    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            for x in stride(from: r.minX, through: r.maxX, by: 2) {
                p.addLine(to: CGPoint(x: x, y: r.minY + amplitude * (1 + sin(phase + x / r.width * 2 * .pi))))
            }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// A dot that blinks once per new sample: "this is live". A continuous pulse would redraw the whole
/// popover (rings, chart, background blur) every frame, about 35% CPU; one short fade per beat is nearly free.
struct LivePulse: View {
    let beat: Int
    var size: CGFloat = 7
    @Local private var lit = false

    var body: some View {
        Circle().fill(Palette.accent).frame(width: size, height: size)
            .opacity(lit ? 1 : 0.35)
            .onChange(of: beat) { _ in
                lit = true
                withAnimation(Motion.ease?.delay(0.25)) { lit = false }
            }
            .accessibilityHidden(true)
    }
}

/// Green → amber → red as a resource fills up.
func level(_ v: Double) -> Color { v > 0.85 ? Palette.red : v > 0.65 ? Palette.amber : Palette.green }

struct Ring: View {
    let value: Double // 0...1
    let color: Color
    var end: Color? // a second stop the arc sweeps into, for a gradient accent
    let label: String
    var caption: String?
    var size: CGFloat = 76
    var line: CGFloat = 9
    var marker: Double?

    var body: some View {
        let v = min(max(value, 0), 1)
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: line)
            Circle().trim(from: 0, to: v)
                .stroke(AngularGradient(colors: end.map { [color, $0] } ?? [color.opacity(0.55), color], center: .center, startAngle: .zero, endAngle: .degrees(360 * max(v, 0.01))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.ease, value: v) // glides between samples instead of jumping
            if let marker {
                Capsule().fill(Color.primary).frame(width: 3, height: line + 5)
                    .offset(y: -(size - line) / 2).rotationEffect(.degrees(marker * 360))
            }
            VStack(spacing: 0) {
                Text(label).font(.system(size: size * 0.22, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText()).animation(Motion.ease, value: label)
                if let caption { Text(tr(caption)).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: size - line, height: size - line)
        .padding(line / 2)
        .animation(Motion.ease, value: v)
    }
}

struct Meter: View {
    let value: Double
    var color: Color?

    var body: some View {
        let v = min(max(value, 0), 1), c = color ?? level(v)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(c.opacity(0.18))
                Capsule().fill(LinearGradient(colors: [c.opacity(0.75), c], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, g.size.width * v))
            }
        }
        .frame(height: 8)
        .animation(Motion.ease, value: v)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(tr(text)).lineLimit(1)
        }
        .font(.system(size: 11, weight: .bold))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(.black.opacity(0.16), in: Capsule())
    }
}

/// List row that highlights on hover and tells its content whether it is hovered.
struct HoverRow<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @Local private var hover = false

    var body: some View {
        content(hover)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

/// Control Center–style tile: fills with the accent when on.
struct ToggleTile: View {
    let title: String, icon: String
    @Binding var on: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button { on.toggle() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(on ? Color.black.opacity(0.1) : Color.primary.opacity(0.07), in: Circle())
                Spacer(minLength: 0)
                Text(tr(title)).font(.system(size: 12, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(on ? "Aktif" : "Mati").font(.system(size: 10, weight: .medium)).opacity(0.65)
            }
            .foregroundStyle(on ? Palette.onAccent : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .padding(12)
            .background(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(0.035)), in: shape)
            .overlay(shape.strokeBorder(on ? .clear : Palette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Motion.snap, value: on)
    }
}

struct Action: View {
    let title: String, icon: String, run: () -> Void
    @Local private var hover = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: run) {
            HStack(spacing: 10) {
                IconBadge(icon: icon, size: 28)
                Text(tr(title)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(Color.primary.opacity(hover ? 0.07 : 0.035), in: shape)
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
