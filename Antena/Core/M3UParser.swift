import Foundation

/// Lector de listas M3U / M3U8 (formato IPTV extendido).
/// Entiende: #EXTINF con tvg-id / tvg-name / tvg-logo / group-title, #EXTGRP,
/// #EXTVLCOPT (user-agent y referrer) y la sintaxis estilo Kodi `url|User-Agent=...`.
enum M3UParser {
    private static let attrRegex = try! NSRegularExpression(pattern: #"([A-Za-z0-9_\-]+)\s*=\s*"([^"]*)""#)

    static func parse(_ raw: String) -> [Channel] {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)

        var channels: [Channel] = []
        var title: String?
        var attrs: [String: String] = [:]
        var extGroup: String?
        var ua: String?
        var ref: String?

        for sub in lines {
            let line = sub.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.uppercased().hasPrefix("#EXTINF") {
                let info = parseInfo(line)
                attrs = info.attrs
                title = info.title
            } else if line.uppercased().hasPrefix("#EXTGRP:") {
                extGroup = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if line.uppercased().hasPrefix("#EXTVLCOPT:") {
                let opt = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if let v = value(of: opt, key: "http-user-agent=") { ua = v }
                if let v = value(of: opt, key: "http-referrer=") ?? value(of: opt, key: "http-referer=") { ref = v }
            } else if line.hasPrefix("#") {
                continue
            } else {
                var urlString = line
                if let pipe = line.firstIndex(of: "|") {
                    urlString = String(line[..<pipe])
                    let extras = line[line.index(after: pipe)...]
                    for pair in extras.split(separator: "&") {
                        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                        guard kv.count == 2 else { continue }
                        let v = kv[1].removingPercentEncoding ?? kv[1]
                        switch kv[0].lowercased() {
                        case "user-agent": ua = v
                        case "referer", "referrer": ref = v
                        default: break
                        }
                    }
                }

                let name = [title, attrs["tvg-name"]].compactMap { $0 }.first { !$0.isEmpty } ?? urlString
                let group = [attrs["group-title"], extGroup].compactMap { $0 }.first { !$0.isEmpty } ?? "Sin grupo"
                let logo = attrs["tvg-logo"].flatMap { $0.isEmpty ? nil : $0 }

                channels.append(Channel(
                    id: "\(channels.count)|\(urlString)",
                    name: name,
                    url: urlString,
                    logo: logo,
                    group: group,
                    tvgID: attrs["tvg-id"],
                    userAgent: ua,
                    referrer: ref
                ))
                title = nil; attrs = [:]; extGroup = nil; ua = nil; ref = nil
            }
        }
        return channels
    }

    /// Separa los atributos y el nombre visible: el nombre va tras la primera coma fuera de comillas.
    private static func parseInfo(_ line: String) -> (attrs: [String: String], title: String) {
        var inQuotes = false
        var header = line
        var title = ""
        for i in line.indices {
            let ch = line[i]
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                header = String(line[..<i])
                title = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        var out: [String: String] = [:]
        let ns = header as NSString
        for m in attrRegex.matches(in: header, range: NSRange(location: 0, length: ns.length)) {
            out[ns.substring(with: m.range(at: 1)).lowercased()] = ns.substring(with: m.range(at: 2))
        }
        return (out, title)
    }

    private static func value(of option: String, key: String) -> String? {
        option.lowercased().hasPrefix(key) ? String(option.dropFirst(key.count)) : nil
    }
}
