import SwiftUI

// MARK: - Fila de canal

struct ChannelRow: View {
    @Environment(Library.self) private var library
    let channel: Channel
    let onPlay: () -> Void

    var body: some View {
        let fav = library.isFavorite(channel)
        Button(action: onPlay) {
            HStack(spacing: 12) {
                ChannelLogo(urlString: channel.logo)
                    .frame(width: 56, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(channel.group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if fav {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button { library.toggleFavorite(channel) } label: {
                Label(fav ? "Quitar" : "Favorito", systemImage: fav ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .contextMenu {
            Button { onPlay() } label: { Label("Reproducir", systemImage: "play") }
            Button { library.toggleFavorite(channel) } label: {
                Label(fav ? "Quitar de favoritos" : "Añadir a favoritos", systemImage: fav ? "star.slash" : "star")
            }
            Button { UIPasteboard.general.string = channel.url } label: {
                Label("Copiar URL del canal", systemImage: "doc.on.doc")
            }
        }
    }
}

struct ChannelLogo: View {
    let urlString: String?

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "tv").foregroundStyle(.secondary))
            }
        }
    }
}

// MARK: - Favoritos

struct FavoritesView: View {
    @Environment(Library.self) private var library
    @Binding var playing: Channel?

    var body: some View {
        NavigationStack {
            Group {
                if library.favorites.isEmpty {
                    ContentUnavailableView(
                        "Sin favoritos",
                        systemImage: "star",
                        description: Text("Desliza un canal hacia la izquierda para marcarlo como favorito.")
                    )
                } else {
                    List {
                        ForEach(library.favorites) { ch in
                            ChannelRow(channel: ch) { playing = ch }
                        }
                        .onDelete { library.deleteFavorites(at: $0) }
                        .onMove { library.moveFavorites(from: $0, to: $1) }
                    }
                    .listStyle(.plain)
                    .toolbar { EditButton() }
                }
            }
            .navigationTitle("Favoritos")
        }
    }
}

// MARK: - Recientes

struct RecentsView: View {
    @Environment(Library.self) private var library
    @Binding var playing: Channel?

    var body: some View {
        NavigationStack {
            Group {
                if library.recents.isEmpty {
                    ContentUnavailableView(
                        "Nada reciente",
                        systemImage: "clock",
                        description: Text("Los canales que veas aparecerán aquí.")
                    )
                } else {
                    List(library.recents) { ch in
                        ChannelRow(channel: ch) { playing = ch }
                    }
                    .listStyle(.plain)
                    .toolbar {
                        Button("Borrar", role: .destructive) { library.clearRecents() }
                    }
                }
            }
            .navigationTitle("Recientes")
        }
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @AppStorage("engine") private var engine = Engine.auto.rawValue
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent
    @AppStorage("vlcCaching") private var caching = 1500
    @AppStorage("accent") private var accent = Accent.naranja.rawValue
    @AppStorage("theme") private var theme = Theme.oscuro.rawValue

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Motor", selection: $engine) {
                        ForEach(Engine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Stepper(value: $caching, in: 300...10000, step: 300) {
                        HStack {
                            Text("Búfer VLC")
                            Spacer()
                            Text("\(caching) ms").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } header: {
                    Text("Reproducción")
                } footer: {
                    Text("Automático usa el reproductor de Apple para HLS (.m3u8), con AirPlay y Picture in Picture, y VLC para todo lo demás. Sube el búfer si un canal se corta.")
                }

                Section {
                    TextField("User-Agent", text: $userAgent, axis: .vertical)
                        .font(.footnote.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Menu("Usar uno predefinido") {
                        ForEach(Defaults.userAgentPresets.indices, id: \.self) { i in
                            Button(Defaults.userAgentPresets[i].0) { userAgent = Defaults.userAgentPresets[i].1 }
                        }
                    }
                } header: {
                    Text("Red")
                } footer: {
                    Text("Algunos proveedores solo aceptan ciertos User-Agent. Si un canal define el suyo en la lista, se usa ese.")
                }

                Section("Apariencia") {
                    Picker("Tema", selection: $theme) {
                        ForEach(Theme.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
                    }
                    HStack(spacing: 14) {
                        ForEach(Accent.allCases) { a in
                            Circle()
                                .fill(a.color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if a.rawValue == accent {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { accent = a.rawValue }
                                .accessibilityLabel(a.rawValue.capitalized)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Acerca de") {
                    LabeledContent("Versión", value: version)
                    LabeledContent("Publicidad", value: "Ninguna")
                    LabeledContent("Rastreo", value: "Ninguno")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
