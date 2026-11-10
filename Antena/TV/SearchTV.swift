import SwiftUI

// MARK: - Búsqueda en canales y en la guía

struct SearchTV: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    @Environment(\.verticalSizeClass) private var vSize
    @AppStorage("recentSearches") private var recentRaw = ""
    @State private var query = ""
    @State private var scope = Scope.all
    @FocusState private var focused: Bool

    enum Scope: String, CaseIterable, Identifiable {
        case all = "Todo", channels = "Canales", programs = "Programas"
        var id: String { rawValue }
    }

    private var recent: [String] {
        recentRaw.split(separator: "\n").map(String.init)
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let channelHits = q.count >= 2 ? channels(matching: q) : []
        let programHits = q.count >= 2 ? epg.search(q, in: library.playlists).filter { !parental.needsPIN($0.channel) } : []
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(TVColor.text2)
                    TextField("Canal o programa", text: $query)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { remember(q) }
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(TVColor.text3) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Borrar búsqueda")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(TVColor.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(TVColor.line), lineWidth: 2))

                Picker("Buscar en", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: vSize == .compact ? 260 : 190)
            }

            if q.count < 2 {
                if !recent.isEmpty {
                    HStack(spacing: 6) {
                        Text("Recientes:").font(.system(size: 11)).foregroundStyle(TVColor.text3)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(recent, id: \.self) { r in
                                    Button { query = r } label: {
                                        Text(r).font(.system(size: 12))
                                            .padding(.horizontal, 10).frame(height: 28)
                                            .overlay(Capsule().strokeBorder(TVColor.line))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button("Borrar") { recentRaw = "" }.font(.system(size: 11)).foregroundStyle(TVColor.text3)
                    }
                }
                ContentUnavailableView("Busca un canal o un programa", systemImage: "magnifyingglass",
                                       description: Text("Escribe al menos dos letras. Se busca en todas tus listas y en la guía de las próximas horas."))
                    .frame(maxHeight: .infinity)
            } else {
                let showCh = scope != .programs
                let showPr = scope != .channels
                if vSize == .compact && showCh && showPr {
                    HStack(alignment: .top, spacing: 14) {
                        channelSection(channelHits, q: q)
                        programSection(programHits, q: q)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if showCh { channelSection(channelHits, q: q, scrolls: false) }
                            if showPr { programSection(programHits, q: q, scrolls: false) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onAppear { if query.isEmpty { focused = true } }
    }

    // MARK: Resultados

    private func channels(matching q: String) -> [ChannelHit] {
        var out: [ChannelHit] = []
        var seen = Set<String>()
        for p in library.playlists {
            for ch in p.channels where !parental.isHidden(ch) && ch.name.localizedStandardContains(q) {
                if seen.insert(ch.url).inserted { out.append(ChannelHit(channel: ch, playlist: p.id)) }
                if out.count >= 80 { return out }
            }
        }
        return out
    }

    @ViewBuilder
    private func channelSection(_ hits: [ChannelHit], q: String, scrolls: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Canales · \(hits.count)")
            if hits.isEmpty {
                Text("Ningún canal coincide.").font(.system(size: 12)).foregroundStyle(TVColor.text3)
            } else {
                wrap(scrolls) {
                    ForEach(hits) { hit in
                        let ch = hit.channel
                        let pid = hit.playlist
                        let locked = parental.needsPIN(ch)
                        let now = locked ? nil : epg.current(for: ch, playlist: pid)
                        Button { remember(q); tv.play(ch, parental: parental) } label: {
                            row(leading: AnyView(TVLogo(channel: ch, locked: locked).frame(width: 46, height: 28)),
                                title: ch.name,
                                subtitle: now.map { "Ahora: \($0.title)" } ?? ch.group,
                                trailing: "play.fill")
                        }
                        .buttonStyle(.plain)
                        .contextMenu { ChannelActions(channel: ch) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func programSection(_ hits: [ProgramHit], q: String, scrolls: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("En la guía · \(hits.count)")
            if hits.isEmpty {
                Text(epg.guides.isEmpty ? "No hay guía descargada." : "Ningún programa coincide.")
                    .font(.system(size: 12)).foregroundStyle(TVColor.text3)
            } else {
                wrap(scrolls) {
                    ForEach(hits) { hit in
                        let live = hit.program.isLive(at: epg.now)
                        Button {
                            remember(q)
                            if live {
                                tv.play(hit.channel, parental: parental)
                            } else {
                                tv.playlistID = hit.playlist
                                tv.group = .group(hit.channel.group)
                                tv.guideStart = TVState.halfHour(hit.program.start.addingTimeInterval(-1800))
                                tv.guideSelection = GuideSelection(channel: hit.channel, program: hit.program)
                                tv.section = .guide
                            }
                        } label: {
                            row(leading: AnyView(badge(hit.program, live: live)),
                                title: hit.program.title,
                                subtitle: "\(hit.channel.name) · \(when(hit.program))",
                                trailing: live ? "play.fill" : "tablecells")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func wrap<Content: View>(_ scrolls: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        if scrolls {
            ScrollView { LazyVStack(spacing: 6) { content() } }
        } else {
            LazyVStack(spacing: 6) { content() }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(TVColor.text3)
    }

    private func row(leading: AnyView, title: String, subtitle: String, trailing: String) -> some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(TVColor.text2).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: trailing).font(.system(size: 12)).foregroundStyle(.tint)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(TVColor.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    private func badge(_ p: EPGProgram, live: Bool) -> some View {
        Text(live ? "AHORA" : p.start.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(live ? .white : TVColor.text)
            .frame(width: 52, height: 24)
            .background(live ? TVColor.live : TVColor.chip, in: RoundedRectangle(cornerRadius: 6))
    }

    private func when(_ p: EPGProgram) -> String {
        if p.isLive(at: epg.now) { return "hasta \(p.stop.formatted(date: .omitted, time: .shortened))" }
        let cal = Calendar.current
        let time = p.start.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(p.start) { return "hoy \(time)" }
        if cal.isDateInTomorrow(p.start) { return "mañana \(time)" }
        return p.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func remember(_ q: String) {
        guard q.count >= 2 else { return }
        var list = recent.filter { $0.caseInsensitiveCompare(q) != .orderedSame }
        list.insert(q, at: 0)
        recentRaw = list.prefix(8).joined(separator: "\n")
    }
}
