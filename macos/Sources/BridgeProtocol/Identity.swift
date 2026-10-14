import CryptoKit
import Foundation
import Security
import X509

public struct Identity: @unchecked Sendable {
    public let secIdentity: SecIdentity
    public let certificate: Data
    public let fingerprint: String

    private init(secIdentity: SecIdentity, certificate: Data) {
        self.secIdentity = secIdentity
        self.certificate = certificate
        fingerprint = Fingerprint.of(certificate)
    }

    public enum Failure: Error {
        case invalidKey(String)
        case invalidCertificate
    }

    public static func loadOrCreate(in directory: URL, name: String = "Galaxy Bridge") throws -> Identity {
        let keyFile = directory.appendingPathComponent("key.raw")
        let certificateFile = directory.appendingPathComponent("certificate.der")
        let manager = FileManager.default
        if !manager.fileExists(atPath: certificateFile.path) || !manager.fileExists(atPath: keyFile.path) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let key = P256.Signing.PrivateKey()
            try key.rawRepresentation.write(to: keyFile, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
            try makeCertificate(key: key, name: name).write(to: certificateFile, options: .atomic)
        }
        return try load(
            key: P256.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyFile)),
            certificate: Data(contentsOf: certificateFile)
        )
    }

    public static func ephemeral(name: String = "Galaxy Bridge") throws -> Identity {
        let key = P256.Signing.PrivateKey()
        return try load(key: key, certificate: makeCertificate(key: key, name: name))
    }

    private static func makeCertificate(key: P256.Signing.PrivateKey, name: String) throws -> Data {
        let certificateKey = Certificate.PrivateKey(key)
        let subject = try DistinguishedName { CommonName(name) }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: certificateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-24 * 3600),
            notValidAfter: now.addingTimeInterval(20 * 365 * 24 * 3600),
            issuer: subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth, .clientAuth])
            },
            issuerPrivateKey: certificateKey
        )
        return Data(try certificate.serializeAsPEM().derBytes)
    }

    private static func load(key: P256.Signing.PrivateKey, certificate: Data) throws -> Identity {
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(
            key.x963Representation as CFData,
            [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary,
            &error
        ) else {
            throw Failure.invalidKey(error.map { "\($0.takeRetainedValue())" } ?? "")
        }
        guard let secCertificate = SecCertificateCreateWithData(nil, certificate as CFData),
              let identity = SecIdentityCreate(nil, secCertificate, secKey)
        else { throw Failure.invalidCertificate }
        return Identity(secIdentity: identity, certificate: certificate)
    }
}

public enum Fingerprint {
    public static func of(_ certificate: Data) -> String {
        SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
    }

    public static func shortID(_ fingerprint: String) -> String {
        String(fingerprint.prefix(16))
    }

    public static func display(_ fingerprint: String) -> String {
        let digits = Array(fingerprint.prefix(12).uppercased())
        return stride(from: 0, to: digits.count, by: 4).map { String(digits[$0..<min($0 + 4, digits.count)]) }.joined(separator: " ")
    }
}
