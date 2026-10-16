import CryptoKit
import Foundation

// Verify the exact release offer and both signatures with the public key the app embeds. Feed signing
// follows Sparkle 2.10's common_cli/Signing.swift and SPUExtractSignedFeed.m: sign the original bytes
// before the trailing sparkle-signatures comment, without XML canonicalization. Notes are embedded.
//   swift Scripts/verify-appcast.swift <appcast.xml> <archive> <public-key-base64> <version>
//       [--download-url-prefix <url>]
// Exit 0 on success, 1 on invalid release data, 2 on usage. No private key or Keychain access.

func fail(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("verify-appcast: \(reason)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5 || (args.count == 7 && args[5] == "--download-url-prefix" && !args[6].isEmpty) else {
    FileHandle.standardError.write(Data("usage: verify-appcast.swift <appcast.xml> <archive> <public-key-base64> <version> [--download-url-prefix <url>]\n".utf8))
    exit(2)
}
let version = args[4]
let prefix = args.count == 7 ? args[6] : "https://github.com/andersonba/pullglance/releases/download/v\(version)/"
let expectedURL = (prefix.hasSuffix("/") ? prefix : prefix + "/") + "Pullglance.zip"
guard let keyData = Data(base64Encoded: args[3]), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("the public key is not a 32-byte Ed25519 key in base64")
}
guard let feed = try? Data(contentsOf: URL(fileURLWithPath: args[1])) else { fail("cannot read \(args[1])") }
guard let archive = try? Data(contentsOf: URL(fileURLWithPath: args[2])) else { fail("cannot read \(args[2])") }

let marker = Data("<!-- sparkle-signatures:\n".utf8)
guard let blockRange = feed.range(of: marker, options: .backwards),
      let block = String(data: feed[blockRange.lowerBound...], encoding: .utf8) else {
    fail("missing feed signature block")
}
let content = Data(feed[..<blockRange.lowerBound])
// Accept only Sparkle's complete trailing block. In particular no unsigned XML may follow it.
let blockPattern = try! NSRegularExpression(pattern: #"\A<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]{86}==)\nlength: ([0-9]+)\n-->\n?\z"#)
guard let match = blockPattern.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
      let signatureRange = Range(match.range(at: 1), in: block),
      let lengthRange = Range(match.range(at: 2), in: block),
      let feedSignature = Data(base64Encoded: String(block[signatureRange])),
      UInt64(block[lengthRange]) == UInt64(content.count),
      content.range(of: marker) == nil,
      key.isValidSignature(feedSignature, for: content) else {
    fail("invalid feed signature or signed length")
}

let document: XMLDocument
do {
    document = try XMLDocument(data: content, options: [.nodeLoadExternalEntitiesNever])
} catch {
    fail("invalid XML: \(error)")
}
guard document.dtd == nil else { fail("XML must not contain a DTD") }
let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
func children(_ parent: XMLElement, named name: String, namespace: String = "") -> [XMLElement] {
    (parent.children ?? []).compactMap { $0 as? XMLElement }.filter {
        $0.localName == name && ($0.uri ?? "") == namespace
    }
}
guard let root = document.rootElement(), root.name == "rss", (root.uri ?? "").isEmpty,
      children(root, named: "channel").count == 1 else { fail("XML must contain one rss/channel") }
let channel = children(root, named: "channel")[0]
let items = children(channel, named: "item")
guard items.count == 1, (try? document.nodes(forXPath: "//item").count) == 1 else { fail("expected one item") }
let item = items[0]
for field in ["version", "shortVersionString"] {
    let elements = children(item, named: field, namespace: sparkleNamespace)
    guard elements.count == 1, elements[0].stringValue == version else {
        fail("sparkle:\(field) must occur once and equal \(version)")
    }
}
let enclosures = children(item, named: "enclosure")
guard enclosures.count == 1, (try? document.nodes(forXPath: "//enclosure").count) == 1 else { fail("expected one enclosure") }
let enclosure = enclosures[0]
// Reject the legacy attribute form too: conflicting attributes can let a reader interpret a different
// version from the item elements used by generate_appcast and checked above.
for field in ["version", "shortVersionString"] {
    guard enclosure.attribute(forLocalName: field, uri: sparkleNamespace) == nil else {
        fail("sparkle:\(field) must only be specified on the item")
    }
}
guard enclosure.attribute(forName: "url")?.stringValue == expectedURL else { fail("enclosure url must equal \(expectedURL)") }
guard let length = enclosure.attribute(forName: "length")?.stringValue,
      length.range(of: #"\A[0-9]+\z"#, options: .regularExpression) != nil,
      UInt64(length) == UInt64(archive.count) else { fail("enclosure length must equal archive size \(archive.count)") }
guard let encodedSignature = enclosure.attribute(forLocalName: "edSignature", uri: sparkleNamespace)?.stringValue,
      let signature = Data(base64Encoded: encodedSignature),
      key.isValidSignature(signature, for: archive) else { fail("invalid archive signature under this key") }
print("verify-appcast: ok (v\(version), feed and archive)")
