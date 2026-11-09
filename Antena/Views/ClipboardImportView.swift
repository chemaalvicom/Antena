import SwiftUI

/// Añade varias listas de golpe: pega un texto con varios enlaces (M3U o Xtream get.php)
/// y se descargan una a una.
struct ClipboardImportView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent

    private enum ItemState: Equatable {
        case pending, loading, done(Int), duplicate, failed(String)
    }

    private struct Item: Identifiable {
        let id = UUID()
        let url: String
        var name: String
        var selected = true
        var state: ItemState = .pending
    }

    @State private var text = ""
    @State private var items: [Item] = []
    @State private var running = false
    @State private var finished = false

    private var selectedCount: Int { items.filter { $0.selected && $0.state == .pending }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PasteButton(payloadType: String.self) { strings in
                        text = strings.joined(separator: "\n")
                        detect()
                    }
                    TextField("O pega aquí los enlaces, uno por línea", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: text) { detect() }
                } header: {
                    Text("Enlaces")
                } footer: {
                    Text("Vale cualquier texto que contenga enlaces de listas M3U o de Xtream (get.php?username=…). Se detectan solos.")
                }

                if !items.isEmpty {
                    Section("\(items.count) listas detectadas") {
                        ForEach($items) { $item in
                            row($item)
                        }
                    }
                }
            }
            .navigationTitle("Varias desde el portapapeles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Cerrar" : "Cancelar") { dismiss() }.disabled(running)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if running {
                        ProgressView()
                    } else if !finished {
                        Button("Añadir \(selectedCount)") { Task { await addAll() } }
                            .disabled(selectedCount == 0)
                    }
                }
            }
            .interactiveDismissDisabled(running)
        }
    }

    @ViewBuilder private func row(_ item: Binding<Item>) -> some View {
        let it = item.wrappedValue
        HStack(spacing: 12) {
            statusIcon(it)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Nombre", text: item.name)
                    .font(.subheadline.weight(.semibold))
                    .disabled(running || it.state != .pending)
                Text(URL(string: it.url)?.host ?? it.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if case .failed(let msg) = it.state {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !running, it.state == .pending else { return }
            item.wrappedValue.selected.toggle()
        }
    }

    @ViewBuilder private func statusIcon(_ it: Item) -> some View {
        switch it.state {
        case .pending:
            Image(systemName: it.selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(it.selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .font(.title3)
        case .loading:
            ProgressView()
        case .done(let n):
            VStack(spacing: 0) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
                Text("\(n)").font(.caption2).foregroundStyle(.secondary)
            }
        case .duplicate:
            Image(systemName: "equal.circle").foregroundStyle(.secondary).font(.title3)
        case .failed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).font(.title3)
        }
    }

    private func detect() {
        let links = Library.playlistLinks(in: text)
        var next: [Item] = []
        for url in links {
            if let existing = items.first(where: { $0.url == url }) {
                next.append(existing)
            } else {
                var item = Item(url: url, name: Library.suggestedName(for: url))
                if library.hasSource(url) {
                    item.state = .duplicate
                    item.selected = false
                }
                next.append(item)
            }
        }
        items = next
    }

    /// Descarga una a una para no saturar al proveedor; un fallo no para las demás.
    private func addAll() async {
        running = true
        for i in items.indices where items[i].selected && items[i].state == .pending {
            items[i].state = .loading
            do {
                try await library.addRemote(name: items[i].name, urlString: items[i].url, userAgent: userAgent)
                let count = library.playlists.last?.channels.count ?? 0
                items[i].state = .done(count)
            } catch {
                items[i].state = .failed(error.localizedDescription)
            }
        }
        running = false
        finished = true
    }
}
