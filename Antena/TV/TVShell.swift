import SwiftUI
import Observation
import UserNotifications

// MARK: - Colores (estilo guía de TV, siempre oscuro)

enum TVColor {
    static let bg = Color(red: 0.055, green: 0.067, blue: 0.086)
    static let rail = Color(red: 0.039, green: 0.047, blue: 0.063)
    static let panel = Color(red: 0.071, green: 0.086, blue: 0.110)
    static let selected = Color(red: 0.118, green: 0.145, blue: 0.188)
    static let chip = Color(red: 0.149, green: 0.176, blue: 0.212)
    static let line = Color(red: 0.118, green: 0.141, blue: 0.173)
    static let text = Color(red: 0.910, green: 0.918, blue: 0.929)
    static let text2 = Color(red: 0.604, green: 0.639, blue: 0.682)
    static let text3 = Color(red: 0.494, green: 0.529, blue: 0.573)
    static let live = Color(red: 0.851, green: 0.176, blue: 0.125)
    static let ok = Color(red: 0.290, green: 0.871, blue: 0.502)
}

// MARK: - Estado de la interfaz

enum GroupFilter: Hashable {
    case all, favorites, recents
    case group(String)

    var title: String {
        switch self {
        case .all: return "Todos"
        case .favorites: return "Favoritos"
        case .recents: return "Recientes"
        case .group(let g): return g
        }
    }
}

struct PINRequest: Identifiable {
    let id = UUID()
    let reason: String
    let action: () -> Void
}

struct GuideSelection: Equatable {
    var channel: Channel
    var program: EPGProgram?
}

@MainActor
@Observable
final class TVState {
    enum Section: String, CaseIterable, Identifiable {
        case search, live, guide, favorites, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .search: return "Buscar"
            case .live: return "Directo"
            case .guide: return "Guía"
            case .favorites: return "Favoritos"
            case .settings: return "Ajustes"
            }
        }
        var icon: String {
            switch self {
            case .search: return "magnifyingglass"
            case .live: return "tv"
            case .guide: return "tablecells"
            case .favorites: return "star"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    var section: Section = .live
    var playlistID: UUID?
    var group: GroupFilter = .all
    var selectedChannelID: String?
    var playing: Channel?
    var pinRequest: PINRequest?
    var guideStart: Date = TVState.halfHour(Date())
    var guideSelection: GuideSelection?

    @ObservationIgnored private var numberCache: [UUID: (Date, [String: Int])] = [:]

    nonisolated static func halfHour(_ d: Date) -> Date {
        let t = d.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 1800).rounded(.down) * 1800)
    }

    func playlist(in library: Library) -> Playlist? {
        library.playlists.first { $0.id == playlistID } ?? library.playlists.first
    }

    /// Número de canal = posición en la lista (como en una tele).
    func number(of ch: Channel, in p: Playlist?) -> Int? {
        guard let p else { return nil }
        if let cached = numberCache[p.id], cached.0 == p.updatedAt { return cached.1[ch.id] }
        var map: [String: Int] = [:]
        for (i, c) in p.channels.enumerated() { map[c.id] = i + 1 }
        numberCache[p.id] = (p.updatedAt, map)
        return map[ch.id]
    }

    /// Canales del grupo elegido, sin los ocultos por el control parental.
    func channels(_ filter: GroupFilter, playlist p: Playlist?, library: Library, parental: ParentalControl) -> [Channel] {
        let base: [Channel]
        switch filter {
        case .all: base = p?.channels ?? []
        case .favorites: base = library.favorites
        case .recents: base = library.recents
        case .group(let g): base = (p?.channels ?? []).filter { $0.group == g }
        }
        return base.filter { !parental.isHidden($0) }
    }

    /// Reproduce, pidiendo antes el PIN si el canal está protegido.
    func play(_ ch: Channel, parental: ParentalControl) {
        if parental.needsPIN(ch) {
            pinRequest = PINRequest(reason: "«\(ch.name)» está protegido.") { [weak self] in self?.playing = ch }
        } else {
            parental.touch()
            playing = ch
        }
    }

    func choose(_ filter: GroupFilter, parental: ParentalControl) {
        if case .group(let g) = filter, parental.isGroupProtected(g), !parental.unlocked {
            pinRequest = PINRequest(reason: "El grupo «\(g)» está protegido.") { [weak self] in self?.group = filter }
        } else {
            group = filter
        }
    }
}

// MARK: - Contenedor principal

