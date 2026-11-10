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
                ChannelLogo(urlString: channel.logo, name: channel.name)
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
    var name: String = ""

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "TV" : String(letters).uppercased()
    }

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .overlay(
                        Text(initials)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.tint)
                    )
            }
        }
    }
}

// MARK: - Ajustes

struct SettingsView: View {
    @Environment(VPNManager.self) private var vpn
    @Environment(Library.self) private var library
    @Environment(ParentalControl.self) private var parental
    @AppStorage("engine") private var engine = Engine.auto.rawValue
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent
    @AppStorage("vlcCaching") private var caching = 1500
    @AppStorage("accent") private var accent = Accent.naranja.rawValue
    @AppStorage("livePreview") private var livePreview = true
    @State private var showLists = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        VPNSettingsView()
                    } label: {
                        LabeledContent {
                            Text(vpn.status.label)
                        } label: {
                            Label("VPN", systemImage: vpn.isConnected ? "checkmark.shield.fill" : "exclamationmark.shield")
                        }
                    }
                } footer: {
                    Text("ANTENA PRO solo reproduce a través de tu servidor WireGuard.")
                }

                Section("Contenido") {
                    Button { showLists = true } label: {
                        LabeledContent {
                            Text("\(library.playlists.count)")
                        } label: {
                            Label("Listas", systemImage: "list.bullet.rectangle")
                        }
                    }
                    NavigationLink { EPGSettingsView() } label: {
                        Label("Guía de programación", systemImage: "tablecells")
                    }
                    NavigationLink { ParentalSettingsView() } label: {
                        LabeledContent {
                            Text(parental.enabled ? "Activado" : "Desactivado")
                        } label: {
                            Label("Control parental", systemImage: "lock.shield")
                        }
                    }
                }

                Section {
                    Picker("Motor", selection: $engine) {
                        ForEach(Engine.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Vista previa en vídeo", isOn: $livePreview)
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
                    Text("Automático usa el reproductor de Apple para HLS (.m3u8), con AirPlay y Picture in Picture, y VLC para todo lo demás. Sube el búfer si un canal se corta. La vista previa abre el canal sin sonido; si tu proveedor solo permite una conexión a la vez, desactívala.")
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

                Section("Color de acento") {
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
                    LabeledContent("VPN", value: "Servidor propio (WireGuard)")
                    LabeledContent("Rastreo", value: "Ninguno")
                }
            }
            .navigationTitle("Ajustes")
            .scrollContentBackground(.hidden)
            .background(TVColor.bg)
            .sheet(isPresented: $showLists) { PlaylistsManagerView() }
        }
    }
}
