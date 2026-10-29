import SwiftUI
import AVFoundation

@main
struct AntenaApp: App {
    @State private var library = Library()

    init() {
        // Permite audio en segundo plano y Picture in Picture.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .onAppear { library.load() }
        }
    }
}

struct RootView: View {
    @AppStorage("accent") private var accent = Accent.naranja.rawValue
    @AppStorage("theme") private var theme = Theme.oscuro.rawValue
    @State private var playing: Channel?

    var body: some View {
        TabView {
            PlaylistsView(playing: $playing)
                .tabItem { Label("Listas", systemImage: "list.bullet.rectangle") }
            FavoritesView(playing: $playing)
                .tabItem { Label("Favoritos", systemImage: "star") }
            RecentsView(playing: $playing)
                .tabItem { Label("Recientes", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
        .tint((Accent(rawValue: accent) ?? .naranja).color)
        .preferredColorScheme((Theme(rawValue: theme) ?? .oscuro).scheme)
        .fullScreenCover(item: $playing) { channel in
            PlayerScreen(channel: channel)
                .tint((Accent(rawValue: accent) ?? .naranja).color)
        }
    }
}
