import SwiftUI

// MARK: - Directo: grupos + canales + vista previa

struct LiveTV: View {
    @Environment(Library.self) private var library
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        let playlist = tv.playlist(in: library)
        if library.playlists.isEmpty {
            EmptyLibraryView()
        } else {
            let channels = tv.channels(tv.group, playlist: playlist, library: library, parental: parental)
            let selected = channels.first(where: { $0.id == tv.selectedChannelID }) ?? channels.first
            if vSize == .compact {
                HStack(spacing: 0) {
                    GroupsColumn(playlist: playlist)
                        .frame(width: 168)
                    ChannelColumn(channels: channels, selected: selected, playlist: playlist, showHeader: true)
                        .frame(maxWidth: .infinity)
                    PreviewPanel(channel: selected, playlist: playlist, compact: false)
                        .frame(width: 250)
                }
            } else {
                VStack(spacing: 0) {
                    PreviewPanel(channel: selected, playlist: playlist, compact: true)
                    GroupChips(playlist: playlist)
                    ChannelColumn(channels: channels, selected: selected, playlist: playlist, showHeader: false)
                }
            }
        }
    }
}

// MARK: - Grupos

struct GroupEntry: Identifiable {
    let filter: GroupFilter
    let count: Int?
    let locked: Bool
    var id: GroupFilter { filter }
}

@MainActor
func groupEntries(playlist: Playlist?, library: Library, parental: ParentalControl) -> [GroupEntry] {
    var out: [GroupEntry] = [
        GroupEntry(filter: .all, count: playlist?.channels.filter { !parental.isHidden($0) }.count, locked: false),
        GroupEntry(filter: .favorites, count: library.favorites.filter { !parental.isHidden($0) }.count, locked: false),
        GroupEntry(filter: .recents, count: nil, locked: false)
    ]
    guard let playlist else { return out }
    var counts: [String: Int] = [:]
    for c in playlist.channels { counts[c.group, default: 0] += 1 }
    for g in playlist.groups where !parental.isGroupHidden(g) {
        let locked = parental.isGroupProtected(g) && !parental.unlocked
        out.append(GroupEntry(filter: .group(g), count: locked ? nil : counts[g], locked: locked))
    }
    return out
}

private struct GroupsColumn: View {
    @Environment(Library.self) private var library
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    let playlist: Playlist?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaylistMenu(playlist: playlist)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groupEntries(playlist: playlist, library: library, parental: parental)) { e in
                        let selected = tv.group == e.filter
                        Button { tv.choose(e.filter, parental: parental) } label: {
                            HStack(spacing: 6) {
                                Text(e.filter.title)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if e.locked {
                                    Image(systemName: "lock.fill").font(.system(size: 10))
                                        .accessibilityLabel("Protegido")
                                }
                                if let n = e.count {
                                    Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(TVColor.text3)
                                }
                            }
                            .font(.system(size: 13, weight: selected ? .bold : .medium))
                            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(white: 0.8)))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(selected ? TVColor.chip : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(TVColor.panel)
    }
}

