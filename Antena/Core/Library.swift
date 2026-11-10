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
    var favoriteLists: [FavoriteList] = []

    private var loaded = false

    private struct UserData: Codable {
        var favorites: [Channel]
        var recents: [Channel]
        var favoriteLists: [FavoriteList]?
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
        if Launch.isDemo {
            playlists = DemoData.playlists
            let all = playlists.first?.channels ?? []
            favorites = [1, 5, 11, 16, 25].compactMap { all.indices.contains($0) ? all[$0] : nil }
            recents = [0, 6, 13, 21].compactMap { all.indices.contains($0) ? all[$0] : nil }
            return
        }
        let dec = JSONDecoder()
        if let d = try? Data(contentsOf: Self.playlistsFile), let p = try? dec.decode([Playlist].self, from: d) {
            playlists = p
        }
        if let d = try? Data(contentsOf: Self.userFile), let u = try? dec.decode(UserData.self, from: d) {
            favorites = u.favorites
            recents = u.recents
            favoriteLists = u.favoriteLists ?? []
        }
        // Listas antiguas sin guía: en Xtream se deduce de la propia dirección
        var changed = false
        for i in playlists.indices where playlists[i].epgURL == nil {
            if let src = playlists[i].sourceURL, let epg = Self.xtreamEPG(from: src) {
                playlists[i].epgURL = epg
                changed = true
            }
        }
        if changed { savePlaylists() }
    }

    private func savePlaylists() {
        if let d = try? JSONEncoder().encode(playlists) { try? d.write(to: Self.playlistsFile, options: .atomic) }
    }

    private func saveUser() {
        let u = UserData(favorites: favorites, recents: recents, favoriteLists: favoriteLists)
        if let d = try? JSONEncoder().encode(u) { try? d.write(to: Self.userFile, options: .atomic) }
    }

    // MARK: Listas

    func addRemote(name: String, urlString: String, userAgent: String) async throws {
        let result = try await Self.download(urlString, userAgent: userAgent)
        let fallback = URL(string: urlString)?.host ?? "Lista"
        let clean = name.trimmingCharacters(in: .whitespaces)
        var p = Playlist(name: clean.isEmpty ? fallback : clean, sourceURL: urlString, channels: result.channels)
        p.epgURL = result.epg ?? Self.xtreamEPG(from: urlString)
        playlists.append(p)
        savePlaylists()
    }

    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let result = try Self.decode(data)
        var p = Playlist(name: url.deletingPathExtension().lastPathComponent, channels: result.channels)
        p.epgURL = result.epg
        playlists.append(p)
        savePlaylists()
    }

    func refresh(_ id: UUID, userAgent: String) async throws {
        guard let src = playlists.first(where: { $0.id == id })?.sourceURL else { return }
        let result = try await Self.download(src, userAgent: userAgent)
        if let i = playlists.firstIndex(where: { $0.id == id }) {
            playlists[i].channels = result.channels
            playlists[i].updatedAt = Date()
            if let epg = result.epg ?? Self.xtreamEPG(from: src), playlists[i].epgURL == nil {
                playlists[i].epgURL = epg
            }
            savePlaylists()
        }
    }

    func setEPG(_ id: UUID, url: String) {
        guard let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        playlists[i].epgURL = clean.isEmpty ? nil : clean
        savePlaylists()
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
            for j in favoriteLists.indices { favoriteLists[j].urls.removeAll { $0 == c.url } }
        } else {
            favorites.append(c)
        }
        saveUser()
    }

    // MARK: Listas de favoritos

    /// Canales de una lista de favoritos (nil = todos los favoritos).
    func favorites(in listID: UUID?) -> [Channel] {
        guard let listID, let list = favoriteLists.first(where: { $0.id == listID }) else { return favorites }
        return list.urls.compactMap { u in favorites.first { $0.url == u } }
    }

    func isInList(_ c: Channel, _ listID: UUID) -> Bool {
        favoriteLists.first { $0.id == listID }?.urls.contains(c.url) ?? false
    }

    func toggle(_ c: Channel, inList listID: UUID) {
        guard let i = favoriteLists.firstIndex(where: { $0.id == listID }) else { return }
        if let j = favoriteLists[i].urls.firstIndex(of: c.url) {
            favoriteLists[i].urls.remove(at: j)
        } else {
            if !isFavorite(c) { favorites.append(c) }
            favoriteLists[i].urls.append(c.url)
        }
        saveUser()
    }

    @discardableResult
    func addFavoriteList(name: String) -> UUID {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let list = FavoriteList(name: clean.isEmpty ? "Lista \(favoriteLists.count + 1)" : clean)
        favoriteLists.append(list)
        saveUser()
        return list.id
    }

    func renameFavoriteList(_ id: UUID, to name: String) {
        guard let i = favoriteLists.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        favoriteLists[i].name = name
        saveUser()
    }

    func deleteFavoriteList(_ id: UUID) {
        favoriteLists.removeAll { $0.id == id }
        saveUser()
    }

    /// Quita un canal de una lista concreta, o de favoritos si listID es nil.
    func removeFavorite(_ c: Channel, from listID: UUID?) {
        if let listID, let i = favoriteLists.firstIndex(where: { $0.id == listID }) {
            favoriteLists[i].urls.removeAll { $0 == c.url }
            saveUser()
        } else if isFavorite(c) {
            toggleFavorite(c)
        }
    }

    /// Mueve un favorito una posición (delta -1 o +1) dentro de "Todos" o de una lista.
    func moveFavorite(_ c: Channel, by delta: Int, in listID: UUID?) {
        if let listID, let i = favoriteLists.firstIndex(where: { $0.id == listID }) {
            var urls = favoriteLists[i].urls
            guard let from = urls.firstIndex(of: c.url) else { return }
            let to = from + delta
            guard urls.indices.contains(to) else { return }
            urls.swapAt(from, to)
            favoriteLists[i].urls = urls
        } else {
            guard let from = favorites.firstIndex(where: { $0.url == c.url }) else { return }
            let to = from + delta
            guard favorites.indices.contains(to) else { return }
            favorites.swapAt(from, to)
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

    nonisolated static func download(_ s: String, userAgent: String) async throws -> (channels: [Channel], epg: String?) {
        guard let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw LibraryError.badURL }
        var req = URLRequest(url: url, timeoutInterval: 90)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibraryError.http(http.statusCode)
        }
        return try decode(data)
    }

    nonisolated static func decode(_ data: Data) throws -> (channels: [Channel], epg: String?) {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let channels = M3UParser.parse(text)
        if channels.isEmpty { throw LibraryError.empty }
        return (channels, M3UParser.epgURL(in: text))
    }

    /// Guía de un proveedor Xtream: mismo servidor y cuenta que get.php, pero xmltv.php.
    nonisolated static func xtreamEPG(from urlString: String) -> String? {
        guard var comps = URLComponents(string: urlString), comps.path.lowercased().hasSuffix("get.php"),
              let items = comps.queryItems,
              let user = items.first(where: { $0.name.lowercased() == "username" })?.value,
              let pass = items.first(where: { $0.name.lowercased() == "password" })?.value else { return nil }
        comps.path = String(comps.path.dropLast("get.php".count)) + "xmltv.php"
        comps.queryItems = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: pass)]
        return comps.string
    }

    // MARK: Varias listas desde el portapapeles

    func hasSource(_ urlString: String) -> Bool {
        playlists.contains { $0.sourceURL == urlString }
    }

    /// Saca todas las direcciones http(s) de un texto (una por línea, separadas por espacios
    /// o mezcladas con otro texto), sin repetidas y en el orden en que aparecen.
    nonisolated static func playlistLinks(in text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let tokens = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'")))
        for token in tokens {
            var t = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;()[]"))
            guard let start = t.range(of: "http", options: .caseInsensitive) else { continue }
            t = String(t[start.lowerBound...])
            guard let url = URL(string: t), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host != nil else { continue }
            if seen.insert(t).inserted { out.append(t) }
        }
        return out
    }

    /// Nombre propuesto: servidor + usuario en enlaces Xtream, o el nombre del archivo.
    nonisolated static func suggestedName(for urlString: String) -> String {
        guard let comps = URLComponents(string: urlString) else { return "Lista" }
        let host = comps.host ?? "Lista"
        if let user = comps.queryItems?.first(where: { $0.name.lowercased() == "username" })?.value, !user.isEmpty {
            return "\(host) · \(user)"
        }
        let file = (comps.path as NSString).lastPathComponent
        let stem = (file as NSString).deletingPathExtension
        if !stem.isEmpty, !["get", "playlist", "index", "list"].contains(stem.lowercased()) {
            return stem
        }
        return host
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
