import SwiftUI

// MARK: - Favoritos con varias listas

struct FavoritesTV: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @Environment(ParentalControl.self) private var parental
    @Environment(TVState.self) private var tv
    @State private var listID: UUID?
    @State private var editing = false
    @State private var naming = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        let items = library.favorites(in: listID).filter { !parental.isHidden($0) }
        VStack(alignment: .leading, spacing: 10) {
            header(count: items.count)
            tabs
            if items.isEmpty {
                ContentUnavailableView(
                    listID == nil ? "Sin favoritos" : "Lista vacía",
                    systemImage: "star",
                    description: Text(listID == nil
                        ? "Pulsa la estrella de un canal en Directo, o mantenlo pulsado y elige «Añadir a favoritos»."
                        : "Mantén pulsado un canal en Directo y elige «Listas de favoritos».")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, ch in
                            tile(ch, position: i + 1, isFirst: i == 0, isLast: i == items.count - 1)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: library.favoriteLists.map(\.id)) { _, ids in
            if let l = listID, !ids.contains(l) { listID = nil }
        }
        .alert("Nueva lista de favoritos", isPresented: $naming) {
            TextField("Nombre, p. ej. Fútbol", text: $newName)
            Button("Crear") { listID = library.addFavoriteList(name: newName) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Renombrar lista", isPresented: $renaming) {
            TextField("Nombre", text: $newName)
            Button("Guardar") { if let l = listID { library.renameFavoriteList(l, to: newName) } }
            Button("Cancelar", role: .cancel) {}
        }
        .confirmationDialog("¿Eliminar esta lista? Los canales seguirán en favoritos.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar lista", role: .destructive) {
                if let l = listID { library.deleteFavoriteList(l); listID = nil }
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 10) {
            (Text("Favoritos").font(.system(size: 22, weight: .heavy))
             + Text("  ·  \(count) canales").font(.system(size: 14, weight: .semibold)).foregroundColor(TVColor.text2))
                .lineLimit(1)
            Spacer()
            if listID != nil {
                Menu {
                    Button { newName = library.favoriteLists.first(where: { $0.id == listID })?.name ?? ""; renaming = true } label: {
                        Label("Renombrar lista", systemImage: "pencil")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Eliminar lista", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 34)
                        .background(TVColor.chip, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .accessibilityLabel("Opciones de la lista")
            }
            Button { withAnimation { editing.toggle() } } label: {
                Label(editing ? "Hecho" : "Ordenar", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .foregroundStyle(editing ? TVColor.rail : TVColor.text)
                    .background(editing ? AnyShapeStyle(.tint) : AnyShapeStyle(TVColor.chip),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tab("Todos", id: nil)
                ForEach(library.favoriteLists) { l in tab(l.name, id: l.id) }
                Button { newName = ""; naming = true } label: {
                    Label("Nueva lista", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .foregroundStyle(TVColor.text2)
                        .overlay(Capsule().strokeBorder(TVColor.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tab(_ title: String, id: UUID?) -> some View {
        let selected = listID == id
        return Button { listID = id } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(selected ? TVColor.text : TVColor.text2)
                .background(selected ? TVColor.chip : TVColor.panel, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tile(_ ch: Channel, position: Int, isFirst: Bool, isLast: Bool) -> some View {
        let locked = parental.needsPIN(ch)
        let program = locked ? nil : epg.current(for: ch, playlist: tv.playlistID ?? library.playlists.first?.id)
        return VStack(alignment: .leading, spacing: 5) {
            Button { if !editing { tv.play(ch, parental: parental) } } label: {
                TVLogo(channel: ch, locked: locked, corner: 10)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        Text("\(position)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(6)
                    }
                    .overlay(alignment: .topTrailing) {
                        if editing {
                            HStack(spacing: 4) {
                                editButton("chevron.left", "Mover antes", disabled: isFirst) {
                                    library.moveFavorite(ch, by: -1, in: listID)
                                }
                                editButton("chevron.right", "Mover después", disabled: isLast) {
                                    library.moveFavorite(ch, by: 1, in: listID)
                                }
                                editButton("xmark", listID == nil ? "Quitar de favoritos" : "Quitar de la lista", destructive: true) {
                                    library.removeFavorite(ch, from: listID)
                                }
                            }
                            .padding(4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .contextMenu { ChannelActions(channel: ch) }
            Text(ch.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(program?.title ?? ch.group).font(.system(size: 11)).foregroundStyle(TVColor.text2).lineLimit(1)
            if let program { TVProgress(value: program.progress(at: epg.now)) }
        }
    }

    private func editButton(_ icon: String, _ label: String, disabled: Bool = false, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(destructive ? TVColor.live : TVColor.bg, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}
