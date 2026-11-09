import NetworkExtension
import WireGuardKit
import os.log

/// Extensión Packet Tunnel de ANTENA PRO: levanta WireGuard con la configuración
/// guardada en el Keychain compartido.
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let log = Logger(subsystem: VPNShared.tunnelBundleID, category: "tunnel")

    private lazy var adapter: WireGuardAdapter = {
        WireGuardAdapter(with: self) { [log] level, message in
            switch level {
            case .error: log.error("\(message, privacy: .public)")
            default: log.debug("\(message, privacy: .public)")
            }
        }
    }()

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard let text = ConfigKeychain.load() else {
            log.error("No hay configuración en el Keychain")
            completionHandler(TunnelError.noConfiguration)
            return
        }
        let configuration: TunnelConfiguration
        do {
            configuration = try WGQuickParser.parse(text, name: VPNShared.tunnelName)
        } catch {
            log.error("Configuración no válida: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
            return
        }

        adapter.start(tunnelConfiguration: configuration) { [log] adapterError in
            if let adapterError {
                log.error("No se pudo arrancar WireGuard: \(String(describing: adapterError), privacy: .public)")
                completionHandler(TunnelError.adapter(String(describing: adapterError)))
            } else {
                log.info("Túnel iniciado (\(self.adapter.interfaceName ?? "utun", privacy: .public))")
                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        adapter.stop { _ in completionHandler() }
    }

    /// La app pide estadísticas (bytes y último handshake) con un mensaje de un byte.
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let completionHandler else { return }
        guard messageData.first == VPNShared.statsMessage else {
            completionHandler(nil)
            return
        }
        adapter.getRuntimeConfiguration { settings in
            completionHandler(settings.map { Data($0.utf8) })
        }
    }
}

enum TunnelError: LocalizedError {
    case noConfiguration
    case adapter(String)

    var errorDescription: String? {
        switch self {
        case .noConfiguration: return "No hay configuración de VPN. Impórtala desde ANTENA PRO."
        case .adapter(let detail): return "WireGuard no pudo arrancar (\(detail))."
        }
    }
}
