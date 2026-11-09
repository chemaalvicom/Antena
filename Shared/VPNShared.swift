import Foundation
import Security

/// Constantes y utilidades compartidas entre la app y la extensión del túnel.
enum VPNShared {
    /// App Group común a la app y a la extensión. Debe existir en el portal de Apple
    /// y estar marcado en los dos App IDs.
    static let appGroup = "group.com.chemablanco.antenapro"
    static let tunnelBundleID = "com.chemablanco.antenapro.tunnel"
    static let tunnelName = "ANTENA PRO"

    // Claves del Keychain donde se guarda la configuración wg-quick completa.
    static let keychainService = "com.chemablanco.antenapro.wireguard"
    static let keychainAccount = "config"

    /// Mensaje que la app envía a la extensión para pedir estadísticas en vivo.
    static let statsMessage: UInt8 = 1
}

// MARK: - Keychain

/// Guarda la configuración de WireGuard en el Keychain, compartida con la extensión a
/// través del App Group. Nunca sale del dispositivo ni se incluye en copias de iCloud.
enum ConfigKeychain {
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: VPNShared.keychainService,
            kSecAttrAccount as String: VPNShared.keychainAccount,
            kSecAttrAccessGroup as String: VPNShared.appGroup
        ]
    }

    static func save(_ config: String) throws {
        let data = Data(config.utf8)
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        // Accesible tras el primer desbloqueo para que el túnel pueda arrancar en segundo plano.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func load() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "código \(status)"
            return "No se pudo guardar en el Keychain (\(msg))."
        }
    }
}

// MARK: - Validación ligera del formato wg-quick

/// Resumen de una configuración wg-quick, sin depender de WireGuardKit (la app no lo enlaza).
struct WGConfigSummary: Equatable {
    var endpoint: String
    var addresses: [String]
    var dns: [String]
    var routesAllTraffic: Bool

    /// Host del servidor sin el puerto (sirve para mostrar la IP de salida esperada).
    var endpointHost: String {
        if endpoint.hasPrefix("["), let end = endpoint.firstIndex(of: "]") {
            return String(endpoint[endpoint.index(after: endpoint.startIndex)..<end])
        }
        return endpoint.split(separator: ":").first.map(String.init) ?? endpoint
    }

    enum ParseError: LocalizedError {
        case notWireGuard
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .notWireGuard:
                return "No parece una configuración de WireGuard. Debe tener las secciones [Interface] y [Peer]."
            case .missing(let key):
                return "A la configuración le falta «\(key)»."
            }
        }
    }

    /// Lee las secciones y comprueba que estén los campos imprescindibles.
    static func parse(_ text: String) throws -> WGConfigSummary {
        var section = ""
        var iface: [String: String] = [:]
        var peer: [String: String] = [:]
        var peers = 0

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                section = line.lowercased()
                if section == "[peer]" { peers += 1 }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if section == "[interface]" { iface[key] = value }
            if section == "[peer]" && peers == 1 { peer[key] = value }
        }

        guard !iface.isEmpty, peers > 0 else { throw ParseError.notWireGuard }
        guard iface["privatekey"] != nil else { throw ParseError.missing("PrivateKey") }
        guard iface["address"] != nil else { throw ParseError.missing("Address") }
        guard peer["publickey"] != nil else { throw ParseError.missing("PublicKey") }
        guard let endpoint = peer["endpoint"] else { throw ParseError.missing("Endpoint") }

        let list: (String?) -> [String] = { value in
            (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        let allowed = list(peer["allowedips"])
        return WGConfigSummary(
            endpoint: endpoint,
            addresses: list(iface["address"]),
            dns: list(iface["dns"]),
            routesAllTraffic: allowed.contains("0.0.0.0/0")
        )
    }
}
