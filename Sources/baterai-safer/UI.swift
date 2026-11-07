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

enum Tab: Int, CaseIterable {
    case battery, system, cleaner, tools
    var title: String { ["Baterai", "Sistem", "Cleaner", "Tools"][rawValue] }
    var icon: String { ["battery.75percent", "cpu", "sparkles", "square.grid.2x2"][rawValue] }
}

struct TabBar: View {
    @Binding var tab: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases, id: \.self) { t in
                let on = tab == t.rawValue
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { tab = t.rawValue } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.icon).font(.system(size: 11, weight: .semibold))
                        Text(t.title).font(.system(size: 12, weight: on ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? Color.primary : Color.secondary)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct Card<Content: View>: View {
    let title: String?, icon: String?
    let content: Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(spacing: 5) {
                    if let icon { Image(systemName: icon) }
                    Text(title)
                }
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// System Settings–style colored symbol.
struct IconBadge: View {
    let icon: String, color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

struct Switch: View {
    let title: String, icon: String, color: Color
    @Binding var on: Bool

    init(_ title: String, _ icon: String, _ on: Binding<Bool>, color: Color = .blue) {
        self.title = title; self.icon = icon; self.color = color; _on = on
    }

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, color: color)
            Text(title)
            Spacer()
            Toggle(title, isOn: $on).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct Tile: View {
    let icon: String, title: String, value: String, color: Color
    var help = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .help(help)
    }
}

/// Green → orange → red as a resource fills up.
func level(_ v: Double) -> Color { v > 0.85 ? .red : v > 0.65 ? .orange : .green }

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
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: line)
            Circle().trim(from: 0, to: v)
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center, startAngle: .zero, endAngle: .degrees(360 * max(v, 0.01))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let marker {
                Capsule().fill(Color.primary).frame(width: 3, height: line + 5)
                    .offset(y: -(size - line) / 2).rotationEffect(.degrees(marker * 360))
            }
            VStack(spacing: 0) {
                Text(label).font(.system(size: size * 0.22, weight: .bold, design: .rounded)).monospacedDigit()
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

    var body: some View {
        let v = min(max(value, 0), 1)
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(level(v).gradient).frame(width: g.size.width * v)
            }
        }
        .frame(height: 6)
        .animation(.easeInOut, value: v)
    }
}

struct StatusPill: View {
    let text: String, color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
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

/// Control Center–style tile: tap to toggle, lights up when on.
struct ToggleTile: View {
    let title: String, icon: String, color: Color
    @Binding var on: Bool

    var body: some View {
        Button { on.toggle() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(on ? AnyShapeStyle(color.gradient) : AnyShapeStyle(Color.primary.opacity(0.1)), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(on ? "Aktif" : "Mati").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(10)
            .background(Color.primary.opacity(on ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? color.opacity(0.5) : Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: on)
    }
}

struct Action: View {
    let title: String, icon: String, color: Color, run: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 10) {
                IconBadge(icon: icon, color: color, size: 28)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(Color.primary.opacity(hover ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
