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
        case .home: AnyView(HomeView(m: n.media, f: n.focus))
        case .music: AnyView(MusicView(m: n.media))
        case .focus: AnyView(FocusView(f: n.focus, n: n.notes))
        case .ai: AnyView(AIView(ai: n.ai))
        case .notes: AnyView(NotesView(n: n.notes, ai: n.ai))
        case .dev: AnyView(DevView())
        case .clipboard: AnyView(ClipView(c: n.clips))
        case .shelf: AnyView(ShelfView(s: n.shelf, dropping: false))
        case .git: AnyView(GitView(g: n.git, pr: n.pr, ai: n.ai))
        case .stats: AnyView(StatsView(s: n.sys))
        case .ibadah: AnyView(IbadahView())
        default: AnyView(MoreView())
        }
        if t == .more {
            HangmanGame.shared.game = Hangman(word: "PENGUIN", guessed: ["P", "N", "A", "S"])
            for (i, name) in [(0, "ular"), (1, "kartu"), (2, "xo"), (4, "catur"), (5, "hangman"), (6, "sudoku"), (7, "tetris"), (8, "desa")] {
                UserDefaults.standard.set(i, forKey: "game")
                write("game-\(name)", GamesPage().padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16).foregroundStyle(.white).frame(width: 720, height: 232).background(Color.black), .dark)
            }
        }
        if t == .ibadah {
            for (name, pane) in [("notch-Ramadan", AnyView(RamadanPane())), ("notch-Zakat", AnyView(ZakatPane()))] {
                write(name, pane.padding(.horizontal, 18).padding(.vertical, 12).foregroundStyle(.white).frame(width: 470, height: 200).background(Color.black), .dark)
            }
        }
        if t == .more {
            for (i, name) in ["hari", "kebiasaan", "minggu", "pengingat"].enumerated() {
                UserDefaults.standard.set(i, forKey: "selfcarePage")
                write("care-\(name)", SelfCareView().padding(.horizontal, 18).padding(.vertical, 8).foregroundStyle(.white).frame(width: 720, height: 190).background(Color.black), .dark)
            }
            SelfCare.shared.startBreak(.stretch)
            write("care-istirahat", SelfCareView().padding(.horizontal, 18).padding(.vertical, 8).foregroundStyle(.white).frame(width: 720, height: 190).background(Color.black), .dark)
            SelfCare.shared.cancelBreak()
        }
        if t == .more {
            let lm = LangModel.shared
            lm.next()
            lm.s.mistakes.append(Mistake(lang: lm.s.lang, prompt: "She go to school every day.", answer: "She goes to school every day.", why: "Subjek she butuh goes."))
            for (name, mode, quiz) in [("kartu", 0, 0), ("kuis", 1, 0), ("ketik", 1, 1), ("dengar", 1, 2), ("tes", 2, 0), ("ngobrol", 3, 0), ("progres", 4, 0), ("atur", 5, 0), ("salah", 6, 0), ("daftar", 7, 0)] {
                UserDefaults.standard.set(mode, forKey: "langMode"); UserDefaults.standard.set(quiz, forKey: "langQuiz")
                write("lang-\(name)", LangPage().padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16).foregroundStyle(.white).frame(width: 720, height: 232).background(Color.black), .dark)
            }
            UserDefaults.standard.set(3, forKey: "langMode"); UserDefaults.standard.set(true, forKey: "langVoice")
            write("lang-suara", LangPage().padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16).foregroundStyle(.white).frame(width: 720, height: 232).background(Color.black), .dark)
            UserDefaults.standard.set(false, forKey: "langVoice")
            write("lang-wajah", HStack(spacing: 30) { ForEach([VoiceChat.Phase.idle, .listening, .thinking, .speaking], id: \.self) { PoniFace(phase: $0, level: 0.7).frame(width: 110, height: 110) } }.padding(30).background(Color.black), .dark)
            write("lang-window", LangPage(windowed: true).padding(20).foregroundStyle(.white).frame(width: 920, height: 640).background(Color.black), .dark)
            lm.s.mistakes.removeLast()
        }
        if t == .more {
            write("game-catur-window", ChessView(windowed: true).padding(20).foregroundStyle(.white).frame(width: 820, height: 584).background(Color.black), .dark)
        }
        let v = content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
            .foregroundStyle(.white)
            .frame(width: 720, height: 270).background(Color.black)
        write("notch-\(t.title)", v, .dark)
        if t == .home {
            UserDefaults.standard.set("stats,todo,water", forKey: "homeWidgets")
            write("notch-Home-stats", v, .dark)
            UserDefaults.standard.removeObject(forKey: "homeWidgets")
            UserDefaults.standard.set(true, forKey: "downloadAlert")
            write("notch-toggles", QuickToggles(state: n.state).padding(8).foregroundStyle(.white).background(Color.black), .dark)
            UserDefaults.standard.removeObject(forKey: "downloadAlert")
            n.media.app = "Spotify"; n.media.title = "Sample Track"; n.media.artist = "Sample Artist"; n.media.duration = 200; n.media.position = 70; n.media.playing = true
            write("notch-Home-playing", v, .dark)
            n.media.app = nil; n.media.title = ""; n.media.playing = false
        }
    }
}
