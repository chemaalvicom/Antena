import SwiftUI
import AVFoundation

@main
struct AntenaApp: App {
    @State private var library = Library()
    @State private var vpn = VPNManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Permite audio en segundo plano y Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        // Caché amplia para que los logos de los canales no se descarguen cada vez.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)
    }

    var body: some Scene {
        WindowGroup {
            GateView()
                .environment(library)
                .environment(vpn)
                .onAppear { library.load() }
                .task { if !Launch.isDemo { await vpn.start() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !Launch.isDemo { Task { await vpn.resume() } }
        }
    }
}

/// Siempre con VPN: hasta que el túnel conecta por primera vez solo se ve la pantalla de arranque.
/// Si después se cae, el reproductor se bloquea (ver PlayerScreen) y el aviso de Listas se pone en rojo.
struct GateView: View {
    @Environment(VPNManager.self) private var vpn
    @AppStorage("accent") private var accent = Accent.naranja.rawValue
    @AppStorage("theme") private var theme = Theme.oscuro.rawValue

    var body: some View {
        Group {
            if vpn.hasConnectedOnce || Launch.isDemo {
                RootView()
            } else {
                StartupView()
                    .tint((Accent(rawValue: accent) ?? .naranja).color)
                    .preferredColorScheme((Theme(rawValue: theme) ?? .oscuro).scheme)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vpn.hasConnectedOnce)
    }
}

struct RootView: View {
    @AppStorage("accent") private var accent = Accent.naranja.rawValue
    @AppStorage("theme") private var theme = Theme.oscuro.rawValue
    @Environment(Library.self) private var library
    @State private var playing: Channel?
    @State private var tab = Int(Launch.value("-tab") ?? "") ?? 0

    var body: some View {
        TabView(selection: $tab) {
            PlaylistsView(playing: $playing)
                .tabItem { Label("Listas", systemImage: "list.bullet.rectangle") }
                .tag(0)
            FavoritesView(playing: $playing)
                .tabItem { Label("Favoritos", systemImage: "star") }
                .tag(1)
            RecentsView(playing: $playing)
                .tabItem { Label("Recientes", systemImage: "clock") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(3)
        }
        .task {
            guard Launch.has("-play") else { return }
            library.load()
            try? await Task.sleep(for: .milliseconds(600))
            playing = library.playlists.first?.channels.first
        }
        .tint((Accent(rawValue: accent) ?? .naranja).color)
        .preferredColorScheme((Theme(rawValue: theme) ?? .oscuro).scheme)
        .fullScreenCover(item: $playing) { channel in
            PlayerScreen(channel: channel)
                .tint((Accent(rawValue: accent) ?? .naranja).color)
        }
    }
}
