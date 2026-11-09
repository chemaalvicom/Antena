import Foundation
import NetworkExtension
import Observation

/// Gestiona el túnel WireGuard de ANTENA PRO: instalación de la configuración,
/// conexión automática, reconexión y estadísticas.
@MainActor
@Observable
final class VPNManager {
    enum Phase: Equatable {
        case loading
        case needsConfig
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case disconnected
        case failed(String)
    }

    static let maxAttempts = 5

    private(set) var loaded = false
    private(set) var status: NEVPNStatus = .invalid
    private(set) var summary: WGConfigSummary?
    private(set) var connectedDate: Date?
    private(set) var exitIP: String?
    private(set) var rxBytes: UInt64 = 0
    private(set) var txBytes: UInt64 = 0
    private(set) var lastHandshake: Date?
    private(set) var attempt = 0
    private(set) var lastError: String?
    /// Hay un reintento programado.
    private(set) var retrying = false
    /// Se pone a true la primera vez que conecta en esta sesión (deja pasar la pantalla de arranque).
    private(set) var hasConnectedOnce = false

    @ObservationIgnored private var manager: NETunnelProviderManager?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// true si el usuario ha pulsado desconectar: no se reconecta solo.
    @ObservationIgnored private var userStopped = false

    var isConnected: Bool { status == .connected }

