import Foundation

/// Argumentos de arranque (los usa el flujo de capturas del simulador).
///   -demo            carga una lista de ejemplo sin tocar tus datos
///   -tab N           abre la pestaña N (0 Listas, 1 Favoritos, 2 Recientes, 3 Ajustes)
///   -open playlist   entra en la primera lista
///   -open group      entra en el primer grupo de la primera lista
///   -add             abre la hoja "Añadir lista"
///   -play            reproduce el primer canal
enum Launch {
    static let args = ProcessInfo.processInfo.arguments
    static func has(_ key: String) -> Bool { args.contains(key) }
    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var isDemo: Bool { has("-demo") }
}

enum DemoData {
    static let testStream = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"

    static var m3u: String {
        let groups: [(String, [String])] = [
            ("Noticias", ["Actualidad 24h", "Mundo Hoy", "Economía Directo", "Canal Parlamento", "Tiempo y Tráfico"]),
            ("Deportes", ["Deportes HD", "Fútbol Total", "Motor Plus", "Baloncesto TV", "Tenis Center", "Golf & Más"]),
            ("Cine", ["Cine Clásico", "Estrenos HD", "Acción 24", "Comedia Club", "Cine Español"]),
            ("Series", ["Series Max", "Thriller TV", "Drama Plus", "Sitcom 90"]),
            ("Infantil", ["Peques TV", "Dibujos 24", "Junior Club"]),
            ("Música", ["Hits Radio TV", "Rock FM Vídeo", "Clásica en Vivo"]),
            ("Documentales", ["Naturaleza HD", "Historia TV", "Ciencia y Futuro", "Viajes 4K"])
        ]
        var out = "#EXTM3U\n"
        var n = 0
        for (group, names) in groups {
            for name in names {
                let url = n == 0 ? testStream : "http://demo.antena.local/live/\(n).ts"
                out += "#EXTINF:-1 tvg-id=\"c\(n)\" tvg-name=\"\(name)\" group-title=\"\(group)\",\(name)\n\(url)\n"
                n += 1
            }
        }
        return out
    }

    static var playlists: [Playlist] {
        let channels = M3UParser.parse(m3u)
        return [
            Playlist(name: "Mi IPTV", sourceURL: "http://demo.antena.local/lista.m3u", channels: channels, updatedAt: Date().addingTimeInterval(-3600)),
            Playlist(name: "Deportes extra", sourceURL: nil, channels: Array(channels.filter { $0.group == "Deportes" }), updatedAt: Date().addingTimeInterval(-86400 * 2))
        ]
    }
}
