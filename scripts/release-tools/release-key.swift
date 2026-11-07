// release-key.swift — Ed25519 keys for signed DynaNotch updates (docs/SECURITY.md).
//   swift scripts/release-tools/release-key.swift generate   → prints "<private b64> <public b64>"
//   swift scripts/release-tools/release-key.swift public        (private key on stdin)
//   swift scripts/release-tools/release-key.swift sign <file>   (private key on stdin) → base64 signature
// The private key is read from stdin, never from arguments (those show up in `ps`).
import CryptoKit
import Foundation

let args = CommandLine.arguments
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }
func stdinKey() -> Curve25519.Signing.PrivateKey {
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    guard let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("bad key on stdin") }
    return key
}
guard args.count >= 2 else { fail("usage: release-key.swift generate | public | sign <file>  (key on stdin)") }
switch args[1] {
case "generate":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    print(stdinKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard args.count == 3, let data = FileManager.default.contents(atPath: args[2]) else { fail("can't read file") }
    guard let signature = try? stdinKey().signature(for: data) else { fail("can't sign") }
    print(signature.base64EncodedString())
default:
    fail("unknown command \(args[1])")
}
