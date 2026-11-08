import SwiftUI

// Render harness for the poni-ui-check skill: copied into a scratch copy of the repo, never into Sources/.
@MainActor func snap(_ dir: String) {
    _ = NSApplication.shared
    func write<V: View>(_ name: String, _ v: V, _ scheme: ColorScheme) {
        let r = ImageRenderer(content: v.environment(\.colorScheme, scheme))
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("fail", name); return }
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    let m = Model(), sys = SystemModel(), cleaner = CleanerModel(), tools = ToolsModel.shared
    for scheme in [ColorScheme.light, .dark] {
        let bg = scheme == .dark ? Color(white: 0.13) : Color(white: 0.96)
        for t in Tab.allCases {
            let content: AnyView = switch t {
            case .battery: AnyView(BatteryTab(m: m))
            case .system: AnyView(SystemTab(s: sys))
            case .cleaner: AnyView(CleanerTab(c: cleaner))
            case .tools: AnyView(ToolsTab(t: tools))
            }
            let v = VStack(spacing: 0) {
                TabBar(tab: .constant(t.rawValue), tabs: Tab.allCases).padding(.horizontal, 14).padding(.top, 12)
                content.padding(16)
            }
            .frame(width: 400).fixedSize(horizontal: false, vertical: true)
            .background(alignment: .top) {
                RadialGradient(colors: [Palette.accent.opacity(0.1), .clear], center: .top, startRadius: 0, endRadius: 330).frame(height: 330)
            }
            .background(bg)
            write("panel-\(t.title)-\(scheme)", v, scheme)
        }
    }
    let n = Notch.shared
    for t in NTab.allCases where t != .agenda {
        let content: AnyView = switch t {
        case .music: AnyView(MusicView(m: n.media))
        case .focus: AnyView(FocusView(f: n.focus, n: n.notes))
        case .ai: AnyView(AIView(ai: n.ai))
        case .notes: AnyView(NotesView(n: n.notes, ai: n.ai))
        case .dev: AnyView(DevView())
        case .clipboard: AnyView(ClipView(c: n.clips))
        case .shelf: AnyView(ShelfView(s: n.shelf, dropping: false))
        case .git: AnyView(GitView(g: n.git, pr: n.pr, ai: n.ai))
        case .stats: AnyView(StatsView(s: n.sys))
        default: AnyView(MoreView())
        }
        if t == .more {
            for (i, name) in ["ular", "kartu", "xo"].enumerated() {
                UserDefaults.standard.set(i, forKey: "game")
                write("game-\(name)", GamesPage().padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16).foregroundStyle(.white).frame(width: 720, height: 232).background(Color.black), .dark)
            }
        }
        let v = content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
            .foregroundStyle(.white)
            .frame(width: 720, height: 270).background(Color.black)
        write("notch-\(t.title)", v, .dark)
    }
}
