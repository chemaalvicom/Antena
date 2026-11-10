import SwiftUI

// MARK: - Teclado de PIN

struct PINEntryView: View {
    enum Mode { case unlock, create, change }

    @Environment(ParentalControl.self) private var parental
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var reason: String = ""
    let onSuccess: () -> Void

    private enum Step { case current, new, confirm }

    @State private var step: Step
    @State private var pin = ""
    @State private var firstPIN = ""
    @State private var message: String?
    @State private var isError = false
    @State private var done = false

    init(mode: Mode, reason: String = "", onSuccess: @escaping () -> Void) {
        self.mode = mode
        self.reason = reason
        self.onSuccess = onSuccess
        _step = State(initialValue: mode == .create ? .new : .current)
    }

    private var title: String {
        if done { return "Listo" }
        switch step {
        case .current: return mode == .change ? "PIN actual" : "Introduce el PIN"
        case .new: return mode == .change ? "PIN nuevo" : "Crea un PIN"
        case .confirm: return "Repite el PIN"
        }
    }

    private var subtitle: String {
        if let message { return message }
        switch step {
        case .current: return reason.isEmpty ? "Control parental" : reason
        case .new: return "4 dígitos. Lo pediremos para abrir lo protegido."
        case .confirm: return "Escríbelo otra vez para confirmar."
        }
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                TVColor.bg.ignoresSafeArea()
                Group {
                    if wide {
                        HStack(spacing: 36) { info; keypad.frame(width: 260) }
                    } else {
                        VStack(spacing: 28) { info; keypad.frame(width: 270) }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .topLeading) {
                Button("Cancelar") { dismiss() }
                    .padding(16)
                    .foregroundStyle(TVColor.text2)
            }
        }
        .foregroundStyle(TVColor.text)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: done ? "lock.open.fill" : "lock.fill")
                .font(.title2)
                .foregroundStyle(done ? AnyShapeStyle(TVColor.ok) : AnyShapeStyle(.tint))
                .frame(width: 54, height: 54)
                .background(TVColor.chip, in: Circle())
            Text(title).font(.title2.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(isError ? Color(red: 0.97, green: 0.44, blue: 0.44) : TVColor.text2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .strokeBorder(i < pin.count ? Color.clear : TVColor.text3, lineWidth: 2)
                        .background(Circle().fill(i < pin.count ? (isError ? Color.red : (done ? TVColor.ok : Color.accentColor)) : Color.clear))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.top, 4)
            .accessibilityElement()
            .accessibilityLabel("\(pin.count) de 4 dígitos")
        }
        .frame(maxWidth: 320, alignment: .leading)
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "clear", "0", "del"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(keys, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "del" { Image(systemName: "delete.left") }
                        else if k == "clear" { Text("Borrar").font(.system(size: 14, weight: .semibold)) }
                        else { Text(k).font(.system(size: 24, weight: .bold)) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(k.count == 1 ? TVColor.text : TVColor.text2)
                    .background(k.count == 1 ? TVColor.chip : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(done || parental.isLockedOut)
                .accessibilityLabel(k == "del" ? "Borrar último dígito" : (k == "clear" ? "Borrar todo" : k))
            }
        }
    }

    private func press(_ k: String) {
        if isError { pin = ""; isError = false; message = nil }
        switch k {
        case "del": if !pin.isEmpty { pin.removeLast() }
        case "clear": pin = ""
        default:
            guard pin.count < 4 else { return }
            pin += k
            if pin.count == 4 { submit() }
        }
    }

    private func submit() {
        switch step {
        case .current:
            switch parental.verify(pin) {
            case .ok:
                if mode == .change {
                    step = .new
                    pin = ""
                } else {
                    finish()
                }
            case .wrong(let remaining):
                fail("PIN incorrecto. Te quedan \(remaining) intentos.")
            case .lockedOut(let until):
                fail("Demasiados intentos. Prueba a las \(until.formatted(date: .omitted, time: .shortened)).")
            }
        case .new:
            firstPIN = pin
            pin = ""
            step = .confirm
        case .confirm:
            if pin == firstPIN {
                parental.setPIN(pin)
                finish()
            } else {
                step = .new
                fail("No coinciden. Vuelve a crear el PIN.")
            }
        }
    }

    private func fail(_ text: String) {
        message = text
        isError = true
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func finish() {
        done = true
        message = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            dismiss()
            // Espera a que se cierre la hoja antes de abrir otra pantalla (p. ej. el reproductor).
            try? await Task.sleep(for: .milliseconds(450))
            onSuccess()
        }
    }
}

// MARK: - Ajustes › Control parental

struct ParentalSettingsView: View {
    @Environment(Library.self) private var library
    @Environment(ParentalControl.self) private var parental
    @State private var sheet: SheetKind?
    @State private var filter = ""

    private enum SheetKind: Identifiable {
        case create, change, unlock, disable
        var id: Int { hashValue }
    }

