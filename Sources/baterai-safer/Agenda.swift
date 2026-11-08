import SwiftUI
import EventKit

// "Rapat" tab: a month calendar backed by macOS Calendar (EventKit), so events sync via iCloud and
// reminders are Calendar's own alarms, which fire even when this app isn't running.

/// Cells for a month view: leading nils up to the first weekday, then each day; padded to whole weeks.
func monthGrid(_ month: Date, _ cal: Calendar = .current) -> [Date?] {
    guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
          let days = cal.range(of: .day, in: .month, for: start)?.count else { return [] }
    let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
    var cells: [Date?] = Array(repeating: nil, count: lead) + (0..<days).map { cal.date(byAdding: .day, value: $0, to: start) }
    while cells.count % 7 != 0 { cells.append(nil) }
    return cells
}

/// Minutes before the event; nil = no reminder.
let reminderChoices: [Int?] = [nil, 5, 10, 15, 30, 60]
func durationLabel(_ m: Int) -> String {
    m < 60 ? "\(m) menit" : m % 60 == 0 ? "\(m / 60) jam" : "\(m / 60) jam \(m % 60) menit"
}
func shortDuration(_ m: Int) -> String { m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)j" : "\(m / 60)j \(m % 60)m" }
func shortReminder(_ m: Int) -> String { m == 60 ? "1j" : "\(m)m" }

/// "berlangsung" while it runs, "25m lagi" / "2j lagi" within 12 hours, nil otherwise.
func eventStatus(start: Date, end: Date, now: Date) -> (text: String, live: Bool)? {
    if start <= now && now < end { return ("berlangsung", true) }
    let mins = Int(start.timeIntervalSince(now) / 60)
    guard mins >= 0, mins < 12 * 60 else { return nil }
    return (mins < 60 ? "\(max(mins, 1))m lagi" : "\(mins / 60)j lagi", false)
}

func reminderLabel(_ m: Int?) -> String { m.map { $0 == 60 ? "1 jam sebelum" : "\($0) menit sebelum" } ?? "Tanpa pengingat" }

final class AgendaModel: ObservableObject {
    static let shared = AgendaModel()
    let store = EKEventStore()
    @Published var access: Bool?            // nil until asked
    @Published var month = Date()
    @Published var selected = Calendar.current.startOfDay(for: Date())
    @Published var events: [EKEvent] = []   // the visible month

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.reload() }
    }

    func start() {
        guard access == nil else { reload(); return }
        let done = { (ok: Bool) in DispatchQueue.main.async { self.access = ok; self.reload() } }
        if #available(macOS 14, *) { store.requestFullAccessToEvents { ok, _ in done(ok) } } else { store.requestAccess(to: .event) { ok, _ in done(ok) } }
    }

    func reload() {
        guard access == true else { return }
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
    }

    func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month) ?? month
        reload()
    }

    func on(_ day: Date) -> [EKEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) || ($0.isAllDay && $0.startDate <= day && day < $0.endDate) }
    }

    /// Returns an error message, or nil when saved.
    func add(title: String, start: Date, minutes: Int, reminder: Int?) -> String? {
        guard let calendar = store.defaultCalendarForNewEvents else { return "Tidak ada kalender untuk menyimpan" }
        let e = EKEvent(eventStore: store)
        e.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Rapat" : title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes) * 60)
        e.calendar = calendar
        setReminder(e, reminder, save: false)
        do { try store.save(e, span: .thisEvent) } catch { return "Gagal menyimpan: \(error.localizedDescription)" }
        reload()
        return nil
    }

    /// Returns an error message, or nil when saved. Recurring events change this occurrence only.
    func update(_ e: EKEvent, title: String, start: Date, minutes: Int, reminder: Int?) -> String? {
        e.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Rapat" : title
        e.startDate = start
        e.endDate = start.addingTimeInterval(Double(minutes) * 60)
        setReminder(e, reminder, save: false)
        do { try store.save(e, span: .thisEvent) } catch { return "Gagal menyimpan: \(error.localizedDescription)" }
        selected = Calendar.current.startOfDay(for: start)
        if !Calendar.current.isDate(start, equalTo: month, toGranularity: .month) { month = start }
        reload()
        return nil
    }

    func reminder(_ e: EKEvent) -> Int? { e.alarms?.first.map { Int(-$0.relativeOffset / 60) } }

    func setReminder(_ e: EKEvent, _ minutes: Int?, save: Bool = true) {
        e.alarms?.forEach { e.removeAlarm($0) }
        if let minutes { e.addAlarm(EKAlarm(relativeOffset: -Double(minutes) * 60)) }
        if save { try? store.save(e, span: .thisEvent); reload() }
    }

    func delete(_ e: EKEvent) { try? store.remove(e, span: .thisEvent); reload() }
}

