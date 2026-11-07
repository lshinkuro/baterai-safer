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

/// Each tab owns a two-stop gradient; everything in the tab takes its accent from it.
struct Theme {
    let a: Color, b: Color
    var gradient: LinearGradient { LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing) }

    static let mint = Theme(a: Color(hex: 0x34D399), b: Color(hex: 0x0EA5A4))
    static let electric = Theme(a: Color(hex: 0x60A5FA), b: Color(hex: 0x6366F1))
    static let coral = Theme(a: Color(hex: 0xFB7185), b: Color(hex: 0xF97316))
    static let violet = Theme(a: Color(hex: 0xC084FC), b: Color(hex: 0xEC4899))
    static let amber = Theme(a: Color(hex: 0xFBBF24), b: Color(hex: 0xF97316))
    static let rose = Theme(a: Color(hex: 0xF43F5E), b: Color(hex: 0xE11D48))
}

/// Vivid colors for icons, bars and badges (instead of the stock system palette).
enum Palette {
    static let green = Color(hex: 0x22C55E), teal = Color(hex: 0x14B8A6), blue = Color(hex: 0x3B82F6)
    static let indigo = Color(hex: 0x6366F1), violet = Color(hex: 0xA855F7), pink = Color(hex: 0xEC4899)
    static let red = Color(hex: 0xF43F5E), orange = Color(hex: 0xF97316), amber = Color(hex: 0xF59E0B)
    static let yellow = Color(hex: 0xEAB308), sky = Color(hex: 0x0EA5E9), slate = Color(hex: 0x64748B)
    static let cycle = [blue, pink, amber, teal, violet, orange, green, sky, red, indigo]
}

private struct AccentKey: EnvironmentKey { static let defaultValue = Theme.mint }
extension EnvironmentValues {
    var accent: Theme {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
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
    var theme: Theme { [Theme.mint, .electric, .coral, .violet][rawValue] }
    /// Baterai and Tools (where features are switched back on) can't be turned off.
    var enabled: Bool { self == .battery || self == .tools || FeatureFlags.isOn("panel.\(self)") }
}

struct TabBar: View {
    @Binding var tab: Int
    let tabs: [Tab]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { t in
                let on = tab == t.rawValue
                Button { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { tab = t.rawValue } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 11, weight: .bold))
                        Text(t.title).font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(on ? Color.white : Color.secondary)
                    .background {
                        if on {
                            Capsule().fill(t.theme.gradient)
                                .shadow(color: t.theme.b.opacity(0.45), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// Full-color card for the headline of a tab.
struct Hero<Content: View>: View {
    @Environment(\.accent) private var accent
    var theme: Theme?
    @ViewBuilder let content: Content

    var body: some View {
        let t = theme ?? accent
        content
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    t.gradient
                    // soft highlight + a big blurred blob for depth
                    LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
                    Circle().fill(.white.opacity(0.18)).frame(width: 180).blur(radius: 40).offset(x: 120, y: -60)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: t.b.opacity(0.35), radius: 14, y: 6)
    }
}

struct Card<Content: View>: View {
    @Environment(\.accent) private var accent
    let title: String?, icon: String?
    let content: Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let title {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(accent.gradient)
                    }
                    Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Colored rounded-square symbol (rows, lists).
struct IconBadge: View {
    let icon: String, color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct Switch: View {
    let title: String, icon: String, color: Color
    @Binding var on: Bool

    init(_ title: String, _ icon: String, _ on: Binding<Bool>, color: Color = Palette.blue) {
        self.title = title; self.icon = icon; self.color = color; _on = on
    }

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, color: color)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle(title, isOn: $on).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(color)
        }
    }
}

/// Bento tile: tinted background, big rounded number.
struct Tile: View {
    let icon: String, title: String, value: String, color: Color
    var help = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                .frame(width: 26, height: 26).background(color.opacity(0.18), in: Circle())
            Spacer(minLength: 2)
            Text(value).font(.system(size: 19, weight: .heavy, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(11)
        .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .help(help)
    }
}

/// A battery body with liquid fill and an optional limit line — the app's signature.
struct BatteryGlyph: View {
    let level: Double // 0...1
    var limit: Double?
    var charging = false

    var body: some View {
        let v = min(max(level, 0), 1)
        VStack(spacing: 3) {
            Capsule().fill(.white.opacity(0.55)).frame(width: 18, height: 5)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.18))
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 10, bottomTrailing: 10, topTrailing: 4), style: .continuous)
                        .fill(LinearGradient(colors: [.white, .white.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(8, (g.size.height - 8) * v))
                        .padding(4)
                    if let limit {
                        Rectangle().fill(.white).frame(height: 2)
                            .overlay(alignment: .trailing) { Text("\(Int(limit * 100))").font(.system(size: 8, weight: .heavy)).offset(x: 16) }
                            .offset(y: -(g.size.height - 8) * limit - 4)
                            .opacity(0.9)
                    }
                    if charging {
                        Image(systemName: "bolt.fill").font(.system(size: 18, weight: .black))
                            .foregroundStyle(.black.opacity(0.35))
                            .frame(maxHeight: .infinity)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 2))
            }
        }
        .frame(width: 52, height: 96)
        .animation(.spring(response: 0.6), value: v)
    }
}

/// Green → amber → red as a resource fills up.
func level(_ v: Double) -> Color { v > 0.85 ? Palette.red : v > 0.65 ? Palette.amber : Palette.green }

struct Ring: View {
    let value: Double // 0...1
    let color: Color
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
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .zero, endAngle: .degrees(360 * max(v, 0.01))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let marker {
                Capsule().fill(Color.primary).frame(width: 3, height: line + 5)
                    .offset(y: -(size - line) / 2).rotationEffect(.degrees(marker * 360))
            }
            VStack(spacing: 0) {
                Text(label).font(.system(size: size * 0.22, weight: .heavy, design: .rounded)).monospacedDigit()
                if let caption { Text(caption).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
            }
        }
        .frame(width: size - line, height: size - line)
        .padding(line / 2)
        .animation(.easeInOut, value: v)
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
        .animation(.easeInOut, value: v)
    }
}

struct StatusPill: View {
    let text: String
    var color: Color = .white

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.22), in: Capsule())
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

/// Control Center–style tile: fills with color when on.
struct ToggleTile: View {
    let title: String, icon: String, theme: Theme
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(on ? theme.b : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(on ? Color.white : Color.primary.opacity(0.08), in: Circle())
                Spacer(minLength: 0)
                Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(on ? "Aktif" : "Mati").font(.system(size: 10, weight: .semibold)).opacity(0.75)
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(11)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(on ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.05)))
            }
            .shadow(color: on ? theme.b.opacity(0.35) : .clear, radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: on)
    }
}

struct Action: View {
    let title: String, icon: String, color: Color, run: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                IconBadge(icon: icon, color: color, size: 30)
                Text(title).font(.system(size: 12.5, weight: .semibold, design: .rounded)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(color.opacity(hover ? 0.2 : 0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
