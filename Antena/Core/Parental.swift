import Foundation
import Observation
import CryptoKit
import Security

/// Control parental: PIN de 4 dígitos (guardado cifrado en el Keychain), grupos y canales
/// protegidos, bloqueo tras 5 fallos y nuevo bloqueo al salir de la app.
@MainActor
@Observable
final class ParentalControl {
    enum VerifyResult: Equatable {
        case ok
        case wrong(remaining: Int)
        case lockedOut(until: Date)
    }

    static let maxFailures = 5
    static let lockoutSeconds: TimeInterval = 5 * 60
    static let idleRelock: TimeInterval = 30 * 60

    var enabled: Bool
    var hideProtected: Bool
    var protectSettings: Bool
    var relockOnExit: Bool
    private(set) var protectedGroups: Set<String>
    private(set) var protectedChannels: Set<String>
    private(set) var hasPIN: Bool
    private(set) var unlocked = false
    private(set) var failures: Int
    private(set) var lockedUntil: Date?

    @ObservationIgnored private var lastActivity = Date()
    private let defaults = UserDefaults.standard

    private enum K {
        static let enabled = "parental.enabled"
        static let hide = "parental.hide"
        static let settings = "parental.settings"
        static let relock = "parental.relock"
        static let groups = "parental.groups"
        static let channels = "parental.channels"
        static let failures = "parental.failures"
        static let lockedUntil = "parental.lockedUntil"
        static let service = "com.chemablanco.antenapro.parental"
        static let account = "pin"
    }

    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: K.enabled)
        hideProtected = d.bool(forKey: K.hide)
        protectSettings = d.object(forKey: K.settings) as? Bool ?? true
        relockOnExit = d.object(forKey: K.relock) as? Bool ?? true
        protectedGroups = Set(d.stringArray(forKey: K.groups) ?? [])
        protectedChannels = Set(d.stringArray(forKey: K.channels) ?? [])
        failures = d.integer(forKey: K.failures)
        let until = d.double(forKey: K.lockedUntil)
        lockedUntil = until > 0 ? Date(timeIntervalSince1970: until) : nil
        hasPIN = Self.readPIN() != nil
        if enabled && !hasPIN { enabled = false }
    }

    func save() {
        defaults.set(enabled, forKey: K.enabled)
        defaults.set(hideProtected, forKey: K.hide)
        defaults.set(protectSettings, forKey: K.settings)
        defaults.set(relockOnExit, forKey: K.relock)
        defaults.set(Array(protectedGroups).sorted(), forKey: K.groups)
        defaults.set(Array(protectedChannels).sorted(), forKey: K.channels)
        defaults.set(failures, forKey: K.failures)
        defaults.set(lockedUntil?.timeIntervalSince1970 ?? 0, forKey: K.lockedUntil)
    }

    // MARK: Estado

    /// true cuando hay que pedir PIN (control activo, con PIN y sin desbloquear).
    var isLocked: Bool {
        enabled && hasPIN && !unlocked
    }

    var isLockedOut: Bool {
        if let lockedUntil, lockedUntil > Date() { return true }
        return false
    }

    func isGroupProtected(_ group: String) -> Bool {
        enabled && hasPIN && protectedGroups.contains(group)
    }

    func isProtected(_ ch: Channel) -> Bool {
        enabled && hasPIN && (protectedGroups.contains(ch.group) || protectedChannels.contains(ch.url))
    }

    /// Hay que pedir el PIN antes de mostrar o reproducir este canal.
    func needsPIN(_ ch: Channel) -> Bool { isProtected(ch) && !unlocked }

    /// Se oculta por completo (opción "Ocultar lo protegido").
    func isHidden(_ ch: Channel) -> Bool { hideProtected && needsPIN(ch) }

    func isGroupHidden(_ group: String) -> Bool { hideProtected && isGroupProtected(group) && !unlocked }

    func setGroup(_ group: String, protected on: Bool) {
        if on { protectedGroups.insert(group) } else { protectedGroups.remove(group) }
        save()
    }

    func setChannel(_ ch: Channel, protected on: Bool) {
        if on { protectedChannels.insert(ch.url) } else { protectedChannels.remove(ch.url) }
        save()
    }

    func removeProtectedChannel(url: String) {
        protectedChannels.remove(url)
        save()
    }

    /// Grupos que parecen de adultos, para sugerirlos al activar el control.
    static func looksAdult(_ group: String) -> Bool {
        let g = group.lowercased()
        return ["adult", "xxx", "+18", "18+", "porn", "erotic", "erótic", "for adults", "hot"].contains { g.contains($0) }
    }

    // MARK: PIN

    func verify(_ pin: String) -> VerifyResult {
        if let lockedUntil, lockedUntil > Date() { return .lockedOut(until: lockedUntil) }
        guard let stored = Self.readPIN(), Self.matches(pin, stored) else {
            failures += 1
            if failures >= Self.maxFailures {
                failures = 0
                let until = Date().addingTimeInterval(Self.lockoutSeconds)
                lockedUntil = until
                save()
                return .lockedOut(until: until)
            }
            save()
            return .wrong(remaining: Self.maxFailures - failures)
        }
        failures = 0
        lockedUntil = nil
        unlocked = true
        lastActivity = Date()
        save()
        return .ok
    }

    /// Crea o cambia el PIN (deja la app desbloqueada).
    func setPIN(_ pin: String) {
        Self.writePIN(pin)
        hasPIN = true
        unlocked = true
        lastActivity = Date()
        failures = 0
        lockedUntil = nil
        save()
    }

    /// Desactiva el control y borra el PIN.
    func disable() {
        Self.deletePIN()
        hasPIN = false
        enabled = false
        unlocked = false
        save()
    }

    func lock() { unlocked = false }

    func touch() { lastActivity = Date() }

    /// Al pasar a segundo plano o tras 30 min sin uso.
    func appBackgrounded() {
        if relockOnExit { lock() }
    }

    func checkIdle() {
        if unlocked && relockOnExit && Date().timeIntervalSince(lastActivity) > Self.idleRelock { lock() }
    }

    // MARK: Keychain (sal + SHA-256)

    private static func hash(_ pin: String, salt: Data) -> String {
        var data = salt
        data.append(Data(pin.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func matches(_ pin: String, _ stored: String) -> Bool {
        let parts = stored.split(separator: ":")
        guard parts.count == 2, let salt = Data(base64Encoded: String(parts[0])) else { return false }
        return hash(pin, salt: salt) == parts[1]
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: K.service,
         kSecAttrAccount as String: K.account]
    }

    private static func readPIN() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private static func writePIN(_ pin: String) {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let value = "\(salt.base64EncodedString()):\(hash(pin, salt: salt))"
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func deletePIN() {
        SecItemDelete(query as CFDictionary)
    }
}
