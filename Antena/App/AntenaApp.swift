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