struct TVShell: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("accent") private var accent = Accent.naranja.rawValue
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent
    @State private var tv = TVState()

    var body: some View {
        let landscape = vSize == .compact
        Group {
            if landscape {
                HStack(spacing: 0) {
                    SideRail()
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                    BottomBar()
                }
            }
        }
        .foregroundStyle(TVColor.text)
        .background(TVColor.bg.ignoresSafeArea())
        .environment(tv)
        .tint((Accent(rawValue: accent) ?? .naranja).color)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $tv.playing) { ch in
            PlayerScreen(channel: ch)
                .tint((Accent(rawValue: accent) ?? .naranja).color)
        }
        .sheet(item: $tv.pinRequest) { req in
            PINEntryView(mode: .unlock, reason: req.reason, onSuccess: req.action)
        }
        .task {
            library.load()
            if tv.playlistID == nil { tv.playlistID = library.playlists.first?.id }
            await epg.loadCached(library.playlists)
            await epg.refreshIfNeeded(library.playlists, userAgent: userAgent)
        }
        .task {
            while !Task.isCancelled {
                epg.now = Date()
                parental.checkIdle()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onChange(of: library.playlists.map(\.id)) { _, ids in
            if tv.playlistID == nil || !ids.contains(tv.playlistID!) { tv.playlistID = ids.first }
            Task { await epg.refreshIfNeeded(library.playlists, userAgent: userAgent) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { parental.appBackgrounded() }
            if phase == .active { Task { await epg.refreshIfNeeded(library.playlists, userAgent: userAgent) } }
        }
    }

    @ViewBuilder private var content: some View {
        switch tv.section {
        case .search: SearchTV()
        case .live: LiveTV()
        case .guide: GuideTV()
        case .favorites: FavoritesTV()
        case .settings: SettingsGate()
        }
    }
}

// MARK: - Menú lateral (horizontal) y barra inferior (vertical)

struct SideRail: View {
    @Environment(TVState.self) private var tv
    @Environment(VPNManager.self) private var vpn

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TVColor.rail)
                .frame(width: 36, height: 36)
                .background(.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            ForEach([TVState.Section.search, .live, .guide, .favorites]) { s in
                RailButton(section: s)
            }
            Spacer(minLength: 4)
            Image(systemName: vpn.isConnected ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 15))
                .foregroundStyle(vpn.isConnected ? TVColor.ok : .orange)
                .accessibilityLabel(vpn.isConnected ? "VPN activa" : "VPN caída")
            RailButton(section: .settings)
        }
        .padding(.vertical, 10)
        .frame(width: 64)
        .background(TVColor.rail.ignoresSafeArea())
    }
}

private struct RailButton: View {
    @Environment(TVState.self) private var tv
    let section: TVState.Section

    var body: some View {
        let selected = tv.section == section
        Button { tv.section = section } label: {
            VStack(spacing: 3) {
                Image(systemName: selected && section == .favorites ? "star.fill" : section.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(section.title)
                    .font(.system(size: 10, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 54, height: 48)
            .foregroundStyle(selected ? TVColor.rail : TVColor.text2)
            .background(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BottomBar: View {
    @Environment(TVState.self) private var tv

    var body: some View {
        HStack(spacing: 0) {
            ForEach([TVState.Section.live, .guide, .favorites, .search, .settings]) { s in
                let selected = tv.section == s
                Button { tv.section = s } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selected && s == .favorites ? "star.fill" : s.icon)
                            .font(.system(size: 19, weight: .semibold))
                        Text(s.title).font(.system(size: 10, weight: selected ? .bold : .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(TVColor.text2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.top, 6)
        .background(TVColor.rail.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { TVColor.line.frame(height: 1) }
    }
}

// MARK: - Piezas comunes

/// Logo del canal sobre fondo neutro (o un candado si está protegido).
struct TVLogo: View {
    let channel: Channel
    var locked = false
    var corner: CGFloat = 6

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(TVColor.chip)
            if locked {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(TVColor.text2)
            } else {
                ChannelLogo(urlString: channel.logo, name: channel.name)
                    .padding(channel.logo == nil ? 0 : 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct TVProgress: View {
    let value: Double
    var highlighted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TVColor.chip)
                Capsule()
                    .fill(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(TVColor.text3))
                    .frame(width: max(0, geo.size.width * value))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

struct LiveBadge: View {
    var body: some View {
        Text("EN DIRECTO")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(TVColor.live, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Vídeo silenciado para la vista previa (se para al abrir el reproductor).
struct LivePreviewView: View {
    let channel: Channel
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent
    @StateObject private var model = VLCPlaybackModel()

    var body: some View {
        ZStack {
            VLCVideoSurface(player: model.player)
            if model.failed {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(TVColor.text2)
            } else if model.isBuffering {
                ProgressView().tint(.white)
            }
        }
        .onAppear { model.start(channel: channel, userAgent: userAgent, caching: 1000, muted: true) }
        .onDisappear { model.stop() }
    }
}

/// Avisos de "Recordar" un programa.
enum Reminders {
    private static let key = "reminders"

    static func isSet(_ p: EPGProgram) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(p.id)
    }

    static func schedule(_ p: EPGProgram, channel: Channel) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let fire = p.start.addingTimeInterval(-60).timeIntervalSinceNow
        guard fire > 1 else { return false }
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = "Empieza en \(channel.name) a las \(p.start.formatted(date: .omitted, time: .shortened))."
        content.sound = .default
        let req = UNNotificationRequest(identifier: p.id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire, repeats: false))
        do { try await center.add(req) } catch { return false }
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.append(p.id)
        UserDefaults.standard.set(Array(list.suffix(200)), forKey: key)
        return true
    }

    static func cancel(_ p: EPGProgram) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [p.id])
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == p.id }
        UserDefaults.standard.set(list, forKey: key)
    }
}

/// Ajustes: piden PIN si el control parental protege los ajustes.
struct SettingsGate: View {
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv

    var body: some View {
        if parental.protectSettings && parental.isLocked {
            LockedPlaceholder(title: "Ajustes protegidos", message: "Introduce el PIN de control parental para cambiar los ajustes.") {
                tv.pinRequest = PINRequest(reason: "Los ajustes están protegidos.") {}
            }
        } else {
            SettingsView()
        }
    }
}

struct LockedPlaceholder: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 56, height: 56)
                .background(TVColor.chip, in: Circle())
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(TVColor.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(action: action) {
                Text("Introducir PIN").fontWeight(.bold).padding(.horizontal, 8).frame(minHeight: 40)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(TVColor.rail)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
