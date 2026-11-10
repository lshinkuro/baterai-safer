import SwiftUI

// Lainnya → Todo and its Home card: a plain task list, stored on this Mac.

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
}

final class TodoModel: ObservableObject {
    static let shared = TodoModel()
    static let file = Paths.user + "/todo.json"

    @Published var items = load(TodoModel.file, [Todo]()) {
        didSet {
            try? FileManager.default.createDirectory(atPath: Paths.user, withIntermediateDirectories: true)
            save(items, Self.file)
        }
    }

    var open: [Todo] { items.filter { !$0.done } }
    var finished: [Todo] { items.filter(\.done) }

    func add(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { items.append(Todo(text: t)) }
    }

    func toggle(_ t: Todo) { if let i = items.firstIndex(where: { $0.id == t.id }) { items[i].done.toggle() } }
    func rename(_ id: UUID, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, let i = items.firstIndex(where: { $0.id == id }) { items[i].text = t }
    }
    func delete(_ t: Todo) { items.removeAll { $0.id == t.id } }
    func clearFinished() { items = open }
}

struct TodoPage: View {
    @ObservedObject var m = TodoModel.shared
    @Local private var input = ""
    @Local private var editing: UUID?

    var body: some View {
        HStack(spacing: 10) {
            NCard(padding: 12) {
                VStack(spacing: 8) {
                    if m.items.isEmpty {
                        Placeholder(icon: "checkmark.circle", title: "Belum ada tugas", subtitle: "Tulis satu yang mau dikerjakan hari ini")
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 4) { ForEach(m.open + m.finished) { row($0) } }
                        }
                    }
                    HStack(spacing: 6) {
                        TextField(tr("Tugas baru…"), text: $input).textFieldStyle(.plain).font(.system(size: 12)).onSubmit(submit)
                        NButton(icon: editing == nil ? "plus" : "checkmark") { submit() }
                            .tip(editing == nil ? "Tambah tugas" : "Simpan").disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.leading, 12).padding(.trailing, 3).padding(.vertical, 3)
                    .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
            NCard(padding: 12, glow: true) {
                VStack(spacing: 8) {
                    Ring(value: m.items.isEmpty ? 0 : Double(m.finished.count) / Double(m.items.count), color: Palette.accent, label: "\(m.finished.count)/\(m.items.count)", size: 76, line: 8)
                    Text(m.open.isEmpty && !m.items.isEmpty ? tr("Semua beres") : String(format: tr("%@ tersisa"), "\(m.open.count)")).font(.system(size: 13, weight: .semibold))
                    if !m.finished.isEmpty {
                        NButton(icon: "trash", title: "Hapus yang selesai") {
                            if confirm("Hapus yang selesai?", String(format: tr("%@ tugas selesai akan dihapus."), "\(m.finished.count)"), "Hapus") { m.clearFinished() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 190)
        }
    }

    func row(_ t: Todo) -> some View {
        HStack(spacing: 8) {
            Button { withAnimation(Motion.ease) { m.toggle(t) } } label: {
                Image(systemName: t.done ? "checkmark.circle.fill" : "circle").font(.system(size: 14)).foregroundStyle(t.done ? Palette.accent : .gray)
            }
            .buttonStyle(.plain).tip(t.done ? "Belum" : "Selesai")
            Text(t.text).font(.system(size: 12)).lineLimit(1).strikethrough(t.done, color: .gray).foregroundStyle(t.done ? .gray : .white)
            Spacer(minLength: 4)
            Menu {
                Button(tr("Ubah")) { edit(t) }
                Button(role: .destructive) { remove(t) } label: { Label(tr("Hapus"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().tip("Lainnya")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(editing == t.id ? Palette.accent.opacity(0.14) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu {
            Button(tr("Ubah")) { edit(t) }
            Button(tr("Hapus")) { remove(t) }
        }
    }

    func edit(_ t: Todo) { editing = t.id; input = t.text }

    func remove(_ t: Todo) {
        guard confirm(String(format: tr("Hapus %@?"), t.text), "Tugas ini akan dihapus.", "Hapus") else { return }
        m.delete(t)
        if editing == t.id { editing = nil; input = "" }
    }

    func submit() {
        if let editing { m.rename(editing, input) } else { m.add(input) }
        editing = nil
        input = ""
    }
}
