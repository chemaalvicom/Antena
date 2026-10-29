import SwiftUI
import AVKit
import MobileVLCKit

// MARK: - Pantalla de reproducción

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @Environment(\.verticalSizeClass) private var vSize
    @AppStorage("engine") private var engine = Engine.auto.rawValue
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent

    let channel: Channel
    /// Cambio manual de motor durante la reproducción (true = VLC).
    @State private var engineOverride: Bool?
    @State private var showBar = true

    private var useVLC: Bool {
        if let engineOverride { return engineOverride }
        switch Engine(rawValue: engine) ?? .auto {
        case .apple: return false
        case .vlc: return true
        case .auto: return !channel.isHLS
        }
    }

    var body: some View {
        let landscape = vSize == .compact
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if !landscape { topBar }
                Group {
                    if useVLC {
                        VLCPlayerView(channel: channel, userAgent: userAgent)
                    } else {
                        ApplePlayerView(channel: channel, userAgent: userAgent)
                    }
                }
                .id(useVLC)
            }
            .ignoresSafeArea(edges: landscape ? .all : [])

            if landscape && showBar {
                topBar
                    .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                    .transition(.opacity)
            }
        }
        .onTapGesture(count: 2) { if landscape { withAnimation { showBar.toggle() } } }
        .onAppear { library.markPlayed(channel) }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.15), in: Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name).font(.headline).lineLimit(1)
                Text("\(channel.group) · \(useVLC ? "VLC" : "Apple")")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            Button { library.toggleFavorite(channel) } label: {
                Image(systemName: library.isFavorite(channel) ? "star.fill" : "star")
                    .frame(width: 38, height: 38)
            }
            Menu {
                Button { engineOverride = !useVLC } label: {
                    Label(useVLC ? "Probar con reproductor Apple" : "Probar con VLC", systemImage: "arrow.triangle.2.circlepath")
                }
                Button { UIPasteboard.general.string = channel.url } label: {
                    Label("Copiar URL", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 38, height: 38)
            }
            RoutePicker().frame(width: 38, height: 38)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Motor Apple (AVPlayer): HLS, AirPlay, Picture in Picture

struct ApplePlayerView: UIViewControllerRepresentable {
    let channel: Channel
    let userAgent: String

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect

        if let url = channel.streamURL {
            let ua = channel.userAgent ?? userAgent
            var headers: [String: String] = ["User-Agent": ua]
            if let ref = channel.referrer { headers["Referer"] = ref }
            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": headers,
                AVURLAssetHTTPUserAgentKey: ua
            ]
            let asset = AVURLAsset(url: url, options: options)
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            player.allowsExternalPlayback = true
            vc.player = player
            player.play()
        }
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        vc.player?.pause()
        vc.player = nil
    }
}

// MARK: - Motor VLC: MPEG-TS, MKV, RTMP y casi cualquier flujo

final class VLCPlaybackModel: ObservableObject {
    let player = VLCMediaPlayer()
    @Published var isPlaying = false
    @Published var isBuffering = true
    @Published var failed = false
    private var timer: Timer?

    func start(channel: Channel, userAgent: String, caching: Int) {
        guard let url = channel.streamURL else { failed = true; return }
        let media = VLCMedia(url: url)
        media.addOption(":http-user-agent=\(channel.userAgent ?? userAgent)")
        if let ref = channel.referrer { media.addOption(":http-referrer=\(ref)") }
        media.addOption(":network-caching=\(caching)")
        player.media = media
        player.play()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let state = player.state
        let playing = player.isPlaying
        if isPlaying != playing { isPlaying = playing }
        let buffering = !playing && (state == .opening || state == .buffering)
        if isBuffering != buffering { isBuffering = buffering }
        let error = state == .error
        if failed != error { failed = error }
    }

    func togglePause() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
    }
}

private struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct VLCPlayerView: View {
    let channel: Channel
    let userAgent: String
    @AppStorage("vlcCaching") private var caching = 1500
    @StateObject private var model = VLCPlaybackModel()
    @State private var showControls = true

    var body: some View {
        ZStack {
            VLCVideoSurface(player: model.player)

            if model.failed {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("No se pudo reproducir este canal").font(.headline)
                    Text("Prueba otro motor desde el menú ⋯ o revisa el User-Agent en Ajustes.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(32)
            } else if model.isBuffering {
                ProgressView().controlSize(.large).tint(.white)
            } else if showControls {
                Button { model.togglePause() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 76, height: 76)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
        .onAppear { model.start(channel: channel, userAgent: userAgent, caching: caching) }
        .onDisappear { model.stop() }
        .task(id: showControls) {
            // Oculta los controles a los 3 s
            guard showControls else { return }
            try? await Task.sleep(for: .seconds(3))
            if model.isPlaying { withAnimation { showControls = false } }
        }
    }
}

// MARK: - Botón AirPlay

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.prioritizesVideoDevices = true
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
