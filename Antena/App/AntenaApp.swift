import SwiftUI
import AVFoundation

@main
struct AntenaApp: App {
    @State private var library = Library()
    @State private var vpn = VPNManager()
    @State private var epg = EPGStore()
    @State private var parental = ParentalControl()
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
                .environment(epg)
                .environment(parental)
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
                TVShell()
            } else {
                StartupView()
                    .tint((Accent(rawValue: accent) ?? .naranja).color)
                    .preferredColorScheme((Theme(rawValue: theme) ?? .oscuro).scheme)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vpn.hasConnectedOnce)
    }
}
