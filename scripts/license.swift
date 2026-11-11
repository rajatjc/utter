// Utter license keys.
//
//   swift scripts/license.swift keygen
//       Creates the signing key pair (once). The PRIVATE key is saved to
//       ~/Library/Application Support/Utter-licensing/signing-key (readable only
//       by you); never commit it. Paste the printed PUBLIC key into
//       Sources/Utter/Features/LicenseManager.swift.
//
//   swift scripts/license.swift issue --name "Ada Lovelace" --email ada@example.com [--edition pro]
//       Prints a license key to email to a buyer. Hook this up to your payment
//       provider's "order completed" webhook to automate it.
//
// Key format (must match UtterCore/Licensing.swift):
//   UTTER-<base64url(JSON payload)>.<base64url(Ed25519 signature of the payload)>
import CryptoKit
import Foundation

let keyDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Utter-licensing", isDirectory: true)
let keyFile = keyDir.appendingPathComponent("signing-key")

func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func option(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch CommandLine.arguments.dropFirst().first {
case "keygen":
    if FileManager.default.fileExists(atPath: keyFile.path) {
        fail("A signing key already exists at \(keyFile.path). Keys already sold depend on it; not overwriting.")
    }
    let key = Curve25519.Signing.PrivateKey()
    try FileManager.default.createDirectory(at: keyDir, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyFile)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
    print("Private key saved to \(keyFile.path). Back it up somewhere safe and never commit it.")
    print("Public key (paste into LicenseManager.swift):")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "issue":
    guard let name = option("--name"), let email = option("--email") else {
        fail("usage: swift scripts/license.swift issue --name NAME --email EMAIL [--edition pro]")
    }
    guard let stored = try? String(contentsOf: keyFile, encoding: .utf8),
          let raw = Data(base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("No signing key at \(keyFile.path). Run: swift scripts/license.swift keygen") }
    let payload: [String: Any] = [
        "name": name,
        "email": email,
        "edition": option("--edition") ?? "pro",
        "issued": Date().timeIntervalSince1970.rounded(),
    ]
    let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let signature = try key.signature(for: json)
    print("UTTER-" + base64URL(json) + "." + base64URL(signature))

default:
    fail("usage: swift scripts/license.swift keygen | issue --name NAME --email EMAIL [--edition pro]")
}