private struct GroupChips: View {
    @Environment(Library.self) private var library
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    let playlist: Playlist?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PlaylistMenu(playlist: playlist, compact: true)
                ForEach(groupEntries(playlist: playlist, library: library, parental: parental)) { e in
                    let selected = tv.group == e.filter
                    Button { tv.choose(e.filter, parental: parental) } label: {
                        HStack(spacing: 5) {
                            if e.locked { Image(systemName: "lock.fill").font(.system(size: 10)) }
                            Text(e.filter.title).lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(selected ? TVColor.rail : TVColor.text)
                        .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(TVColor.panel), in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Color.clear : TVColor.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

/// Cambiar de lista y gestionar listas.
struct PlaylistMenu: View {
    @Environment(Library.self) private var library
    @Environment(TVState.self) private var tv
    let playlist: Playlist?
    var compact = false
    @State private var showManager = false

    var body: some View {
        Menu {
            ForEach(library.playlists) { p in
                Button {
                    tv.playlistID = p.id
                    tv.group = .all
                } label: {
                    if p.id == playlist?.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
            Divider()
            Button { showManager = true } label: { Label("Gestionar listas", systemImage: "list.bullet.rectangle") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle").font(.system(size: 11, weight: .bold))
                Text(playlist?.name ?? "Listas").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(compact ? TVColor.text : TVColor.text2)
            .padding(.horizontal, compact ? 12 : 0)
            .frame(height: compact ? 34 : 28)
            .background(compact ? TVColor.chip : .clear, in: Capsule())
        }
        .sheet(isPresented: $showManager) { PlaylistsManagerView() }
    }
}

// MARK: - Lista de canales

private struct ChannelColumn: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    @Environment(VPNManager.self) private var vpn
    let channels: [Channel]
    let selected: Channel?
    let playlist: Playlist?
    let showHeader: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                HStack(spacing: 10) {
                    Text(epg.now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tint)
                    Text("\(tv.group.title) · \(channels.count) canales")
                        .font(.system(size: 12))
                        .foregroundStyle(TVColor.text2)
                        .lineLimit(1)
                    Spacer()
                    Label("VPN", systemImage: vpn.isConnected ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(vpn.isConnected ? TVColor.ok : .orange)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .overlay(alignment: .bottom) { TVColor.line.frame(height: 1) }
            }
            if channels.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: emptyIcon, description: Text(emptyText))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(channels) { ch in
                                ChannelLine(channel: ch,
                                            number: tv.number(of: ch, in: playlist),
                                            selected: ch.id == selected?.id,
                                            playlist: playlist)
                                .id(ch.id)
                            }
                        }
                    }
                    .onChange(of: tv.group) { _, _ in
                        if let first = channels.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        switch tv.group {
        case .favorites: return "Sin favoritos"
        case .recents: return "Nada reciente"
        default: return "Sin canales"
        }
    }
    private var emptyIcon: String {
        switch tv.group {
        case .favorites: return "star"
        case .recents: return "clock"
        default: return "tv"
        }
    }
    private var emptyText: String {
        switch tv.group {
        case .favorites: return "Pulsa la estrella de un canal o mantenlo pulsado para añadirlo."
        case .recents: return "Los canales que veas aparecerán aquí."
        default: return "Este grupo está vacío."
        }
    }
}

private struct ChannelLine: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    let channel: Channel
    let number: Int?
    let selected: Bool
    let playlist: Playlist?

    var body: some View {
        let locked = parental.needsPIN(channel)
        let program = locked ? nil : epg.current(for: channel, playlist: playlist?.id)
        Button {
            if selected || locked { tv.play(channel, parental: parental) } else { tv.selectedChannelID = channel.id }
        } label: {
            HStack(spacing: 10) {
                Text(number.map(String.init) ?? "")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(TVColor.text3))
                    .frame(width: 30, alignment: .trailing)
                TVLogo(channel: channel, locked: locked)
                    .frame(width: 52, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(channel.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if library.isFavorite(channel) {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                                .accessibilityLabel("Favorito")
                        }
                        if locked {
                            Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(TVColor.text2)
                                .accessibilityLabel("Protegido")
                        }
                    }
                    if let program {
                        Text("\(program.start.formatted(date: .omitted, time: .shortened)) · \(program.title)")
                            .font(.system(size: 11))
                            .foregroundStyle(TVColor.text2)
                            .lineLimit(1)
                        TVProgress(value: program.progress(at: epg.now), highlighted: selected)
                    } else {
                        Text(locked ? "Protegido · pide PIN" : channel.group)
                            .font(.system(size: 11))
                            .foregroundStyle(TVColor.text3)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(selected ? TVColor.selected : .clear)
            .overlay(alignment: .bottom) { TVColor.panel.frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { ChannelActions(channel: channel) }
        .accessibilityHint(selected ? "Toca para ver" : "Toca para ver la vista previa")
    }
}

/// Menú de acciones de un canal (mantener pulsado).
struct ChannelActions: View {
    @Environment(Library.self) private var library
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    let channel: Channel

    var body: some View {
        let fav = library.isFavorite(channel)
        Button { tv.play(channel, parental: parental) } label: { Label("Ver", systemImage: "play.fill") }
        Button { library.toggleFavorite(channel) } label: {
            Label(fav ? "Quitar de favoritos" : "Añadir a favoritos", systemImage: fav ? "star.slash" : "star")
        }
        if !library.favoriteLists.isEmpty {
            Menu {
                ForEach(library.favoriteLists) { l in
                    Button { library.toggle(channel, inList: l.id) } label: {
                        if library.isInList(channel, l.id) { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                    }
                }
            } label: { Label("Listas de favoritos", systemImage: "star.square.on.square") }
        }
        if parental.enabled && parental.hasPIN {
            let isProt = parental.protectedChannels.contains(channel.url)
            Button {
                let change = { parental.setChannel(channel, protected: !isProt) }
                if parental.unlocked { change() } else {
                    tv.pinRequest = PINRequest(reason: "Cambiar la protección de «\(channel.name)».", action: change)
                }
            } label: {
                Label(isProt ? "Quitar protección" : "Proteger con PIN", systemImage: isProt ? "lock.open" : "lock")
            }
        }
        Button { UIPasteboard.general.string = channel.url } label: { Label("Copiar URL del canal", systemImage: "doc.on.doc") }
    }
}

// MARK: - Vista previa

private struct PreviewPanel: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    @Environment(VPNManager.self) private var vpn
    @AppStorage("livePreview") private var livePreview = true
    let channel: Channel?
    let playlist: Playlist?
    let compact: Bool
    @State private var previewID: String?

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 0) {
                screen.aspectRatio(16 / 9, contentMode: .fit)
                info.padding(.horizontal, 16).padding(.top, 10)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                screen.aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                info
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(TVColor.panel)
        }
    }

    private var canPreview: Bool {
        guard let channel else { return false }
        return livePreview && vpn.isConnected && tv.playing == nil && !parental.needsPIN(channel)
    }

    @ViewBuilder private var screen: some View {
        ZStack {
            Color.black
            if let channel {
                if canPreview && previewID == channel.id {
                    LivePreviewView(channel: channel).id(channel.id)
                } else {
                    TVLogo(channel: channel, locked: parental.needsPIN(channel), corner: 0)
                        .padding(compact ? 40 : 24)
                        .background(Color.black)
                }
                VStack {
                    HStack {
                        LiveBadge()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let channel { tv.play(channel, parental: parental) } }
        .task(id: channel?.id) {
            // Espera un momento antes de abrir el vídeo para no gastar conexión al pasar canales.
            previewID = nil
            guard let id = channel?.id else { return }
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { previewID = id }
        }
        .accessibilityLabel("Vista previa. Toca para ver a pantalla completa.")
    }

    @ViewBuilder private var info: some View {
        if let channel {
            let locked = parental.needsPIN(channel)
            let current = locked ? nil : epg.current(for: channel, playlist: playlist?.id)
            let next = locked ? nil : epg.next(for: channel, playlist: playlist?.id)
            let fav = library.isFavorite(channel)
            VStack(alignment: .leading, spacing: 6) {
                Text([tv.number(of: channel, in: playlist).map(String.init), channel.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                if let current {
                    Text(current.title).font(.system(size: compact ? 17 : 15, weight: .bold)).lineLimit(2)
                    Text("\(current.timeRange) · quedan \(current.minutesLeft(at: epg.now)) min")
                        .font(.system(size: 11))
                        .foregroundStyle(TVColor.text2)
                    TVProgress(value: current.progress(at: epg.now), highlighted: true)
                } else {
                    Text(locked ? "Canal protegido" : "Sin información de la guía")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TVColor.text2)
                }
                if let next {
                    (Text("A continuación: ").foregroundStyle(TVColor.text2) + Text(next.title).fontWeight(.semibold))
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Button { tv.play(channel, parental: parental) } label: {
                        Label("Ver", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(TVColor.rail)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button { library.toggleFavorite(channel) } label: {
                        Image(systemName: fav ? "star.fill" : "star")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(fav ? .yellow : TVColor.text2)
                            .frame(width: 44, height: 38)
                            .background(TVColor.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(fav ? "Quitar de favoritos" : "Añadir a favoritos")
                }
                .padding(.top, 4)
            }
        } else {
            Text("Elige un canal").font(.subheadline).foregroundStyle(TVColor.text2)
        }
    }
}

// MARK: - Sin listas

struct EmptyLibraryView: View {
    @State private var showAdd = false
    @State private var showClipboard = false

    var body: some View {
        ContentUnavailableView {
            Label("Sin listas", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Añade tu lista M3U o tu cuenta Xtream. La guía de programación se carga sola si el proveedor la ofrece.")
        } actions: {
            Button("Añadir lista") { showAdd = true }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(TVColor.rail)
            Button("Pegar varias desde el portapapeles") { showClipboard = true }
        }
        .sheet(isPresented: $showAdd) { AddPlaylistView() }
        .sheet(isPresented: $showClipboard) { ClipboardImportView() }
    }
}
