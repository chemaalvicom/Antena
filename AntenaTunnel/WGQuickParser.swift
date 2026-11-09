import Foundation
import WireGuardKit

/// Convierte un archivo wg-quick (lo que genera el servidor y muestra el QR) en la
/// configuración de WireGuardKit. Soporta un [Interface] y uno o varios [Peer].
enum WGQuickParser {
    enum ParseError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self {
            case .invalid(let what): return "Valor no válido en la configuración: \(what)"
            }
        }
    }

    static func parse(_ text: String, name: String) throws -> TunnelConfiguration {
        var sections: [(name: String, values: [String: String])] = []

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                sections.append((line.lowercased(), [:]))
                continue
            }
            guard !sections.isEmpty, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            sections[sections.count - 1].values[key] = value
        }

        guard let ifaceValues = sections.first(where: { $0.name == "[interface]" })?.values else {
            throw ParseError.invalid("falta [Interface]")
        }
        guard let keyText = ifaceValues["privatekey"], let privateKey = PrivateKey(base64Key: keyText) else {
            throw ParseError.invalid("PrivateKey")
        }

        var iface = InterfaceConfiguration(privateKey: privateKey)
        iface.addresses = try list(ifaceValues["address"]).map {
            guard let r = IPAddressRange(from: $0) else { throw ParseError.invalid("Address \($0)") }
            return r
        }
        // DNS puede mezclar servidores y dominios de búsqueda.
        for item in list(ifaceValues["dns"]) {
            if let server = DNSServer(from: item) {
                iface.dns.append(server)
            } else {
                iface.dnsSearch.append(item)
            }
        }
        if let mtu = ifaceValues["mtu"] {
            guard let v = UInt16(mtu) else { throw ParseError.invalid("MTU") }
            iface.mtu = v
        }
        if let port = ifaceValues["listenport"] {
            guard let v = UInt16(port) else { throw ParseError.invalid("ListenPort") }
            iface.listenPort = v
        }

        var peers: [PeerConfiguration] = []
        for section in sections where section.name == "[peer]" {
            let v = section.values
            guard let pubText = v["publickey"], let publicKey = PublicKey(base64Key: pubText) else {
                throw ParseError.invalid("PublicKey")
            }
            var peer = PeerConfiguration(publicKey: publicKey)
            if let psk = v["presharedkey"] {
                guard let key = PreSharedKey(base64Key: psk) else { throw ParseError.invalid("PresharedKey") }
                peer.preSharedKey = key
            }
            peer.allowedIPs = try list(v["allowedips"]).map {
                guard let r = IPAddressRange(from: $0) else { throw ParseError.invalid("AllowedIPs \($0)") }
                return r
            }
            if let ep = v["endpoint"] {
                guard let endpoint = Endpoint(from: ep) else { throw ParseError.invalid("Endpoint \(ep)") }
                peer.endpoint = endpoint
            }
            if let ka = v["persistentkeepalive"], ka.lowercased() != "off" {
                guard let value = UInt16(ka) else { throw ParseError.invalid("PersistentKeepalive") }
                peer.persistentKeepAlive = value
            }
            peers.append(peer)
        }
        guard !peers.isEmpty else { throw ParseError.invalid("falta [Peer]") }

        return TunnelConfiguration(name: name, interface: iface, peers: peers)
    }

    private static func list(_ value: String?) -> [String] {
        (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
