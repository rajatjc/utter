import UtterCore
import Foundation
import Security

/// Trial and license state. The license key and the trial start date live in
/// the login Keychain; keys are verified offline against the public key below
/// (see `scripts/license.swift` for making keys).
@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    /// Ed25519 public key matching the private signing key kept outside the repo.
    static let publicKey = Data(base64Encoded: "lMJUGjVuaPt19cqgqNoQmzrQ4TLyxrcqp7CDMNVxJp8=")!

    /// Where the "Buy" button goes. Point it at your store page (Paddle, Lemon Squeezy, Gumroad…).
    static let purchaseURL = URL(string: "https://github.com/rajatjc/utter")!

    enum State: Equatable {
        case licensed(Licensing.Info)
        case trial(daysLeft: Int)
        case expired
    }

    @Published private(set) var state: State = .trial(daysLeft: Trial.days)

    private let service = "dev.utter.Utter"

    init() { refresh() }

    var canDictate: Bool {
        if case .expired = state { return false }
        return true
    }

    func refresh() {
        if let key = read("license-key"), let info = Licensing.verify(key, publicKey: Self.publicKey) {
            state = .licensed(info)
            return
        }
        let start: Date
        if let saved = read("trial-start"), let seconds = Double(saved) {
            start = Date(timeIntervalSince1970: seconds)
        } else {
            start = Date()
            write("trial-start", String(start.timeIntervalSince1970))
        }
        switch Trial.state(firstLaunch: start, now: Date()) {
        case .active(let days): state = .trial(daysLeft: days)
        case .expired: state = .expired
        }
    }

    /// Returns an error message, or nil when the key was accepted.
    func activate(_ key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Licensing.verify(trimmed, publicKey: Self.publicKey) != nil else {
            return "That key isn't valid. Copy the whole key, starting with UTTER-."
        }
        write("license-key", trimmed)
        refresh()
        return nil
    }

    func deactivate() {
        delete("license-key")
        refresh()
    }

    // MARK: Keychain

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ account: String, _ value: String) {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    private func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
