// Only for local tests and rehearsals. Sparkle's current key-file format is a base64 Ed25519 seed.
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