    var autoReconnect: Bool {
        get { UserDefaults.standard.object(forKey: "vpnAutoReconnect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "vpnAutoReconnect") }
    }

    var phase: Phase {
        if !loaded { return .loading }
        if summary == nil { return .needsConfig }
        switch status {
        case .connected:
            return .connected
        case .connecting, .reasserting:
            return attempt > 0 ? .reconnecting(attempt: attempt) : .connecting
        default:
            if retrying { return .reconnecting(attempt: attempt) }
            if let lastError { return .failed(lastError) }
            return .disconnected
        }
    }

    // MARK: Arranque

    /// Carga la configuración guardada y conecta. Se llama al abrir la app.
    func start() async {
        if !loaded {
            if let text = ConfigKeychain.load() {
                summary = try? WGConfigSummary.parse(text)
            }
            do {
                let all = try await NETunnelProviderManager.loadAllFromPreferences()
                manager = all.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == VPNShared.tunnelBundleID
                }
            } catch {
                lastError = "No se pudo leer la VPN del sistema: \(error.localizedDescription)"
            }
            observeStatus()
            loaded = true
        }
        if summary != nil && !isConnected && status != .connecting {
            userStopped = false
            await connect()
        }
    }

    /// Al volver a primer plano: si el túnel se cayó con la app en segundo plano, se levanta.
    func resume() async {
        guard loaded, summary != nil, !userStopped else { return }
        if status == .disconnected || status == .invalid {
            attempt = 0
            await connect()
        }
    }

    // MARK: Configuración

    /// Valida, guarda en el Keychain, registra la VPN en el sistema y conecta.
    func install(config raw: String) async throws {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try WGConfigSummary.parse(text)
        try ConfigKeychain.save(text)
        summary = parsed

        let mgr = manager ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = VPNShared.tunnelBundleID
        proto.serverAddress = parsed.endpoint
        mgr.protocolConfiguration = proto
        mgr.localizedDescription = VPNShared.tunnelName
        mgr.isEnabled = true
        // La primera vez iOS pide permiso para "Añadir configuración VPN".
        try await mgr.saveToPreferences()
        try await mgr.loadFromPreferences()
        manager = mgr
        observeStatus()

        // Si ya había túnel, se reinicia con la configuración nueva.
        if status == .connected || status == .connecting {
            mgr.connection.stopVPNTunnel()
            try? await Task.sleep(for: .seconds(1))
        }
        attempt = 0
        lastError = nil
        userStopped = false
        await connect()
    }

    func removeConfiguration() async {
        userStopped = true
        cancelRetry()
        lastError = nil
        manager?.connection.stopVPNTunnel()
        try? await manager?.removeFromPreferences()
        manager = nil
        ConfigKeychain.delete()
        summary = nil
        status = .invalid
        exitIP = nil
    }

    // MARK: Conexión

    func connect() async {
        guard let mgr = manager else {
            // Hay configuración en el Keychain pero la VPN no está en el sistema (por ejemplo,
            // se borró en Ajustes de iOS): se vuelve a registrar.
            if let text = ConfigKeychain.load() {
                do {
                    try await install(config: text)
                } catch {
                    lastError = "No se pudo registrar la VPN: \(error.localizedDescription)"
                }
            }
            return
        }
        cancelRetry()
        do {
            // Otra VPN activa desactiva la nuestra: se vuelve a activar.
            if !mgr.isEnabled {
                mgr.isEnabled = true
                try await mgr.saveToPreferences()
                try await mgr.loadFromPreferences()
            }
            try mgr.connection.startVPNTunnel()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            scheduleRetry()
        }
    }

    /// Botón de encender/apagar en Ajustes › VPN.
    func toggle() async {
        if isConnected || status == .connecting || status == .reasserting {
            userStopped = true
            cancelRetry()
            attempt = 0
            lastError = nil
            manager?.connection.stopVPNTunnel()
        } else {
            userStopped = false
            attempt = 0
            await connect()
        }
    }

    /// Reintento manual desde la pantalla de "reconectando" o de error.
    func retryNow() async {
        userStopped = false
        attempt = 0
        lastError = nil
        await connect()
    }

    private func observeStatus() {
        guard let mgr = manager else { return }
        status = mgr.connection.status
        connectedDate = mgr.connection.connectedDate
        statusTask?.cancel()
        let connection = mgr.connection
        statusTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NEVPNStatusDidChange, object: connection) {
                guard let self else { return }
                self.statusChanged(connection.status, connectedDate: connection.connectedDate)
            }
        }
    }

    private func statusChanged(_ new: NEVPNStatus, connectedDate date: Date?) {
        let old = status
        status = new
        connectedDate = date
        switch new {
        case .connected:
            attempt = 0
            lastError = nil
            hasConnectedOnce = true
            cancelRetry()
            startStats()
            Task { await checkExitIP() }
        case .disconnected, .invalid:
            stopStats()
            exitIP = nil
            if old != new && !userStopped && summary != nil && autoReconnect {
                if lastError == nil { lastError = "Se ha perdido la conexión con el servidor." }
                scheduleRetry()
            }
        default:
            break
        }
    }

    /// Reintentos con espera creciente: 1, 2, 4, 8 y 15 segundos.
    private func scheduleRetry() {
        guard !userStopped, attempt < Self.maxAttempts else {
            retrying = false
            return
        }
        attempt += 1
        let delays: [Double] = [1, 2, 4, 8, 15]
        let wait = delays[min(attempt - 1, delays.count - 1)]
        retryTask?.cancel()
        retrying = true
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.retrying = false
            guard let mgr = self.manager else { return }
            do {
                try mgr.connection.startVPNTunnel()
            } catch {
                self.lastError = error.localizedDescription
                self.scheduleRetry()
            }
        }
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        retrying = false
    }

    // MARK: Estadísticas

    private func startStats() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopStats() {
        statsTask?.cancel()
        statsTask = nil
    }

    private func refreshStats() async {
        guard let session = manager?.connection as? NETunnelProviderSession, isConnected else { return }
        let reply: Data? = await withCheckedContinuation { cont in
            do {
                try session.sendProviderMessage(Data([VPNShared.statsMessage])) { cont.resume(returning: $0) }
            } catch {
                cont.resume(returning: nil)
            }
        }
        guard let reply, let text = String(data: reply, encoding: .utf8) else { return }
        var rx: UInt64 = 0, tx: UInt64 = 0, handshake: TimeInterval = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "rx_bytes": rx += UInt64(parts[1]) ?? 0
            case "tx_bytes": tx += UInt64(parts[1]) ?? 0
            case "last_handshake_time_sec": handshake = max(handshake, TimeInterval(parts[1]) ?? 0)
            default: break
            }
        }
        rxBytes = rx
        txBytes = tx
        lastHandshake = handshake > 0 ? Date(timeIntervalSince1970: handshake) : nil
    }

    /// Pregunta a un servicio público qué IP ve: debe ser la del servidor.
    func checkExitIP() async {
        var req = URLRequest(url: URL(string: "https://api.ipify.org")!, timeoutInterval: 8)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let result = try? await URLSession.shared.data(for: req),
           let ip = String(data: result.0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ip.isEmpty, ip.count < 64 {
            exitIP = ip
        }
    }
}

extension NEVPNStatus {
    var label: String {
        switch self {
        case .connected: return "Conectado"
        case .connecting: return "Conectando…"
        case .reasserting: return "Reconectando…"
        case .disconnecting: return "Desconectando…"
        case .disconnected: return "Desconectado"
        case .invalid: return "Sin configurar"
        @unknown default: return "Desconocido"
        }
    }
}
