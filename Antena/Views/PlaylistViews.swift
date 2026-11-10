import SwiftUI
import UniformTypeIdentifiers

// MARK: - Listas

/// Gestión de listas (añadir, actualizar, renombrar, ordenar y borrar). Se abre como hoja.
struct PlaylistsManagerView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent

    @State private var showAdd = false
    @State private var showClipboard = false
    @State private var showImporter = false
    @State private var refreshing: UUID?
    @State private var renaming: Playlist?
    @State private var newName = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if library.playlists.isEmpty {
                    ContentUnavailableView {
                        Label("Sin listas", systemImage: "antenna.radiowaves.left.and.right")
                    } description: {
                        Text("Añade una lista M3U por URL, con tu cuenta Xtream o importando un archivo.")
                    } actions: {
                        Button("Añadir lista") { showAdd = true }
                            .buttonStyle(.borderedProminent)
                        Button("Pegar varias desde el portapapeles") { showClipboard = true }
                        Button("Importar archivo") { showImporter = true }
                    }
                } else {
                    List {
                        ForEach(library.playlists) { p in
                            PlaylistRow(playlist: p, isRefreshing: refreshing == p.id)
                            .swipeActions(edge: .leading) {
                                if p.sourceURL != nil {
                                    Button { refresh(p) } label: {
                                        Label("Actualizar", systemImage: "arrow.clockwise")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .contextMenu {
                                if p.sourceURL != nil {
                                    Button { refresh(p) } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
                                }
                                Button { newName = p.name; renaming = p } label: { Label("Renombrar", systemImage: "pencil") }
                            }
                        }
                        .onDelete { library.deletePlaylists(at: $0) }
                        .onMove { library.movePlaylists(from: $0, to: $1) }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VPNBanner()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .background(.bar)
            }
            .navigationTitle("Listas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                if !library.playlists.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAdd = true } label: { Label("Desde URL o Xtream", systemImage: "link") }
                        Button { showClipboard = true } label: { Label("Varias desde el portapapeles", systemImage: "doc.on.clipboard") }
                        Button { showImporter = true } label: { Label("Importar archivo", systemImage: "doc") }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddPlaylistView() }
            .sheet(isPresented: $showClipboard) { ClipboardImportView() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.m3uPlaylist, .plainText, .data]) { result in
                switch result {
                case .success(let url):
                    do { try library.importFile(url) } catch { errorText = error.localizedDescription }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .alert("Renombrar lista", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nombre", text: $newName)
                Button("Guardar") { if let r = renaming { library.rename(r.id, to: newName) } }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Error", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    private func refresh(_ p: Playlist) {
        Task {
            refreshing = p.id
            do { try await library.refresh(p.id, userAgent: userAgent) } catch { errorText = error.localizedDescription }
            refreshing = nil
        }
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: playlist.sourceURL == nil ? "doc.text" : "network")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name).font(.headline)
                Text("\(playlist.channels.count) canales · \(playlist.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRefreshing { ProgressView() }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Añadir lista

struct AddPlaylistView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent

    enum Mode: String, CaseIterable, Identifiable {
        case url = "URL M3U"
        case xtream = "Xtream Codes"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .url
    @State private var name = ""
    @State private var url = ""
    @State private var server = ""
    @State private var user = ""
    @State private var password = ""
    @State private var xtreamHLS = false
    @State private var loading = false
    @State private var errorText: String?

    private var finalURL: String {
        mode == .url ? url : Library.xtreamURL(server: server, user: user, password: password, hls: xtreamHLS)
    }

    private var canSave: Bool {
        mode == .url ? !url.isEmpty : !(server.isEmpty || user.isEmpty || password.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section("Nombre") {
                    TextField("Ej.: Mi IPTV", text: $name)
                }

                if mode == .url {
                    Section {
                        TextField("https://…/lista.m3u", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Dirección")
                    } footer: {
                        Text("Se descarga ahora y podrás actualizarla deslizando la lista hacia la derecha.")
                    }
                } else {
                    Section("Cuenta") {
                        TextField("Servidor (http://servidor:puerto)", text: $server)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Usuario", text: $user)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Contraseña", text: $password)
                        Toggle("Flujos HLS (.m3u8)", isOn: $xtreamHLS)
                    }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Añadir lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if loading {
                        ProgressView()
                    } else {
                        Button("Añadir") { save() }.disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(loading)
        }
    }

    private func save() {
        loading = true
        errorText = nil
        Task {
            do {
                try await library.addRemote(name: name, urlString: finalURL, userAgent: userAgent)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            loading = false
        }
    }
}
