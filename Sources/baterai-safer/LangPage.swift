import SwiftUI

// Lainnya → Belajar Bahasa: the page itself, in the notch or in its own window. Model in Lang.swift.

enum LangWindow {
    static func show() { AppWindow.show("lang", title: tr("Belajar Bahasa"), size: NSSize(width: 920, height: 640)) { LangPage(windowed: true) } }
}

struct LangPage: View {
    @ObservedObject var m = LangModel.shared
    var windowed = false
    @AppStorage("langMode") private var mode = 0 // 0 kosakata, 1 kuis, 2 tes, 3 ngobrol, 4 progres, 5 pengaturan, 6 kesalahan, 7 daftar
    @AppStorage("langQuiz") private var quizKind = 0 // 0 pilihan ganda, 1 ketik, 2 dengar
    @AppStorage("langVoice") private var voiceMode = false
    @StateObject private var voice = VoiceChat()
    @Local private var input = ""
    @Local private var choosingLang = false
    @Local private var mistakeShown = false
    @Local private var editing: Word?
    @Local private var wordField = ""
    @Local private var meaningField = ""
    @Local private var exampleField = ""
    @Local private var search = ""
    @FocusState private var typing: Bool

    var tabs: [(id: Int, title: String)] {
        [(0, "Kosakata"), (1, "Kuis"), (2, m.testName), (3, "Ngobrol"), (6, "Kesalahan"), (7, "Daftar"), (4, "Progres"), (5, "⚙︎")]
    }
    var wordSize: CGFloat { windowed ? 56 : 34 }

