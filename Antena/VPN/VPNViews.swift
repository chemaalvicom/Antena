import SwiftUI
import VisionKit
import UniformTypeIdentifiers

// MARK: - Arranque: no se entra sin VPN

struct StartupView: View {
    @Environment(VPNManager.self) private var vpn
    @State private var showImport = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 112, height: 112)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                HStack(spacing: 6) {
                    Text("ANTENA")
                    Text("PRO").foregroundStyle(.tint)
                }
                .font(.system(size: 30, weight: .heavy))
                Text("Tu IPTV, siempre conectada")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            card
            Label("ANTENA PRO solo reproduce con la VPN activa", systemImage: "lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showImport) { ImportVPNView() }
        .sheet(isPresented: $showSettings) { NavigationStack { VPNSettingsView() } }
    }

    @ViewBuilder private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch vpn.phase {
            case .loading:
                header("Preparando…", "Leyendo la configuración", icon: "shield")
                ProgressView().frame(maxWidth: .infinity)
            case .needsConfig:
                header("Configura tu VPN", "Escanea el QR de tu servidor para empezar", icon: "qrcode.viewfinder")
                Button { showImport = true } label: {
                    Text("Configurar VPN").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            case .failed(let message):
                header("No se pudo conectar", message, icon: "exclamationmark.shield", tint: .orange)
                HStack {
                    Button { Task { await vpn.retryNow() } } label: {
                        Text("Reintentar").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { showSettings = true } label: {
                        Text("Ajustes VPN").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            default:
                header(connectingTitle, "Servidor propio · WireGuard", icon: "shield")
                ProgressView(value: progress).tint(.accentColor)
                VStack(alignment: .leading, spacing: 8) {
                    step("Configuración cargada del Keychain", done: true)
                    step("Túnel iniciado", done: vpn.isConnected)
                    step("Comprobando IP de salida", done: vpn.exitIP != nil)
                }
                .font(.footnote)
                if case .disconnected = vpn.phase {
                    Button("Conectar") { Task { await vpn.retryNow() } }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var connectingTitle: String {
        if case .reconnecting(let n) = vpn.phase { return "Reintentando (\(n)/\(VPNManager.maxAttempts))…" }
        let host = vpn.summary?.endpointHost ?? "el servidor"
        return "Conectando con \(host)…"
    }

    private var progress: Double {
        if vpn.exitIP != nil { return 1 }
        if vpn.isConnected { return 0.8 }
        return 0.4
    }

    private func header(_ title: String, _ subtitle: String, icon: String, tint: Color = .accentColor) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func step(_ text: String, done: Bool) -> some View {
        Label {
            Text(text).foregroundStyle(done ? .primary : .secondary)
        } icon: {
            if done {
                Image(systemName: "checkmark").foregroundStyle(.green).fontWeight(.bold)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
    }
}

// MARK: - Aviso de estado en Listas

struct VPNBanner: View {
    @Environment(VPNManager.self) private var vpn

    var body: some View {
        NavigationLink {
            VPNSettingsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        switch vpn.phase {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        default: return .red
        }
    }

    private var icon: String {
        vpn.isConnected ? "checkmark.shield" : "exclamationmark.shield"
    }

    private var title: String {
        switch vpn.phase {
        case .connected: return "VPN activa"
        case .connecting: return "Conectando VPN…"
        case .reconnecting(let n): return "Reconectando VPN (\(n)/\(VPNManager.maxAttempts))…"
        case .failed: return "VPN caída · reproducción bloqueada"
        default: return "VPN desconectada · reproducción bloqueada"
        }
    }

    private var subtitle: String {
        if vpn.isConnected {
            return [vpn.exitIP ?? vpn.summary?.endpointHost, "Servidor propio"].compactMap { $0 }.joined(separator: " · ")
        }
        return "Pulsa para ver el estado"
    }
}

// MARK: - Ajustes › VPN

struct VPNSettingsView: View {
    @Environment(VPNManager.self) private var vpn
    @State private var showImport = false
    @State private var confirmDelete = false
    @AppStorage("vpnAutoReconnect") private var autoReconnect = true

    var body: some View {
        Form {
            Section {
                VStack(spacing: 14) {
                    Button { Task { await vpn.toggle() } } label: {
                        Image(systemName: "power")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(stateColor)
                            .frame(width: 96, height: 96)
                            .background(stateColor.opacity(0.15), in: Circle())
                            .overlay(Circle().strokeBorder(stateColor, lineWidth: 3))
                    }
                    .buttonStyle(.plain)
                    .disabled(vpn.summary == nil)
                    .accessibilityLabel(vpn.isConnected ? "Desconectar VPN" : "Conectar VPN")

                    VStack(spacing: 4) {
                        Text(vpn.status.label).font(.title3.bold()).foregroundStyle(stateColor)
                        if let since = vpn.connectedDate, vpn.isConnected {
                            Text(since, style: .timer).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }

                    if vpn.isConnected {
                        HStack(spacing: 8) {
                            stat(ByteCountFormatter.string(fromByteCount: Int64(vpn.rxBytes), countStyle: .binary), "Recibido")
                            stat(ByteCountFormatter.string(fromByteCount: Int64(vpn.txBytes), countStyle: .binary), "Enviado")
                            stat(handshakeText, "Handshake")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent {
                    Label("Fijo", systemImage: "lock.fill").foregroundStyle(.green).font(.subheadline.weight(.semibold))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Siempre con VPN")
                        Text("Se conecta al abrir y no reproduce nada sin el túnel")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $autoReconnect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reconexión automática")
                        Text("Reintenta si el túnel cae o cambias de Wi-Fi a datos")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Comportamiento")
            }

            Section("Servidor") {
                if let s = vpn.summary {
                    LabeledContent("Servidor", value: s.endpoint)
                    LabeledContent("IP de salida", value: vpn.exitIP ?? "—")
                    LabeledContent("Dirección en el túnel", value: s.addresses.joined(separator: ", "))
                    if !s.dns.isEmpty { LabeledContent("DNS", value: s.dns.joined(separator: ", ")) }
                    if !s.routesAllTraffic {
                        Label("La configuración no envía todo el tráfico por la VPN (AllowedIPs sin 0.0.0.0/0).", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Button("Cambiar configuración") { showImport = true }
                    Button("Eliminar configuración", role: .destructive) { confirmDelete = true }
                } else {
                    Button("Importar configuración") { showImport = true }
                }
            }
        }
        .navigationTitle("VPN")
        .sheet(isPresented: $showImport) { ImportVPNView() }
        .confirmationDialog("¿Eliminar la configuración de la VPN?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { Task { await vpn.removeConfiguration() } }
        } message: {
            Text("Tendrás que volver a escanear el QR para ver canales.")
        }
    }

    private var stateColor: Color {
        switch vpn.phase {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        default: return .secondary
        }
    }

    private var handshakeText: String {
        guard let h = vpn.lastHandshake else { return "—" }
        let s = max(0, Int(Date().timeIntervalSince(h)))
        return s < 120 ? "\(s) s" : "\(s / 60) min"
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Importar configuración (QR, archivo o portapapeles)

struct ImportVPNView: View {
    @Environment(VPNManager.self) private var vpn
    @Environment(\.dismiss) private var dismiss
    @State private var showFile = false
    @State private var working = false
    @State private var errorText: String?
    @State private var scanned = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground))
                    if scannerAvailable && !scanned {
                        QRScannerView { code in
                            guard !scanned else { return }
                            scanned = true
                            install(code)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else if working {
                        ProgressView("Configurando…")
                    } else if !scannerAvailable {
                        Label("La cámara no está disponible. Usa un archivo o el portapapeles.", systemImage: "camera.badge.ellipsis")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .frame(height: 340)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Escanea el código QR").font(.title3.bold())
                    Text("En tu servidor ejecuta: sudo qrencode -t ansiutf8 < /etc/wireguard/iphone.conf y apunta la cámara a la pantalla. La configuración se guarda en el Keychain del iPhone y no sale del dispositivo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button { showFile = true } label: {
                        Label("Importar archivo .conf", systemImage: "doc").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { install(text) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(working)
            }
            .padding(20)
            .navigationTitle("Configurar VPN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .fileImporter(isPresented: $showFile, allowedContentTypes: [.item]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    install(text)
                } else {
                    errorText = "No se pudo leer el archivo."
                }
            }
            .interactiveDismissDisabled(working)
        }
    }

    private func install(_ text: String) {
        working = true
        errorText = nil
        Task {
            do {
                try await vpn.install(config: text)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                scanned = false
            }
            working = false
        }
    }
}

/// Lector de QR con VisionKit (iPhone XS o posterior).
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    onCode(text)
                    return
                }
            }
        }
    }
}

// MARK: - Reproductor bloqueado mientras no hay VPN

struct VPNBlockedView: View {
    @Environment(VPNManager.self) private var vpn

    var body: some View {
        VStack(spacing: 14) {
            if case .failed = vpn.phase {
                Image(systemName: "exclamationmark.shield").font(.largeTitle).foregroundStyle(.orange)
            } else {
                ProgressView().controlSize(.large).tint(.yellow)
            }
            Text("Pausado: esperando a la VPN").font(.headline)
            Text(detail)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Button("Reintentar ahora") { Task { await vpn.retryNow() } }
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var detail: String {
        switch vpn.phase {
        case .reconnecting(let n):
            return "Túnel caído · reconectando (\(n)/\(VPNManager.maxAttempts)). El canal seguirá en cuanto vuelva la VPN, sin exponer tu conexión."
        case .failed(let message):
            return message
        case .connecting:
            return "Conectando con el servidor…"
        default:
            return "La VPN está desconectada. ANTENA PRO no reproduce sin ella."
        }
    }
}
