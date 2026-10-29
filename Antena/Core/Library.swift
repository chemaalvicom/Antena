import SwiftUI
import Observation

enum LibraryError: LocalizedError {
    case badURL
    case http(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "La dirección no es válida."
        case .http(let code): return "El servidor respondió con error \(code)."
        case .empty: return "No se encontraron canales. Comprueba que sea una lista M3U."
        }
    }
}

/// Todo lo que guarda la app: listas, favoritos y recientes. Se guarda en JSON local, sin nube ni rastreo.
@MainActor
@Observable
final class Library {
    var playlists: [Playlist] = []
    var favorites: [Channel] = []
    var recents: [Channel] = []

    private var loaded = false

    private struct UserData: Codable {
        var favorites: [Channel]
        var recents: [Channel]
    }

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Antena", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var playlistsFile: URL { folder.appendingPathComponent("listas.json") }
    private static var userFile: URL { folder.appendingPathComponent("usuario.json") }

    // MARK: Carga y guardado

    func load() {
        guard !loaded else { return }
        loaded = true
        let dec = JSONDecoder()
        if let d = try? Data(contentsOf: Self.playlistsFile), let p = try? dec.decode([Playlist].self, from: d) {
            playlists = p
        }
        if let d = try? Data(contentsOf: Self.userFile), let u = try? dec.decode(UserData.self, from: d) {
            favorites = u.favorites
            recents = u.recents
        }
    }

    private func savePlaylists() {
        if let d = try? JSONEncoder().encode(playlists) { try? d.write(to: Self.playlistsFile, options: .atomic) }
    }

    private func saveUser() {
        let u = UserData(favorites: favorites, recents: recents)
        if let d = try? JSONEncoder().encode(u) { try? d.write(to: Self.userFile, options: .atomic) }
    }

    // MARK: Listas

    func addRemote(name: String, urlString: String, userAgent: String) async throws {
        let channels = try await Self.download(urlString, userAgent: userAgent)
        let fallback = URL(string: urlString)?.host ?? "Lista"
        let clean = name.trimmingCharacters(in: .whitespaces)
        playlists.append(Playlist(name: clean.isEmpty ? fallback : clean, sourceURL: urlString, channels: channels))
        savePlaylists()
    }

    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let channels = try Self.decode(data)
        playlists.append(Playlist(name: url.deletingPathExtension().lastPathComponent, channels: channels))
        savePlaylists()
    }

    func refresh(_ id: UUID, userAgent: String) async throws {
        guard let src = playlists.first(where: { $0.id == id })?.sourceURL else { return }
        let channels = try await Self.download(src, userAgent: userAgent)
        if let i = playlists.firstIndex(where: { $0.id == id }) {
            playlists[i].channels = channels
            playlists[i].updatedAt = Date()
            savePlaylists()
        }
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        playlists[i].name = name
        savePlaylists()
    }

    func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        savePlaylists()
    }

    func movePlaylists(from source: IndexSet, to destination: Int) {
        playlists.move(fromOffsets: source, toOffset: destination)
        savePlaylists()
    }

    // MARK: Favoritos y recientes

    func isFavorite(_ c: Channel) -> Bool { favorites.contains { $0.url == c.url } }

    func toggleFavorite(_ c: Channel) {
        if let i = favorites.firstIndex(where: { $0.url == c.url }) {
            favorites.remove(at: i)
        } else {
            favorites.append(c)
        }
        saveUser()
    }

    func deleteFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        saveUser()
    }

    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        saveUser()
    }

    func markPlayed(_ c: Channel) {
        recents.removeAll { $0.url == c.url }
        recents.insert(c, at: 0)
        if recents.count > 40 { recents = Array(recents.prefix(40)) }
        saveUser()
    }

    func clearRecents() {
        recents.removeAll()
        saveUser()
    }

    // MARK: Red

    nonisolated static func download(_ s: String, userAgent: String) async throws -> [Channel] {
        guard let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw LibraryError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibraryError.http(http.statusCode)
        }
        return try decode(data)
    }

    nonisolated static func decode(_ data: Data) throws -> [Channel] {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let channels = M3UParser.parse(text)
        if channels.isEmpty { throw LibraryError.empty }
        return channels
    }

    /// URL M3U para proveedores Xtream Codes (servidor + usuario + contraseña).
    nonisolated static func xtreamURL(server: String, user: String, password: String, hls: Bool) -> String {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.lowercased().hasPrefix("http") { base = "http://" + base }
        while base.hasSuffix("/") { base.removeLast() }
        let u = user.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? user
        let p = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        return "\(base)/get.php?username=\(u)&password=\(p)&type=m3u_plus&output=\(hls ? "m3u8" : "ts")"
    }
}
