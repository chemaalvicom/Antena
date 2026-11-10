import Foundation
import Observation
import Compression

// MARK: - Datos de la guía

/// Un programa de la guía (XMLTV). Las horas se guardan en UTC.
struct EPGProgram: Codable, Hashable, Identifiable {
    var channel: String
    var start: Date
    var stop: Date
    var title: String
    var desc: String?

    var id: String { "\(channel)|\(start.timeIntervalSince1970)" }

    func isLive(at now: Date) -> Bool { start <= now && now < stop }

    func progress(at now: Date) -> Double {
        let total = stop.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    func minutesLeft(at now: Date) -> Int {
        max(0, Int(stop.timeIntervalSince(now) / 60.0 + 0.5))
    }

    var timeRange: String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(stop.formatted(date: .omitted, time: .shortened))"
    }
}

/// Guía de una lista: programas por canal (ordenados) y nombres de canal para cruzar sin tvg-id.
struct EPGData: Codable {
    var programs: [String: [EPGProgram]]
    var names: [String: String]
    var fetchedAt: Date

    var programCount: Int { programs.values.reduce(0) { $0 + $1.count } }
}

struct ProgramHit: Identifiable {
    let program: EPGProgram
    let channel: Channel
    let playlist: UUID
    var id: String { "\(program.id)|\(channel.id)" }
}

struct ChannelHit: Identifiable {
    let channel: Channel
    let playlist: UUID
    var id: String { channel.url }
}

enum EPGError: LocalizedError {
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .http(let code): return "El servidor de la guía respondió con error \(code)."
        case .unreadable: return "El archivo de la guía no es un XMLTV válido."
        }
    }
}

// MARK: - Almacén