    private var allGroups: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in library.playlists {
            for g in p.groups where seen.insert(g).inserted { out.append(g) }
        }
        let suggested = out.filter(ParentalControl.looksAdult)
        let rest = out.filter { !ParentalControl.looksAdult($0) }
        let all = suggested + rest
        return filter.isEmpty ? all : all.filter { $0.localizedStandardContains(filter) }
    }

    var body: some View {
        Group {
            if parental.isLocked {
                LockedPlaceholder(title: "Control parental", message: "Introduce el PIN para cambiar estos ajustes.") {
                    sheet = .unlock
                }
            } else {
                form
            }
        }
        .navigationTitle("Control parental")
        .sheet(item: $sheet) { kind in
            switch kind {
            case .create:
                PINEntryView(mode: .create) {
                    parental.enabled = true
                    for g in allGroups where ParentalControl.looksAdult(g) { parental.setGroup(g, protected: true) }
                    parental.save()
                }
            case .change:
                PINEntryView(mode: .change) {}
            case .unlock:
                PINEntryView(mode: .unlock, reason: "Ajustes de control parental") {}
            case .disable:
                PINEntryView(mode: .unlock, reason: "Desactivar el control parental") { parental.disable() }
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("Activar control parental", isOn: Binding(
                    get: { parental.enabled },
                    set: { on in
                        if on {
                            if parental.hasPIN { parental.enabled = true; parental.save() } else { sheet = .create }
                        } else {
                            sheet = .disable
                        }
                    }))
            } footer: {
                Text("Pide un PIN de 4 dígitos para abrir los grupos y canales que elijas. El PIN se guarda cifrado en este iPhone.")
            }

            if parental.enabled {
                Section {
                    Toggle(isOn: binding(\.hideProtected)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ocultar lo protegido")
                            Text("No aparece en listas ni búsquedas hasta poner el PIN.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: binding(\.protectSettings)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Proteger los ajustes")
                            Text("Pide el PIN para entrar en Ajustes y cambiar listas.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: binding(\.relockOnExit)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Volver a bloquear al salir")
                            Text("Al cerrar la app o tras 30 minutos sin uso.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Cambiar PIN") { sheet = .change }
                    if parental.unlocked {
                        Button("Bloquear ahora") { parental.lock() }
                    }
                }

                Section {
                    TextField("Filtrar grupos", text: $filter)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if allGroups.isEmpty {
                        Text("Añade una lista para elegir grupos.").foregroundStyle(.secondary)
                    }
                    ForEach(allGroups, id: \.self) { g in
                        Toggle(isOn: Binding(
                            get: { parental.protectedGroups.contains(g) },
                            set: { parental.setGroup(g, protected: $0) })) {
                            HStack {
                                Text(g).lineLimit(1)
                                if ParentalControl.looksAdult(g) {
                                    Text("Sugerido").font(.caption2.bold()).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Grupos protegidos (\(parental.protectedGroups.count))")
                }

                if !parental.protectedChannels.isEmpty {
                    Section {
                        ForEach(parental.protectedChannels.sorted(), id: \.self) { url in
                            let name = library.playlists.lazy.flatMap(\.channels).first { $0.url == url }?.name ?? url
                            Text(name).lineLimit(1)
                                .swipeActions {
                                    Button("Quitar", role: .destructive) { parental.removeProtectedChannel(url: url) }
                                }
                        }
                    } header: {
                        Text("Canales protegidos sueltos")
                    } footer: {
                        Text("Para proteger un canal, mantenlo pulsado en Directo y elige «Proteger con PIN».")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(TVColor.bg)
    }

    private func binding(_ key: ReferenceWritableKeyPath<ParentalControl, Bool>) -> Binding<Bool> {
        Binding(get: { parental[keyPath: key] }, set: { parental[keyPath: key] = $0; parental.save() })
    }
}

// MARK: - Ajustes › Guía de programación

struct EPGSettingsView: View {
    @Environment(Library.self) private var library
    @Environment(EPGStore.self) private var epg
    @AppStorage("userAgent") private var userAgent = Defaults.userAgent

    var body: some View {
        Form {
            ForEach(library.playlists) { p in
                Section(p.name) {
                    TextField("Dirección XMLTV (.xml o .xml.gz)", text: Binding(
                        get: { p.epgURL ?? "" },
                        set: { library.setEPG(p.id, url: $0) }))
                        .font(.footnote.monospaced())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if epg.loading.contains(p.id) {
                        HStack { ProgressView(); Text("Descargando…").foregroundStyle(.secondary) }
                    } else if let g = epg.guides[p.id] {
                        LabeledContent("Programas", value: "\(g.programCount)")
                        LabeledContent("Actualizada", value: g.fetchedAt.formatted(.relative(presentation: .named)))
                    }
                    if let e = epg.errors[p.id] {
                        Text(e).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            Section {
                Button("Actualizar la guía ahora") {
                    Task { await epg.refreshIfNeeded(library.playlists, userAgent: userAgent, force: true) }
                }
                .disabled(!epg.loading.isEmpty)
            } footer: {
                Text("La guía se detecta sola en listas Xtream y en las que traen url-tvg. Se actualiza cada 12 horas.")
            }
        }
        .navigationTitle("Guía de programación")
    }
}
