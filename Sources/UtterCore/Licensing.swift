import CryptoKit
import Foundation

/// Offline license keys, verified with an Ed25519 public key built into the
/// app. Keys are made with `scripts/license.swift` using the matching private
/// key, which never goes in the repository. Works with any payment provider:
/// after a purchase, generate a key for the buyer and email it.
///
/// Format: `UTTER-<base64url payload>.<base64url signature>`, where the payload
/// is JSON `{"name": "...", "email": "...", "issued": <unix seconds>, "edition": "..."}`.
public enum Licensing {
    public struct Info: Codable, Equatable, Sendable {
        public var name: String
        public var email: String
        public var issued: Date
        public var edition: String

        public init(name: String, email: String, issued: Date, edition: String) {
            self.name = name; self.email = email; self.issued = issued; self.edition = edition
        }

        enum CodingKeys: String, CodingKey { case name, email, issued, edition }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            email = try c.decode(String.self, forKey: .email)
            issued = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .issued))
            edition = try c.decode(String.self, forKey: .edition)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(email, forKey: .email)
            try c.encode(issued.timeIntervalSince1970.rounded(), forKey: .issued)
            try c.encode(edition, forKey: .edition)
        }
    }

    /// Returns the license details if `key` was signed by the private key matching `publicKey`.
    public static func verify(_ key: String, publicKey: Data) -> Info? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("UTTER-") else { return nil }
        let parts = trimmed.dropFirst(6).split(separator: ".")
        guard parts.count == 2,
              let payload = base64URLDecode(String(parts[0])),
              let signature = base64URLDecode(String(parts[1])),
              let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              pk.isValidSignature(signature, for: payload)
        else { return nil }
        return try? JSONDecoder().decode(Info.self, from: payload)
    }

    /// Makes a key (used by the generator script and the checks).
    public static func sign(_ info: Info, privateKey: Curve25519.Signing.PrivateKey) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(info)
        let signature = try privateKey.signature(for: payload)
        return "UTTER-" + base64URLEncode(payload) + "." + base64URLEncode(signature)
    }

    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64URLDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }
}

/// The free trial.
public enum Trial {
    public static let days = 14

    public enum State: Equatable, Sendable {
        case active(daysLeft: Int)
        case expired
    }

    public static func state(firstLaunch: Date, now: Date, length: Int = days) -> State {
        let elapsed = now.timeIntervalSince(firstLaunch) / 86400
        let left = Int((Double(length) - elapsed).rounded(.up))
        return left > 0 ? .active(daysLeft: min(left, length)) : .expired
    }
}