/// Descarga, guarda en caché y consulta la guía de programación de cada lista.
@MainActor
@Observable
final class EPGStore {
    private(set) var guides: [UUID: EPGData] = [:]
    private(set) var loading: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]
    /// Hora de referencia para barras de progreso; se actualiza cada 30 s desde la interfaz.
    var now = Date()

    /// Caché de qué clave de la guía corresponde a cada canal.
    @ObservationIgnored private var keyCache: [UUID: [String: String]] = [:]
    @ObservationIgnored private var cacheLoaded = false

    static let maxAge: TimeInterval = 12 * 3600

    nonisolated private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Antena/Guia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated private static func cacheFile(_ id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: Carga

    /// Lee las guías guardadas en disco (rápido, sin red).
    func loadCached(_ playlists: [Playlist]) async {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        for p in playlists {
            let url = Self.cacheFile(p.id)
            let decoded: EPGData? = await Task.detached(priority: .utility) {
                guard let d = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(EPGData.self, from: d)
            }.value
            if let decoded { set(decoded, for: p.id) }
        }
    }

    /// Descarga las guías que falten o tengan más de 12 horas.
    func refreshIfNeeded(_ playlists: [Playlist], userAgent: String, force: Bool = false) async {
        for p in playlists {
            guard let src = p.epgURL, !src.isEmpty, !loading.contains(p.id) else { continue }
            if !force, let g = guides[p.id], Date().timeIntervalSince(g.fetchedAt) < Self.maxAge { continue }
            await refresh(p, from: src, userAgent: userAgent)
        }
        // Quita guías de listas que ya no existen
        let ids = Set(playlists.map(\.id))
        for id in guides.keys where !ids.contains(id) {
            guides[id] = nil
            keyCache[id] = nil
            try? FileManager.default.removeItem(at: Self.cacheFile(id))
        }
    }

    private func refresh(_ p: Playlist, from src: String, userAgent: String) async {
        guard let url = URL(string: src.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errors[p.id] = "La dirección de la guía no es válida."
            return
        }
        loading.insert(p.id)
        defer { loading.remove(p.id) }
        do {
            var req = URLRequest(url: url, timeoutInterval: 180)
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let (raw, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw EPGError.http(http.statusCode)
            }
            let id = p.id
            let parsed: EPGData? = await Task.detached(priority: .utility) {
                let data = Gzip.isCompressed(raw) ? (Gzip.decompress(raw) ?? Data()) : raw
                let now = Date()
                let parser = XMLTVParser(from: now.addingTimeInterval(-6 * 3600), to: now.addingTimeInterval(48 * 3600))
                guard parser.parse(data) || !parser.programs.isEmpty else { return nil }
                let result = EPGData(programs: parser.finished(), names: parser.names, fetchedAt: now)
                if let encoded = try? JSONEncoder().encode(result) {
                    try? encoded.write(to: EPGStore.cacheFile(id), options: .atomic)
                }
                return result
            }.value
            guard let parsed, !parsed.programs.isEmpty else { throw EPGError.unreadable }
            set(parsed, for: id)
            errors[id] = nil
        } catch {
            errors[p.id] = error.localizedDescription
        }
    }

    private func set(_ data: EPGData, for id: UUID) {
        guides[id] = data
        keyCache[id] = [:]
    }

    // MARK: Consultas

    nonisolated static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Nombre simplificado para cruzar canales sin tvg-id: sin acentos, sin calidad ni símbolos.
    nonisolated static func normName(_ s: String) -> String {
        var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        for tag in [" fhd", " uhd", " 4k", " hd", " sd", " hevc", " 1080p", " 720p"] {
            t = t.replacingOccurrences(of: tag, with: " ")
        }
        return String(t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private func resolveKey(_ ch: Channel, in pid: UUID) -> String? {
        guard let g = guides[pid] else { return nil }
        if let cached = keyCache[pid]?[ch.id] { return cached.isEmpty ? nil : cached }
        var found: String?
        if let t = ch.tvgID, !t.isEmpty, g.programs[Self.key(t)] != nil {
            found = Self.key(t)
        } else if let byName = g.names[Self.normName(ch.name)], g.programs[byName] != nil {
            found = byName
        } else if let t = ch.tvgID, !t.isEmpty, let byName = g.names[Self.normName(t)], g.programs[byName] != nil {
            found = byName
        }
        keyCache[pid, default: [:]][ch.id] = found ?? ""
        return found
    }

    func programs(for ch: Channel, playlist: UUID?) -> [EPGProgram] {
        guard let pid = playlist, let key = resolveKey(ch, in: pid) else { return [] }
        return guides[pid]?.programs[key] ?? []
    }

    func current(for ch: Channel, playlist: UUID?) -> EPGProgram? {
        programs(for: ch, playlist: playlist).first { $0.isLive(at: now) }
    }

    func next(for ch: Channel, playlist: UUID?) -> EPGProgram? {
        programs(for: ch, playlist: playlist).first { $0.start >= now }
    }

    func programs(for ch: Channel, playlist: UUID?, from: Date, to: Date) -> [EPGProgram] {
        programs(for: ch, playlist: playlist).filter { $0.stop > from && $0.start < to }
    }

    /// Busca programas por título en las próximas horas.
    func search(_ query: String, in playlists: [Playlist], limit: Int = 60) -> [ProgramHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var out: [ProgramHit] = []
        for p in playlists {
            guard let g = guides[p.id] else { continue }
            var byKey: [String: Channel] = [:]
            for ch in p.channels {
                if let k = resolveKey(ch, in: p.id), byKey[k] == nil { byKey[k] = ch }
            }
            for (key, list) in g.programs {
                guard let ch = byKey[key] else { continue }
                for prog in list where prog.stop > now && prog.title.localizedStandardContains(q) {
                    out.append(ProgramHit(program: prog, channel: ch, playlist: p.id))
                }
            }
        }
        out.sort { $0.program.start < $1.program.start }
        return Array(out.prefix(limit))
    }
}

// MARK: - Lector XMLTV

final class XMLTVParser: NSObject, XMLParserDelegate {
    private let from: Date
    private let to: Date
    private(set) var programs: [String: [EPGProgram]] = [:]
    private(set) var names: [String: String] = [:]

    private var text = ""
    private var channelID: String?
    private var inProgramme = false
    private var pChannel: String?
    private var pStart: Date?
    private var pStop: Date?
    private var pTitle: String?
    private var pDesc: String?

    init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        return parser.parse()
    }

    /// Ordena por hora y ajusta los finales que faltan o se solapan.
    func finished() -> [String: [EPGProgram]] {
        var out: [String: [EPGProgram]] = [:]
        for (key, list) in programs {
            var sorted = list.sorted { $0.start < $1.start }
            for i in sorted.indices.dropLast() where sorted[i].stop > sorted[i + 1].start {
                sorted[i].stop = sorted[i + 1].start
            }
            out[key] = sorted.filter { $0.stop > $0.start }
        }
        return out
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "channel":
            channelID = attributes["id"].map(EPGStore.key)
        case "programme":
            inProgramme = true
            pChannel = attributes["channel"].map(EPGStore.key)
            pStart = Self.date(attributes["start"])
            pStop = Self.date(attributes["stop"])
            pTitle = nil
            pDesc = nil
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "display-name":
            if !inProgramme, let c = channelID, !value.isEmpty {
                let n = EPGStore.normName(value)
                if !n.isEmpty && names[n] == nil { names[n] = c }
            }
        case "channel":
            channelID = nil
        case "title":
            if inProgramme && pTitle == nil && !value.isEmpty { pTitle = value }
        case "desc":
            if inProgramme && pDesc == nil && !value.isEmpty { pDesc = value }
        case "programme":
            if let c = pChannel, let s = pStart {
                let e = pStop ?? s.addingTimeInterval(3600)
                if e > from && s < to {
                    programs[c, default: []].append(EPGProgram(channel: c, start: s, stop: e, title: pTitle ?? "Sin título", desc: pDesc))
                }
            }
            inProgramme = false
        default:
            break
        }
        text = ""
    }

    /// Formato XMLTV: "20261110213000 +0100" (la zona es opcional).
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        let c = Array(s.utf8)
        func num(_ at: Int, _ n: Int) -> Int? {
            guard at + n <= c.count else { return nil }
            var v = 0
            for i in at..<(at + n) {
                let d = c[i]
                guard d >= 48 && d <= 57 else { return nil }
                v = v * 10 + Int(d - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2) else { return nil }
        let h = num(8, 2) ?? 0
        let mi = num(10, 2) ?? 0
        let sec = num(12, 2) ?? 0
        var offset = 0
        var i = 12
        while i < c.count && c[i] != 43 && c[i] != 45 { i += 1 }   // '+' o '-'
        if i < c.count, let oh = num(i + 1, 2), let om = num(i + 3, 2) {
            offset = (oh * 3600 + om * 60) * (c[i] == 45 ? -1 : 1)
        }
        // Días desde 1970-01-01 (algoritmo civil de H. Hinnant)
        let yy = mo <= 2 ? y - 1 : y
        let era = (yy >= 0 ? yy : yy - 399) / 400
        let yoe = yy - era * 400
        let mp = (mo + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146097 + doe - 719468
        let seconds = days * 86400 + h * 3600 + mi * 60 + sec - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}

// MARK: - Descompresión de guías .gz

enum Gzip {
    static func isCompressed(_ data: Data) -> Bool {
        data.count > 18 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var pos = 10
        if flags & 0x04 != 0 {
            guard pos + 2 <= bytes.count else { return nil }
            pos += 2 + (Int(bytes[pos]) | Int(bytes[pos + 1]) << 8)
        }
        if flags & 0x08 != 0 { while pos < bytes.count && bytes[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x10 != 0 { while pos < bytes.count && bytes[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x02 != 0 { pos += 2 }
        guard pos < bytes.count - 8 else { return nil }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }

        let bufferSize = 1 << 20
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        return bytes.withUnsafeBufferPointer { src -> Data? in
            guard let base = src.baseAddress else { return nil }
            stream.pointee.src_ptr = base.advanced(by: pos)
            stream.pointee.src_size = src.count - pos - 8
            var out = Data()
            var status = COMPRESSION_STATUS_OK
            repeat {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else { return nil }
                out.append(buffer, count: bufferSize - stream.pointee.dst_size)
            } while status == COMPRESSION_STATUS_OK
            return out
        }
    }
}
