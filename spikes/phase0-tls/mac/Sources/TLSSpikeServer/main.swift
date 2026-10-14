import CryptoKit
import Foundation
import Network
import Security
import X509

let port: UInt16 = 52800
let directory = URL(fileURLWithPath: "identity", isDirectory: true)
let arguments = CommandLine.arguments
let pinned = arguments.firstIndex(of: "--pin").map { arguments[$0 + 1].lowercased() }
let queue = DispatchQueue(label: "tls-spike")

func log(_ message: String) {
    print("[mac] \(message)")
    fflush(stdout)
}

func fingerprint(_ der: Data) -> String {
    SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
}

func loadIdentity() throws -> (SecIdentity, Data) {
    let keyFile = directory.appendingPathComponent("key.raw")
    let certFile = directory.appendingPathComponent("cert.der")
    if !FileManager.default.fileExists(atPath: certFile.path) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = P256.Signing.PrivateKey()
        let certificateKey = Certificate.PrivateKey(key)
        let name = try DistinguishedName { CommonName("Galaxy Bridge (teste)") }
        let now = Date()
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: certificateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-3600),
            notValidAfter: now.addingTimeInterval(10 * 365 * 24 * 3600),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: try Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                Critical(KeyUsage(digitalSignature: true))
                try ExtendedKeyUsage([.serverAuth, .clientAuth])
            },
            issuerPrivateKey: certificateKey
        )
        try Data(certificate.serializeAsPEM().derBytes).write(to: certFile)
        try key.rawRepresentation.write(to: keyFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        log("Identidade nova criada em \(directory.path)")
    }

    let key = try P256.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyFile))
    let der = try Data(contentsOf: certFile)
    var error: Unmanaged<CFError>?
    guard let secKey = SecKeyCreateWithData(
        key.x963Representation as CFData,
        [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate] as CFDictionary,
        &error
    ) else { throw error!.takeRetainedValue() }
    guard let secCertificate = SecCertificateCreateWithData(nil, der as CFData),
          let identity = SecIdentityCreate(nil, secCertificate, secKey)
    else { throw NSError(domain: "spike", code: 1, userInfo: [NSLocalizedDescriptionKey: "SecIdentityCreate falhou"]) }
    return (identity, der)
}

func makeParameters(identity: SecIdentity) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let options = tls.securityProtocolOptions
    sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
    sec_protocol_options_set_local_identity(options, sec_identity_create(identity)!)
    sec_protocol_options_set_peer_authentication_required(options, true)
    sec_protocol_options_set_verify_block(options, { metadata, trust, complete in
        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let leaf = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first else {
            log("Celular sem certificado: recusado")
            complete(false)
            return
        }
        let peer = fingerprint(SecCertificateCopyData(leaf) as Data)
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata)
        let accepted = pinned == nil || peer == pinned
        log("Certificado do celular: \(peer)")
        log("TLS \(version == .TLSv13 ? "1.3" : "\(version.rawValue)"): \(accepted ? "aceito" : "RECUSADO (não é o celular pareado)")")
        complete(accepted)
    }, queue)

    let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
    return parameters
}

func receive(on connection: NWConnection) {
    connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { header, _, done, error in
        guard let header, header.count == 4, error == nil else {
            if let error { log("Conexão encerrada: \(error)") }
            if done { log("Celular desconectou") }
            return
        }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { body, _, _, _ in
            guard let body else { return }
            log("Recebido: \(String(decoding: body, as: UTF8.self))")
            send(#"{"type":"hello","body":{"name":"Mac (teste)"}}"#, on: connection)
            receive(on: connection)
        }
    }
}

func send(_ json: String, on connection: NWConnection) {
    let body = Data(json.utf8)
    var length = UInt32(body.count).bigEndian
    connection.send(content: Data(bytes: &length, count: 4) + body, completion: .contentProcessed { error in
        if let error { log("Envio falhou: \(error)") }
    })
}

do {
    let (identity, der) = try loadIdentity()
    log("Impressão digital do Mac: \(fingerprint(der))")
    log(pinned.map { "Só aceita o celular \($0)" } ?? "Aceita qualquer celular (sem --pin)")

    let listener = try NWListener(using: makeParameters(identity: identity))
    listener.newConnectionHandler = { connection in
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: log("Conexão pronta")
            case .failed(let error): log("Conexão falhou: \(error)")
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }
    listener.stateUpdateHandler = { state in
        if case .ready = state { log("Escutando em 127.0.0.1:\(port)") }
        if case .failed(let error) = state { log("Listener falhou: \(error)"); exit(1) }
    }
    listener.start(queue: queue)
    dispatchMain()
} catch {
    log("Erro: \(error)")
    exit(1)
}