    var body: some View {
        VStack(spacing: 8) {
            header
            switch mode {
            case 2: test
            case 3: talk
            case 4: progress
            case 5: settings
            case 6: mistakes
            case 7: wordList
            case 1: quiz
            default: flashcards
            }
        }
        .overlay(alignment: .topLeading) {
            if choosingLang {
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.001).onTapGesture { withAnimation(Motion.snap) { choosingLang = false } }
                    languageChoices.padding(.top, 32)
                }
                .transition(.opacity)
            }
        }
        .onAppear { if m.current == nil { m.next() } }
        .onDisappear { voice.stop() }
        .onChange(of: m.current) { _ in sayIfListening() }
    }

    func sayIfListening() { if mode == 1, quizKind == 2, let w = m.current { m.speak(w.word) } }

    // MARK: Header

    var header: some View {
        HStack(spacing: 5) {
            Button { withAnimation(Motion.snap) { choosingLang.toggle() } } label: {
                HStack(spacing: 5) {
                    Text(m.s.lang.flag).font(.system(size: 12))
                    Text(tr(m.s.lang.title)).font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.gray)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.white.opacity(choosingLang ? 0.14 : 0.09), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).fixedSize().tip("Pilih bahasa")
            HStack(spacing: 1) {
                ForEach(tabs, id: \.id) { t in
                    tab(t.title, on: mode == t.id, badge: t.id == 6 ? m.mistakes.count : 0) {
                        withAnimation(Motion.ease) { mode = t.id }
                        voice.stop()
                        if t.id < 2 { m.next() }
                    }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.07), in: Capsule())
            Spacer(minLength: 4)
            target
            if !windowed { NButton(icon: "arrow.up.left.and.arrow.down.right") { LangWindow.show() }.tip("Buka di jendela besar") }
        }
    }

    func tab(_ text: String, on: Bool, badge: Int, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 3) {
                Text(tr(text)).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
                if badge > 0 { Text("\(badge)").font(.system(size: 9, weight: .bold)).monospacedDigit().opacity(0.75) }
            }
            .foregroundStyle(on ? Palette.onAccent : .gray)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(on ? Palette.accent.opacity(0.9) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var languageChoices: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 2) {
            ForEach(Lang.allCases, id: \.self) { l in
                let on = m.s.lang == l
                Button {
                    voice.stop()
                    if !on { m.setLang(l); editing = nil }
                    withAnimation(Motion.snap) { choosingLang = false }
                } label: {
                    HStack(spacing: 8) {
                        Text(l.flag)
                        Text(tr(l.title)).font(.system(size: 12, weight: on ? .semibold : .regular))
                        Spacer(minLength: 12)
                        if on { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(on ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .frame(width: 160)
        .background(Color(hex: 0x1C1D1F), in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }

    var target: some View {
        HStack(spacing: 5) {
            Ring(value: min(1, Double(m.today) / Double(max(m.s.target, 1))), color: Palette.accent, label: "", size: 20, line: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(m.today)/\(m.s.target)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                Text("🔥 \(m.streak)").font(.system(size: 10)).foregroundStyle(.gray)
            }
        }
        .help("Target kata hari ini · streak")
    }

    // MARK: Shared pieces

    /// The lead card of a practice screen, with the language's flag as a faint watermark.
    func stage<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        NCard(padding: 14, glow: true) {
            ZStack(alignment: .bottomTrailing) {
                Text(m.s.lang.flag).font(.system(size: windowed ? 130 : 76)).opacity(0.09).accessibilityHidden(true)
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    func dots(_ box: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Circle().fill(i <= box ? Palette.accent : Color.white.opacity(0.15)).frame(width: 6, height: 6)
            }
        }
        .accessibilityElement().accessibilityLabel(String(format: tr("Kotak %@ dari 5"), "\(box)"))
    }

    func cardTop(_ w: Word) -> some View {
        HStack(spacing: 6) {
            dots(m.card(w).box)
            if m.isNew(w) { Chip(text: "Baru", color: Palette.accent) }
            Spacer()
            Text("\(m.dueCount) perlu diulang").font(.system(size: 10)).foregroundStyle(.gray).monospacedDigit()
        }
    }

    func bigAction(_ icon: String, _ title: String, _ color: Color, filled: Bool, _ run: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(tr(title)).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(filled ? Palette.onAccent : color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(filled ? color : Color.white.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    func speakButton(_ text: String) -> some View {
        Button { m.speak(text) } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 13)).foregroundStyle(Palette.accent) }
            .buttonStyle(.plain).tip("Dengarkan")
    }

    /// state: nil = neutral, true = the right answer, false = the wrong pick.
    func choice(_ letter: String, _ text: String, state: Bool?, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 8) {
                Text(letter).font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(state == nil ? 0.08 : 0.2), in: Circle())
                Text(text).font(.system(size: 11, weight: .semibold)).multilineTextAlignment(.leading).lineLimit(2)
                Spacer(minLength: 0)
                if let state { Image(systemName: state ? "checkmark" : "xmark").font(.system(size: 10, weight: .bold)) }
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(.horizontal, 7)
            .background(state == true ? Palette.green.opacity(0.5) : state == false ? Palette.red.opacity(0.5) : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func field(_ title: String, _ text: Binding<String>) -> some View {
        TextField(tr(title), text: text).textFieldStyle(.plain).font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.gray)
    }

    var addWordsButton: some View {
        NButton(icon: "sparkles", title: m.busy ? "Membuat…" : "Tambah kata (AI)", tint: Palette.accent) { m.addWords() }
            .disabled(m.busy || m.genStatus != nil).help(m.genStatus.map(tr) ?? String(format: tr("%@ membuat 8 kata baru"), m.engineName))
    }

    var allDone: some View {
        HStack(spacing: 22) {
            Ring(value: min(1, Double(m.today) / Double(max(m.s.target, 1))), color: Palette.accent, label: "\(m.today)/\(m.s.target)", size: 92, line: 9)
            VStack(alignment: .leading, spacing: 6) {
                Text("Semua kata sudah diulang 🎉").font(.system(size: 15, weight: .semibold))
                Text("🔥 \(m.streak) hari beruntun").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                Text("Kata berikutnya muncul sesuai jadwal hafalan. Mau tambah kata baru?").font(.system(size: 11)).foregroundStyle(.gray)
                HStack(spacing: 6) {
                    addWordsButton
                    NButton(icon: "plus", title: "Kata sendiri") { withAnimation(Motion.ease) { mode = 7 } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Kosakata

    @ViewBuilder var flashcards: some View {
        if let w = m.current {
            HStack(spacing: 10) {
                stage {
                    VStack(spacing: 6) {
                        cardTop(w)
                        Spacer(minLength: 0)
                        ZStack {
                            front(w).rotation3DEffect(.degrees(m.revealed ? -180 : 0), axis: (0, 1, 0)).opacity(m.revealed ? 0 : 1)
                            back(w).rotation3DEffect(.degrees(m.revealed ? 0 : 180), axis: (0, 1, 0)).opacity(m.revealed ? 1 : 0)
                        }
                        Spacer(minLength: 0)
                        Text("Naik kotak lewat Kuis Ketik atau Dengar").font(.system(size: 10)).foregroundStyle(.gray)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { reveal(w) }
                VStack(spacing: 6) {
                    if m.revealed {
                        bigAction("checkmark", "Hafal", Palette.green, filled: true) { m.answer(knew: true) }
                        bigAction("arrow.counterclockwise", "Belum hafal", Palette.red, filled: false) { m.answer(knew: false) }
                    } else {
                        bigAction("eye.fill", "Lihat arti", Palette.accent, filled: true) { reveal(w) }
                    }
                    addWordsButton
                }
                .frame(width: windowed ? 260 : 170)
            }
        } else {
            allDone
        }
    }

    func reveal(_ w: Word) {
        guard !m.revealed else { return }
        withAnimation(Motion.snap) { m.revealed = true }
        m.speak(w.word)
    }

    func front(_ w: Word) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(w.word).font(.system(size: wordSize, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                speakButton(w.word)
            }
            Text("Ketuk untuk lihat arti").font(.system(size: 11)).foregroundStyle(.gray)
        }
    }

    func back(_ w: Word) -> some View {
        VStack(spacing: 5) {
            Text(w.meaning).font(.system(size: windowed ? 26 : 20, weight: .semibold)).foregroundStyle(Palette.accent).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            Text(w.word).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            if !w.example.isEmpty {
                HStack(spacing: 6) {
                    Text(w.example).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).lineLimit(2)
                    speakButton(w.example)
                }
            }
        }
    }

    // MARK: Kuis

    var quizKinds: some View {
        HStack(spacing: 4) {
            ForEach(Array(["Pilih", "Ketik", "Dengar"].enumerated()), id: \.offset) { i, t in
                Button {
                    quizKind = i
                    m.next()
                    if i > 0 { typing = true }
                    sayIfListening()
                } label: {
                    Text(tr(t)).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(quizKind == i ? Palette.onAccent : .gray)
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(quizKind == i ? Palette.accent : Color.white.opacity(0.05), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder var quiz: some View {
        if let w = m.current {
            HStack(spacing: 10) {
                stage {
                    VStack(spacing: 6) {
                        cardTop(w)
                        Spacer(minLength: 0)
                        quizPrompt(w)
                        Spacer(minLength: 0)
                    }
                }
                VStack(spacing: 5) {
                    quizKinds
                    if quizKind == 0 {
                        ForEach(Array(m.options.enumerated()), id: \.offset) { i, o in
                            choice(["A", "B", "C", "D"][i], o, state: m.picked == nil ? nil : o == w.meaning ? true : m.picked == o ? false : nil) { m.pick(o) }
                        }
                    } else {
                        typedAnswer(w)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: windowed ? 300 : 230)
            }
        } else {
            allDone
        }
    }

    @ViewBuilder func quizPrompt(_ w: Word) -> some View {
        switch quizKind {
        case 1:
            VStack(spacing: 4) {
                Text("Tulis kata untuk").font(.system(size: 11)).foregroundStyle(.gray)
                Text(promptMeaning(w, m.s.lang)).font(.system(size: windowed ? 34 : 24, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            }
        case 2:
            VStack(spacing: 8) {
                Button { m.speak(w.word) } label: {
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 22)).foregroundStyle(Palette.onAccent)
                        .frame(width: 64, height: 64).background(Palette.accent, in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain).tip("Dengarkan")
                Text("Tulis kata yang kamu dengar").font(.system(size: 11)).foregroundStyle(.gray)
            }
        default:
            HStack(spacing: 10) {
                Text(w.word).font(.system(size: wordSize, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                speakButton(w.word)
            }
        }
    }

    func typedAnswer(_ w: Word) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(tr("Ketik jawaban…"), text: $m.typed).textFieldStyle(.plain).font(.system(size: 13))
                    .focused($typing).onSubmit { m.submitTyped(); typing = true }.disabled(m.typedResult != nil)
                Button { m.submitTyped(); typing = true } label: {
                    Image(systemName: m.typedResult == nil ? "arrow.up.circle.fill" : "arrow.right.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain).tip(m.typedResult == nil ? "Periksa" : "Berikutnya")
            }
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
            .background(Color.white.opacity(0.09), in: Capsule())
            .onAppear { typing = true }
            if let right = m.typedResult {
                Label(right ? "Benar, naik kotak" : "Belum tepat", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(right ? Palette.green : Palette.red)
                Text(w.word).font(.system(size: 15, weight: .semibold))
                Text(w.meaning).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(2)
            } else {
                Text("Enter untuk periksa").font(.system(size: 10)).foregroundStyle(.gray)
            }
        }
    }

    // MARK: Tes

    @ViewBuilder var test: some View {
        if m.questions.isEmpty {
            stage {
                VStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill").font(.system(size: 28)).foregroundStyle(Palette.accent)
                    Text(String(format: tr("Latihan soal %@"), m.testName)).font(.system(size: 15, weight: .semibold))
                    Text(String(format: tr("5 soal pilihan ganda dibuat oleh %@, lengkap dengan pembahasan. Skornya tersimpan di Progres."), m.engineName))
                        .font(.system(size: 11)).foregroundStyle(.gray).multilineTextAlignment(.center).frame(maxWidth: 380)
                    NButton(icon: m.busy ? "hourglass" : "play.fill", title: m.busy ? "Membuat soal…" : "Mulai tes", tint: Palette.accent, prominent: true) { m.startTest() }
                        .disabled(m.busy || m.genStatus != nil)
                    if let why = m.genStatus { Text(tr(why)).font(.system(size: 10)).foregroundStyle(Palette.amber) }
                }
            }
        } else if m.qIndex >= m.questions.count {
            stage {
                VStack(spacing: 8) {
                    Text("\(m.score)/\(m.questions.count)").font(.system(size: 40, weight: .semibold)).foregroundStyle(Palette.accent)
                    Text(m.score == m.questions.count ? "Sempurna! 🎉" : m.score * 2 >= m.questions.count ? "Bagus, terus latihan 💪" : "Ayo coba lagi, pelan-pelan 🙂")
                        .font(.system(size: 13, weight: .bold))
                    HStack {
                        NButton(icon: "arrow.clockwise", title: "Tes lagi", tint: Palette.accent, prominent: true) { m.startTest() }.disabled(m.busy)
                        NButton(icon: "chart.bar.fill", title: "Lihat progres") { mode = 4 }
                    }
                }
            }
        } else {
            let q = m.questions[m.qIndex]
            HStack(alignment: .top, spacing: 10) {
                NCard(padding: 14, glow: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOAL \(m.qIndex + 1)/\(m.questions.count) · skor \(m.score)").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
                        Text(q.q).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if m.chosen != nil, !q.why.isEmpty {
                            Text("💡 \(q.why)").font(.system(size: 11)).foregroundStyle(Palette.amber).lineLimit(4)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                VStack(spacing: 5) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                        choice(["A", "B", "C", "D"][i], o, state: m.chosen == nil ? nil : i == q.answer ? true : m.chosen == i ? false : nil) { m.choose(i) }
                    }
                    Spacer(minLength: 0)
                    if m.chosen != nil {
                        NButton(icon: "arrow.right", title: m.qIndex + 1 == m.questions.count ? "Lihat skor" : "Berikutnya", tint: Palette.accent, prominent: true) { m.nextQuestion() }
                    }
                }
                .frame(width: 250)
            }
        }
    }

    // MARK: Ngobrol

    @ViewBuilder var talk: some View {
        if let why = m.aiStatus {
            Placeholder(icon: "sparkles", title: String(format: tr("Ngobrol butuh %@"), m.engineName), subtitle: tr(why) + " · " + tr("ganti di ⚙︎"))
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    scenarioChip("Bebas", "bubble.left.and.bubble.right.fill", nil)
                    ForEach(LangModel.scenarios.indices, id: \.self) { i in scenarioChip(LangModel.scenarios[i].title, LangModel.scenarios[i].icon, i) }
                    Spacer(minLength: 4)
                    NButton(icon: voiceMode ? "keyboard" : "mic.fill", tint: voiceMode ? .white : Palette.accent) {
                        voiceMode.toggle()
                        voice.stop()
                    }
                    .tip(voiceMode ? "Ganti ke ketik" : "Ganti ke suara")
                }
                if voiceMode { voiceView } else { chatView }
            }
        }
    }

    func scenarioChip(_ title: String, _ icon: String, _ i: Int?) -> some View {
        let on = m.scenario == i
        return Button {
            voice.stop()
            if !on { m.startScenario(i) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                Text(tr(title)).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(on ? Palette.onAccent : .gray)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(on ? Palette.accent : Color.white.opacity(0.05), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(m.busy)
    }

    var voiceView: some View {
        let reply = m.chat.last(where: { !$0.me })?.text
        let status = switch voice.phase {
        case .idle: tr("Ketuk Poni untuk mulai bicara")
        case .listening: tr("Mendengarkan…")
        case .thinking: String(format: tr("%@ berpikir…"), m.engineName)
        case .speaking: tr("Bicara…")
        }
        return HStack(spacing: 18) {
            Button {
                if voice.phase == .idle {
                    voice.voiceID = m.voice?.identifier
                    voice.onUtterance = { t in
                        if !m.send(t, reply: { voice.say(spokenPart($0)) }) { voice.resume() }
                    }
                    voice.start(m.s.lang)
                } else {
                    voice.stop()
                }
            } label: {
                PoniFace(phase: voice.phase, level: voice.level).frame(width: 110, height: 110).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(voice.phase == .idle ? "Mulai" : "Berhenti")
            VStack(alignment: .leading, spacing: 6) {
                Text(status).font(.system(size: 14, weight: .semibold))
                if !voice.heard.isEmpty || voice.phase == .thinking {
                    Text(voice.heard.isEmpty ? (m.chat.last(where: { $0.me })?.text ?? "") : voice.heard)
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                }
                if let reply, voice.phase != .idle || !m.chat.isEmpty {
                    ForEach(Array(reply.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                        Text(LocalizedStringKey(String(line))).font(.system(size: line.hasPrefix("✏️") ? 11 : 12, weight: line.hasPrefix("✏️") ? .semibold : .regular))
                            .foregroundStyle(line.hasPrefix("✏️") ? Palette.amber : .white).lineLimit(3)
                    }
                }
                if let e = voice.error { Text(e).font(.system(size: 11)).foregroundStyle(Palette.red) }
                Spacer(minLength: 0)
                Text(voice.onDevice ? tr("Suara dikenali di Mac ini · ketuk Poni untuk berhenti")
                     : String(format: tr("Ucapan %@ dikenali lewat server Apple · ketuk Poni untuk berhenti"), tr(m.s.lang.title)))
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.leading, 16)
    }

    func bubble(_ c: (me: Bool, text: String)) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if c.me { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(c.text.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    Text(LocalizedStringKey(String(line))).font(.system(size: 12, weight: line.hasPrefix("✏️") ? .medium : .regular)).textSelection(.enabled)
                        .foregroundStyle(line.hasPrefix("✏️") ? Palette.amber : .white)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(c.me ? Palette.accent.opacity(0.22) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !c.me {
                speakButton(spokenPart(c.text))
                Spacer(minLength: 40)
            }
        }
    }

    var chatView: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if m.chat.isEmpty && !m.busy { Text(m.s.lang.tryHint).font(.system(size: 11)).foregroundStyle(.gray) }
                        ForEach(Array(m.chat.enumerated()), id: \.offset) { i, c in bubble(c).id(i) }
                        if m.busy { ProgressView().controlSize(.small) }
                    }
                }
                .onChange(of: m.chat.count) { n in withAnimation { proxy.scrollTo(n - 1) } }
            }
            HStack(spacing: 6) {
                TextField(m.s.lang.placeholder, text: $input).textFieldStyle(.plain)
                    .onSubmit { m.send(input); input = "" }
                Button { m.send(input); input = "" } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20)).foregroundStyle(Palette.accent) }
                    .buttonStyle(.plain).disabled(input.isEmpty || m.busy).tip("Kirim")
                NButton(icon: "square.and.pencil") { m.startScenario(m.scenario) }.tip("Percakapan baru")
            }
            .font(.system(size: 12))
            .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
            .background(Color.white.opacity(0.09), in: Capsule())
        }
    }

    // MARK: Kesalahan

    @ViewBuilder var mistakes: some View {
        if let x = m.dueMistake {
            HStack(spacing: 10) {
                stage {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            dots(x.card.box)
                            Spacer()
                            Text("\(m.mistakes.count) kesalahan tersimpan").font(.system(size: 10)).foregroundStyle(.gray).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        Text("Perbaiki atau jawab:").font(.system(size: 11)).foregroundStyle(.gray)
                        Text(x.prompt).font(.system(size: 15, weight: .semibold)).lineLimit(3).minimumScaleFactor(0.7)
                        if mistakeShown {
                            HStack(spacing: 6) {
                                Text(x.answer).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent).lineLimit(2)
                                speakButton(x.answer)
                            }
                            if !x.why.isEmpty { Text(x.why).font(.system(size: 11)).foregroundStyle(Palette.amber).lineLimit(2) }
                        }
                        Spacer(minLength: 0)
                    }
                }
                VStack(spacing: 6) {
                    if mistakeShown {
                        bigAction("checkmark", "Sudah bisa", Palette.green, filled: true) { gradeMistake(x, knew: true) }
                        bigAction("arrow.counterclockwise", "Ulangi lagi", Palette.red, filled: false) { gradeMistake(x, knew: false) }
                    } else {
                        bigAction("eye.fill", "Lihat jawaban", Palette.accent, filled: true) { withAnimation(Motion.ease) { mistakeShown = true } }
                    }
                }
                .frame(width: windowed ? 260 : 170)
            }
        } else {
            Placeholder(icon: "checkmark.seal", title: m.mistakes.isEmpty ? "Belum ada kesalahan" : "Semua sudah diulang hari ini",
                        subtitle: "Koreksi dari Ngobrol dan soal tes yang salah otomatis masuk ke sini")
        }
    }

    func gradeMistake(_ x: Mistake, knew: Bool) {
        mistakeShown = false
        withAnimation(Motion.ease) { m.grade(x, knew: knew) }
    }

    // MARK: Daftar kata

    var wordList: some View {
        HStack(alignment: .top, spacing: 10) {
            NCard(padding: 12, glow: true) {
                VStack(alignment: .leading, spacing: 6) {
                    heading(editing == nil ? tr("TAMBAH KATA") : tr("UBAH KATA"))
                    field("Kata", $wordField)
                    field("Arti", $meaningField)
                    field("Contoh kalimat (boleh kosong)", $exampleField)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        NButton(icon: "checkmark", title: "Simpan", tint: Palette.accent, prominent: true) { saveField() }
                        if editing != nil { NButton(icon: "xmark", title: "Batal") { clearFields() } }
                    }
                }
            }
            .frame(width: windowed ? 320 : 230)
            NCard(padding: 12) {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.gray)
                        TextField(String(format: tr("Cari di %@ kata"), "\(m.deck.count)"), text: $search).textFieldStyle(.plain).font(.system(size: 12))
                    }
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 3) {
                            ForEach(m.deck.filter { search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) || $0.meaning.localizedCaseInsensitiveContains(search) }, id: \.word) { w in wordRow(w) }
                        }
                    }
                }
            }
        }
    }

    func wordRow(_ w: Word) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(w.word).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(w.meaning).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
            }
            Spacer(minLength: 4)
            dots(m.card(w).box)
            Menu {
                Button(tr("Ubah")) { edit(w) }
                Button(tr("Hapus"), role: .destructive) { remove(w) }
            } label: { Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(.gray).frame(width: 18, height: 18) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tip("Lainnya")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(editing == w ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            Button(tr("Ubah")) { edit(w) }
            Button(tr("Hapus"), role: .destructive) { remove(w) }
        }
    }

    func edit(_ w: Word) { editing = w; wordField = w.word; meaningField = w.meaning; exampleField = w.example }
    func clearFields() { editing = nil; wordField = ""; meaningField = ""; exampleField = "" }

    func saveField() {
        if m.saveWord(word: wordField, meaning: meaningField, example: exampleField, replacing: editing) { clearFields() }
    }

    func remove(_ w: Word) {
        guard confirm(String(format: tr("Hapus \"%@\"?"), w.word), tr("Progres hafalan kata ini ikut terhapus."), tr("Hapus")) else { return }
        if editing == w { clearFields() }
        m.deleteWord(w)
    }

    // MARK: Progres

    var progress: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    stat("\(m.mastered)", "hafal", Palette.green)
                    stat("\(m.learning)", "dipelajari", Palette.accent)
                }
                HStack(spacing: 8) {
                    stat(m.accuracy.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", "akurasi 7 hari", .white)
                    stat("🔥\(m.streak)", "hari beruntun", Palette.accent)
                }
            }
            .frame(width: 210)
            NCard(padding: 10, glow: true) { journey }.frame(width: 170)
            NCard(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    heading(String(format: tr("LATIHAN 7 HARI · %@"), tr(m.s.lang.title).uppercased()))
                    let week = m.week, peak = max(week.map(\.n).max() ?? 0, 1)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, d in
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 4).fill(Palette.accent.gradient).frame(height: max(2, 56 * CGFloat(d.n) / CGFloat(peak)))
                                Text(d.day).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 72, alignment: .bottom)
                    heading(String(format: tr("TES %@"), m.testName))
                    if m.tests.isEmpty {
                        Text(String(format: tr("Belum ada. Coba tab %@."), m.testName)).font(.system(size: 11)).foregroundStyle(.gray)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(m.tests.suffix(4).enumerated()), id: \.offset) { _, t in
                                VStack(spacing: 1) {
                                    Text("\(t.score)/\(t.total)").font(.system(size: 12, weight: .semibold))
                                    Text(t.date.formatted(.dateTime.day().month(.abbreviated).locale(appLocale))).font(.system(size: 9)).foregroundStyle(.gray).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 4)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// How the deck is spread over the Leitner boxes.
    var journey: some View {
        let counts = m.boxCounts, peak = max(counts.max() ?? 0, 1), names = ["Baru", "0", "1", "2", "3", "4", "5"]
        return VStack(alignment: .leading, spacing: 5) {
            heading(tr("PERJALANAN HAFALAN"))
            ForEach(counts.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Text(tr(names[i])).font(.system(size: 10)).foregroundStyle(.gray).frame(width: 30, alignment: .leading)
                    GeometryReader { geo in
                        Capsule().fill(Palette.accent.opacity(0.3 + 0.7 * Double(i) / 6))
                            .frame(width: max(3, geo.size.width * CGFloat(counts[i]) / CGFloat(peak)))
                    }
                    .frame(height: 8)
                    Text("\(counts[i])").font(.system(size: 10, weight: .semibold)).monospacedDigit().frame(width: 24, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        NCard(padding: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(color)
                Text(tr(label)).font(.system(size: 10)).foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: Pengaturan

    var settings: some View {
        HStack(alignment: .top, spacing: 10) {
            NCard(padding: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    heading(tr("TEMAN NGOBROL & PEMBUAT SOAL"))
                    engine("apple", "Apple Intelligence", "Di Mac, offline, gratis", LangModel.appleStatus)
                    if !Lite.on { engine("claude", "Claude", "Lebih pintar, lewat Claude Code", LangModel.claude == nil ? "Claude Code belum terpasang" : nil) }
                    HStack {
                        Text("Target harian").font(.system(size: 11))
                        Spacer()
                        Stepper(String(format: tr("%@ kata"), "\(m.s.target)"), value: Binding(get: { m.s.target }, set: { m.s.target = $0; m.persist(); m.next() }), in: 5...50, step: 5)
                            .font(.system(size: 11)).controlSize(.small)
                    }
                    Text(String(format: tr("Maksimal %@ kata baru per hari"), "\(m.newLimit)")).font(.system(size: 10)).foregroundStyle(.gray)
                }
            }
            NCard(padding: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    heading(String(format: tr("SUARA %@"), tr(m.s.lang.title).uppercased()))
                    HStack {
                        Picker("", selection: Binding(get: { m.voice?.identifier ?? "" }, set: { m.s.voices[m.s.lang.rawValue] = $0; m.persist(); m.speak(m.s.lang.sample) })) {
                            ForEach(m.voices, id: \.identifier) { v in
                                Text(v.name + (v.quality == .premium ? " · Premium" : v.quality == .enhanced ? " · Enhanced" : "") + " (\(v.language))").tag(v.identifier)
                            }
                        }
                        .labelsHidden().controlSize(.small)
                        Button { m.speak(m.s.lang.sample) } label: { Image(systemName: "play.circle.fill").font(.system(size: 18)).foregroundStyle(Palette.accent) }
                            .buttonStyle(.plain).tip("Dengarkan")
                    }
                    NButton(icon: "arrow.down.circle", title: "Unduh suara lain", tint: Palette.accent) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!)
                    }
                    Spacer(minLength: 0)
                    Button { m.s.reminder.toggle(); m.persist(); m.scheduleReminder(force: true) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: m.s.reminder ? "checkmark.circle.fill" : "circle").font(.system(size: 13)).foregroundStyle(m.s.reminder ? Palette.accent : .gray)
                            Text("Ingatkan belajar tiap hari").font(.system(size: 12))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(tr(m.s.reminder ? "Nyala" : "Mati"))
                    if m.s.reminder {
                        Stepper(String(format: tr("Jam %@.00"), String(format: "%02d", m.s.reminderHour)),
                                value: Binding(get: { m.s.reminderHour }, set: { m.s.reminderHour = $0; m.persist(); m.scheduleReminder(force: true) }), in: 5...23)
                            .font(.system(size: 11)).controlSize(.small)
                    }
                }
            }
        }
    }

    func engine(_ id: String, _ title: String, _ note: String, _ problem: String?) -> some View {
        let on = m.s.engine == id
        return Button { m.setEngine(id) } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle").foregroundStyle(on ? Palette.accent : .gray)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr(title)).font(.system(size: 12, weight: .bold))
                    Text(tr(problem ?? note)).font(.system(size: 10)).foregroundStyle(problem == nil ? Color.gray : Palette.amber)
                }
                Spacer()
            }
            .padding(7)
            .background(on ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
