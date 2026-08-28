import CryptoKit
import Foundation

let input = FileHandle.standardInput.readDataToEndOfFile()
guard
    let encodedPrivateKey = String(data: input, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
    let privateSeed = Data(base64Encoded: encodedPrivateKey),
    privateSeed.count == 32
else {
    FileHandle.standardError.write(Data("invalid Sparkle private key\n".utf8))
    exit(1)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateSeed)
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
} catch {
    FileHandle.standardError.write(Data("invalid Sparkle private key\n".utf8))
    exit(1)
}
