import CryptoKit
import Foundation

// Checks that an appcast's one enclosure carries a valid Ed25519 signature of the archive under the given
// public key: the key the app embeds (Scripts/make-app.sh) against the key that signed the release
// (Scripts/make-appcast.sh). A mismatch would make every installed copy refuse the update.
//   swift Scripts/verify-appcast.swift <appcast.xml> <archive> <public-key-base64>
// Exit 0 when the signature verifies, 1 with a reason when it does not, 2 on usage.

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-appcast.swift <appcast.xml> <archive> <public-key-base64>\n".utf8))
    exit(2)
}
func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("verify-appcast: \(reason)\n".utf8))
    exit(1)
}

guard let xml = try? String(contentsOfFile: args[1], encoding: .utf8) else { fail("cannot read \(args[1])") }
let pattern = try! NSRegularExpression(pattern: #"sparkle:edSignature="([^"]+)""#)
let signatures = pattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).map { String(xml[Range($0.range(at: 1), in: xml)!]) }
guard signatures.count == 1 else { fail("expected one enclosure with sparkle:edSignature, found \(signatures.count)") }
guard let signature = Data(base64Encoded: signatures[0]) else { fail("the signature is not base64") }
guard let keyData = Data(base64Encoded: args[3]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("the public key is not a 32-byte Ed25519 key in base64")
}
guard let archive = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else { fail("cannot read \(args[2])") }
guard key.isValidSignature(signature, for: archive) else { fail("the signature does not match the archive under this key") }
print("verify-appcast: ok")
