import SwiftUI

// MARK: - Guía de programación (rejilla)

struct GuideTV: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    @Environment(\.verticalSizeClass) private var vSize

    private var landscape: Bool { vSize == .compact }
    private var windowMinutes: Double { landscape ? 150 : 90 }
    private var channelColumn: CGFloat { landscape ? 160 : 118 }

    var body: some View {
        let playlist = tv.playlist(in: library)
        let channels = tv.channels(tv.group, playlist: playlist, library: library, parental: parental)
        if library.playlists.isEmpty {
            EmptyLibraryView()
        } else {
            VStack(spacing: 0) {
                DetailHeader(selection: currentSelection(channels: channels, playlist: playlist), playlist: playlist, landscape: landscape)
                toolbar(playlist: playlist)
                if playlist.flatMap({ epg.guides[$0.id] }) == nil {
                    noGuide(playlist: playlist)
                } else {
                    grid(channels: channels, playlist: playlist)
                }
            }
        }
    }

    private func currentSelection(channels: [Channel], playlist: Playlist?) -> GuideSelection? {
        if let s = tv.guideSelection { return s }
        guard let ch = channels.first else { return nil }
        return GuideSelection(channel: ch, program: epg.current(for: ch, playlist: playlist?.id))
    }

    // MARK: Barra: grupo y desplazamiento en el tiempo

    private func toolbar(playlist: Playlist?) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(groupEntries(playlist: playlist, library: library, parental: parental)) { e in
                    Button { tv.choose(e.filter, parental: parental) } label: {
                        if tv.group == e.filter { Label(e.filter.title, systemImage: "checkmark") }
                        else if e.locked { Label(e.filter.title, systemImage: "lock.fill") }
                        else { Text(e.filter.title) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(tv.group.title).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(TVColor.chip, in: Capsule())
            }
            Spacer()
            Text(tv.guideStart.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TVColor.text2)
            timeButton("chevron.left", "Antes") { tv.guideStart = tv.guideStart.addingTimeInterval(-3600) }
            Button { tv.guideStart = TVState.halfHour(epg.now) } label: {
                Text("Ahora").font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).frame(height: 32)
                    .foregroundStyle(TVColor.rail)
                    .background(.tint, in: Capsule())
            }
            .buttonStyle(.plain)
            timeButton("chevron.right", "Después") { tv.guideStart = tv.guideStart.addingTimeInterval(3600) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func timeButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
                .frame(width: 36, height: 32)
                .background(TVColor.chip, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Rejilla

    private func grid(channels: [Channel], playlist: Playlist?) -> some View {
        GeometryReader { geo in
            let width = max(100, geo.size.width - channelColumn)
            let ppm = width / windowMinutes
            let start = tv.guideStart
            let end = start.addingTimeInterval(windowMinutes * 60)
            VStack(spacing: 0) {
                ruler(start: start, ppm: ppm)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(channels) { ch in
                            GuideRow(channel: ch, playlist: playlist, start: start, end: end, ppm: ppm,
                                     channelColumn: channelColumn, width: width)
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                let x = epg.now.timeIntervalSince(start) / 60 * ppm
                if x >= 0 && x <= width {
                    ZStack(alignment: .top) {
                        Rectangle().fill(.tint).frame(width: 2)
                        Circle().fill(.tint).frame(width: 9, height: 9).offset(y: 6)
                    }
                    .offset(x: channelColumn + x - 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    private func ruler(start: Date, ppm: Double) -> some View {
        HStack(spacing: 0) {
            Text(start.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tint)
                .padding(.leading, 12)
                .frame(width: channelColumn, alignment: .leading)
            ZStack(alignment: .leading) {
                ForEach(0..<Int(windowMinutes / 30), id: \.self) { i in
                    Text(start.addingTimeInterval(Double(i) * 1800).formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TVColor.text2)
                        .offset(x: Double(i) * 30 * ppm + 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 26)
        .overlay(alignment: .bottom) { TVColor.line.frame(height: 1) }
    }

    private func noGuide(playlist: Playlist?) -> some View {
        VStack(spacing: 10) {
            if let p = playlist, epg.loading.contains(p.id) {
                ProgressView("Descargando la guía…").tint(.white)
            } else {
                ContentUnavailableView {
                    Label("Sin guía de programación", systemImage: "tablecells")
                } description: {
                    Text(playlist.flatMap { epg.errors[$0.id] } ?? "Esta lista no indica su guía (XMLTV). Puedes añadir la dirección en Ajustes › Guía de programación.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GuideRow: View {
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    let channel: Channel
    let playlist: Playlist?
    let start: Date
    let end: Date
    let ppm: Double
    let channelColumn: CGFloat
    let width: CGFloat

    var body: some View {
        let locked = parental.needsPIN(channel)
        let programs = locked ? [] : epg.programs(for: channel, playlist: playlist?.id, from: start, to: end)
        HStack(spacing: 0) {
            Button { tv.play(channel, parental: parental) } label: {
                HStack(spacing: 8) {
                    Text(tv.number(of: channel, in: playlist).map(String.init) ?? "")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(TVColor.text3)
                        .frame(width: 26, alignment: .trailing)
                    TVLogo(channel: channel, locked: locked, corner: 5).frame(width: 36, height: 22)
                    Text(channel.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 6)
                .frame(width: channelColumn, height: 52)
                .background(TVColor.panel)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { ChannelActions(channel: channel) }

            ZStack(alignment: .leading) {
                if programs.isEmpty {
                    block(title: locked ? "Protegido" : "Sin información", subtitle: nil, x: 0, w: width, live: false, past: false, selected: false) {
                        tv.guideSelection = GuideSelection(channel: channel, program: nil)
                    }
                } else {
                    ForEach(programs) { p in
                        let s = max(p.start, start)
                        let e = min(p.stop, end)
                        let x = s.timeIntervalSince(start) / 60 * ppm
                        let w = e.timeIntervalSince(s) / 60 * ppm
                        block(title: p.title, subtitle: p.timeRange, x: x, w: w,
                              live: p.isLive(at: epg.now), past: p.stop <= epg.now,
                              selected: tv.guideSelection?.program?.id == p.id) {
                            tv.guideSelection = GuideSelection(channel: channel, program: p)
                        }
                    }
                }
            }
            .frame(width: width, height: 52, alignment: .leading)
            .clipped()
        }
        .overlay(alignment: .bottom) { TVColor.bg.frame(height: 1) }
    }

    private func block(title: String, subtitle: String?, x: Double, w: Double, live: Bool, past: Bool,
                       selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let subtitle, w > 70 {
                    Text(subtitle).font(.system(size: 10)).opacity(0.7).lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: max(8, w - 3), height: 44, alignment: .leading)
            .foregroundStyle(past ? TVColor.text3 : TVColor.text)
            .background(selected ? Color.orange.opacity(0.16) : (live ? TVColor.selected : (past ? TVColor.panel : TVColor.chip.opacity(0.55))),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.tint, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: x + 1.5)
    }
}

// MARK: - Detalle del programa elegido

private struct DetailHeader: View {
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    let selection: GuideSelection?
    let playlist: Playlist?
    let landscape: Bool
    @State private var reminderSet = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let s = selection {
                TVLogo(channel: s.channel, locked: parental.needsPIN(s.channel), corner: 8)
                    .frame(width: landscape ? 120 : 84, height: landscape ? 68 : 48)
                    .overlay(alignment: .topLeading) {
                        if s.program?.isLive(at: epg.now) == true { LiveBadge().scaleEffect(0.85).padding(3) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(s))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                    Text(s.program?.title ?? "Sin información de la guía")
                        .font(.system(size: landscape ? 16 : 15, weight: .heavy))
                        .lineLimit(1)
                    if let d = s.program?.desc {
                        Text(d).font(.system(size: 11)).foregroundStyle(TVColor.text2).lineLimit(landscape ? 2 : 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 6) {
                    Button { tv.play(s.channel, parental: parental) } label: {
                        Label(s.program?.isLive(at: epg.now) == false ? "Ver canal" : "Ver ahora", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .foregroundStyle(TVColor.rail)
                            .background(.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    if let p = s.program, p.start > epg.now {
                        Button {
                            Task {
                                if reminderSet { Reminders.cancel(p); reminderSet = false }
                                else { reminderSet = await Reminders.schedule(p, channel: s.channel) }
                            }
                        } label: {
                            Label(reminderSet ? "Recordado" : "Recordar", systemImage: reminderSet ? "bell.fill" : "bell")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(TVColor.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("Elige un programa en la guía").font(.subheadline).foregroundStyle(TVColor.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(minHeight: landscape ? 92 : 76)
        .background(TVColor.panel)
        .onChange(of: selection?.program?.id, initial: true) { _, _ in
            reminderSet = selection?.program.map(Reminders.isSet) ?? false
        }
    }

    private func headline(_ s: GuideSelection) -> String {
        var parts: [String] = []
        if let n = tv.number(of: s.channel, in: playlist) { parts.append(String(n)) }
        parts.append(s.channel.name)
        if let p = s.program { parts.append(p.timeRange) }
        return parts.joined(separator: " · ")
    }
}