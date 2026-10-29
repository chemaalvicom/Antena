import SwiftUI

// MARK: - Datos

struct Channel: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var url: String
    var logo: String?
    var group: String
    var tvgID: String?
    var userAgent: String?
    var referrer: String?

    /// HLS (.m3u8) lo reproduce bien el motor de Apple; el resto va mejor con VLC.
    var isHLS: Bool { url.lowercased().contains(".m3u8") }

    var streamURL: URL? {
        if let u = URL(string: url) { return u }
        let escaped = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        return URL(string: escaped)
    }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var sourceURL: String?
    var channels: [Channel] = []
    var updatedAt = Date()

    /// Grupos en el orden en que aparecen en la lista.
    var groups: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for c in channels where !seen.contains(c.group) {
            seen.insert(c.group)
            out.append(c.group)
        }
        return out
    }
}

/// Destino de navegación: un grupo concreto (o todos si `group` es nil) de una lista.
struct GroupRoute: Hashable {
    let playlistID: UUID
    let group: String?
}

// MARK: - Ajustes

enum Defaults {
    static let userAgent = "VLC/3.0.21 LibVLC/3.0.21"
    static let userAgentPresets: [(String, String)] = [
        ("VLC", "VLC/3.0.21 LibVLC/3.0.21"),
        ("Safari iPhone", "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"),
        ("Kodi", "Kodi/21.1 (Linux; Android 13) Android/13 Sys_CPU/aarch64 App_Bitness/64 Version/21.1"),
        ("Antena", "Antena/1.0 (iOS)")
    ]
}

enum Engine: String, CaseIterable, Identifiable {
    case auto, apple, vlc
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Automático"
        case .apple: return "Siempre Apple"
        case .vlc: return "Siempre VLC"
        }
    }
}

enum Accent: String, CaseIterable, Identifiable {
    case naranja, rojo, rosa, morado, azul, verde
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .naranja: return Color(red: 1.00, green: 0.48, blue: 0.10)
        case .rojo: return Color(red: 0.92, green: 0.22, blue: 0.24)
        case .rosa: return Color(red: 0.96, green: 0.31, blue: 0.58)
        case .morado: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .azul: return Color(red: 0.16, green: 0.52, blue: 0.98)
        case .verde: return Color(red: 0.18, green: 0.74, blue: 0.42)
        }
    }
}

enum Theme: String, CaseIterable, Identifiable {
    case sistema, oscuro, claro
    var id: String { rawValue }
    var scheme: ColorScheme? {
        switch self {
        case .sistema: return nil
        case .oscuro: return .dark
        case .claro: return .light
        }
    }
}