struct AgendaView: View {
    @ObservedObject var a = AgendaModel.shared
    @AppStorage("agendaReminder") private var defaultReminder = 10 // -1 = none
    @Local private var adding = false
    @Local private var editing: EKEvent?   // nil while adding a new one
    @Local private var title = ""
    @Local private var when = Date()
    @Local private var minutes = 60
    @Local private var reminder: Int? = 10
    @Local private var error = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            switch a.access {
            case false?:
                Placeholder(icon: "calendar.badge.exclamationmark", title: "Izin Kalender ditolak",
                            subtitle: "System Settings → Privacy & Security → Calendars → Poni")
            case nil:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                HStack(spacing: 12) {
                    NCard(padding: 10) { month }.frame(width: 250)
                    if adding { form } else { dayList }
                }
            }
        }
        .onAppear { a.start() }
    }

    var month: some View {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
        return VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(a.month.formatted(.dateTime.month(.wide).year().locale(appLocale)).capitalized)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                navButton("chevron.left") { a.shift(-1) }
                Button { a.month = Date(); pick(cal.startOfDay(for: Date())); a.reload() } label: {
                    Text("Hari ini").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3).background(Palette.accent.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                navButton("chevron.right") { a.shift(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                }
                ForEach(Array(monthGrid(a.month).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 24) }
                }
            }
        }
    }

    func navButton(_ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 20)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let on = cal.isDate(day, inSameDayAs: a.selected), today = cal.isDateInToday(day)
        let count = a.on(day).count, past = day < cal.startOfDay(for: Date())
        return Button { pick(day) } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))").font(.system(size: 11, weight: on || today ? .bold : .medium))
                HStack(spacing: 2) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in Circle().frame(width: 3.5, height: 3.5) }
                }
                .frame(height: 3.5)
                .foregroundStyle(on ? Color.white : Palette.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 24)
            .foregroundStyle(on ? Palette.onAccent : past ? .white.opacity(0.35) : .white.opacity(0.9))
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.accent)
                } else if today {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Picking a day while the form is open moves the event there, keeping its time.
    func pick(_ day: Date) {
        a.selected = day
        guard adding else { return }
        let cal = Calendar.current, t = cal.dateComponents([.hour, .minute], from: when)
        when = cal.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? when
    }

    var dayList: some View {
        let cal = Calendar.current, list = a.on(a.selected)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(cal.component(.day, from: a.selected))").font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.selected.formatted(.dateTime.weekday(.wide).locale(appLocale)).capitalized)
                        .font(.system(size: 13, weight: .bold))
                    Text(list.isEmpty ? a.selected.formatted(.dateTime.month(.wide).year().locale(appLocale))
                         : "\(list.count) acara")
                        .font(.system(size: 11)).foregroundStyle(.gray)
                }
                Spacer()
                NButton(icon: "plus", title: "Tambah", tint: Palette.accent, prominent: true) { startAdding() }
            }
            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(Palette.accent.opacity(0.8))
                    Text("Hari ini kosong").font(.system(size: 12, weight: .semibold))
                    Text("Tambah rapat, nanti diingatkan sebelum mulai.").font(.system(size: 11)).foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(Color.white.opacity(0.15)))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(list, id: \.calendarItemIdentifier) { e in row(e) }
                    }
                }
            }
        }
    }

    func row(_ e: EKEvent) -> some View {
        let r = a.reminder(e), editable = e.calendar?.allowsContentModifications == true
        let color = Color(nsColor: e.calendar?.color ?? .systemBlue)
        let link = meetingLink([e.url?.absoluteString, e.location, e.notes])
        let status = e.isAllDay ? nil : eventStatus(start: e.startDate, end: e.endDate, now: Date())
        return HStack(spacing: 10) {
            Button { if editable { startEditing(e) } } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(e.isAllDay ? "Hari" : e.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        Text(e.isAllDay ? "penuh" : durationLabel(Int(e.endDate.timeIntervalSince(e.startDate) / 60)))
                            .font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
                    }
                    .frame(width: 52, alignment: .trailing)
                    Capsule().fill(color).frame(width: 3, height: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(e.title ?? "Rapat").font(.system(size: 12, weight: .bold)).lineLimit(1)
                        HStack(spacing: 4) {
                            if let status { Chip(text: status.text, icon: status.live ? "dot.radiowaves.left.and.right" : "clock", color: status.live ? Palette.green : Palette.accent) }
                            if let r { Chip(text: shortReminder(r), icon: "bell.fill", color: Palette.amber) }
                            if !editable { Chip(text: "hanya baca", icon: "lock.fill", color: .gray) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(editable ? "Klik untuk edit" : "\(e.calendar?.title ?? "Kalender") hanya bisa dibaca")
            if let link { NButton(icon: "video.fill", title: "Join", tint: Palette.green, prominent: true) { NSWorkspace.shared.open(link) } }
            if editable {
                Menu {
                    ForEach(Array(reminderChoices.enumerated()), id: \.offset) { _, m in
                        Button { a.setReminder(e, m) } label: {
                            if m == r { Label(reminderLabel(m), systemImage: "checkmark") } else { Text(reminderLabel(m)) }
                        }
                    }
                } label: {
                    Image(systemName: r == nil ? "bell.slash" : "bell.fill").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(r == nil ? Color.gray : Palette.amber)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(reminderLabel(r))
                Menu { actions(e) } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tip("Edit atau hapus")
            }
        }
        .contextMenu { if editable { actions(e) } }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.05)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    var form: some View {
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(editing == nil ? "Rapat baru" : "Edit rapat").font(.system(size: 13, weight: .semibold))
                Text(when.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(appLocale)))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                Spacer()
                Text("pilih tanggal di kalender").font(.system(size: 10)).foregroundStyle(.gray)
            }
            HStack(spacing: 6) {
                Image(systemName: "pencil").foregroundStyle(Palette.accent)
                TextField("Judul, mis. Standup tim", text: $title).textFieldStyle(.plain).focused($focused).onSubmit(save)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(0.09), in: Capsule())
            HStack(spacing: 6) {
                Text(when.formatted(date: .omitted, time: .shortened)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .frame(width: 70, alignment: .leading)
                stepButton("minus") { when = when.addingTimeInterval(-15 * 60) }
                stepButton("plus") { when = when.addingTimeInterval(15 * 60) }
                Spacer(minLength: 4)
                ForEach([9, 10, 13, 15], id: \.self) { h in
                    let on = cal.component(.hour, from: when) == h && cal.component(.minute, from: when) == 0
                    chip(String(format: "%02d.00", h), on: on) { when = cal.date(bySettingHour: h, minute: 0, second: 0, of: when) ?? when }
                }
            }
            row("Durasi", "hourglass") {
                ForEach(Set([15, 30, 45, 60, 90, 120, minutes]).sorted(), id: \.self) { m in
                    chip(shortDuration(m), on: minutes == m) { minutes = m }
                }
            }
            row("Ingatkan", "bell.fill") {
                ForEach(Array(reminderChoices.enumerated()), id: \.offset) { _, m in
                    chip(m.map(shortReminder) ?? "Mati", on: reminder == m) { reminder = m }
                }
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(Palette.red) }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let e = editing {
                    NButton(icon: "trash", tint: Palette.red) { remove(e) }.tip("Hapus")
                }
                Text("Tersimpan ke Kalender macOS").font(.system(size: 10)).foregroundStyle(.gray)
                Spacer()
                NButton(icon: "xmark", title: "Batal") { adding = false }
                NButton(icon: "checkmark", title: "Simpan", tint: Palette.accent, prominent: true, run: save)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func row<C: View>(_ label: String, _ icon: String, @ViewBuilder _ chips: () -> C) -> some View {
        HStack(spacing: 5) {
            Label(label, systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.gray).frame(width: 74, alignment: .leading)
            chips()
        }
    }

    func chip(_ text: String, on: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(tr(text)).font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? Palette.onAccent : .white.opacity(0.6))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.white.opacity(0.07)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    func stepButton(_ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
                .background(Color.white.opacity(0.09), in: Circle())
        }
        .buttonStyle(.plain).help("15 menit")
    }

    func startAdding() {
        editing = nil
        // Next whole hour on today, 09.00 on other days.
        let cal = Calendar.current, now = Date()
        when = cal.isDateInToday(a.selected)
            ? cal.date(bySetting: .minute, value: 0, of: now.addingTimeInterval(3600)) ?? now
            : cal.date(bySettingHour: 9, minute: 0, second: 0, of: a.selected) ?? a.selected
        minutes = 60
        title = ""
        error = ""
        reminder = defaultReminder < 0 ? nil : defaultReminder
        adding = true
        focused = true
    }

    @ViewBuilder func actions(_ e: EKEvent) -> some View {
        Button { startEditing(e) } label: { Label(tr("Edit"), systemImage: "pencil") }
        Button(role: .destructive) { remove(e) } label: { Label(tr("Hapus"), systemImage: "trash") }
    }

    /// Asks first: the event disappears from macOS Calendar and synced devices too.
    func remove(_ e: EKEvent) {
        let info = e.hasRecurrenceRules ? "Acara berulang: hanya kejadian ini yang dihapus. Ikut terhapus di Kalender macOS dan perangkat yang tersinkron." : "Ikut terhapus di Kalender macOS dan perangkat yang tersinkron."
        if confirm(String(format: tr("Hapus %@?"), e.title ?? tr("Rapat")), info, "Hapus") { a.delete(e); if editing == e { adding = false } }
    }

    func startEditing(_ e: EKEvent) {
        editing = e
        title = e.title ?? ""
        when = e.startDate
        minutes = max(15, Int(e.endDate.timeIntervalSince(e.startDate) / 60))
        reminder = a.reminder(e)
        error = ""
        adding = true
    }

    func save() {
        let start = when
        let msg = editing.map { a.update($0, title: title, start: start, minutes: minutes, reminder: reminder) }
            ?? a.add(title: title, start: start, minutes: minutes, reminder: reminder)
        if let msg { error = msg; return }
        if editing == nil { a.selected = Calendar.current.startOfDay(for: start); a.month = start; a.reload() }
        defaultReminder = reminder ?? -1 // next event starts with the same choice
        adding = false
        Notch.shared.flash("Rapat tersimpan · \(start.formatted(date: .abbreviated, time: .shortened))")
    }
}
