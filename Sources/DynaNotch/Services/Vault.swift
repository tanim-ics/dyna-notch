import CryptoKit
import Foundation
import os
import DynaNotchCore

/// Encryption at rest with a key that never leaves this Mac's Secure Enclave (docs/SECURITY.md §6). No certificate,
/// no Keychain, no prompts. The chip holds a P-256 key (only its chip-encrypted blob is stored); the file key comes
/// from a key agreement with a stored public key. Copies of the data folder — backups, Time Machine, another Mac —
/// are unreadable. Without a Secure Enclave (some Intel Macs, VMs) files stay plain, as before.
enum Vault {
    private static let logger = Logger(subsystem: "com.tanim.dynanotch", category: "vault")
    private static let lock = NSLock()
    private static var cachedKey: SymmetricKey?
    private static var attempted = false

    static var directory: URL { AppDataStore.directory.appendingPathComponent("vault", isDirectory: true) }
    private static var enclaveBlobURL: URL { directory.appendingPathComponent("enclave-key") }
    private static var peerKeyURL: URL { directory.appendingPathComponent("peer-key") }

    /// "on" (Secure Enclave), "unavailable" (plain files), or "locked" (a key from another Mac; old data moved aside).
    private(set) static var status = "off"

    /// The file key, created on first use. nil = no Secure Enclave: callers write plain data.
    static var key: SymmetricKey? {
        lock.lock(); defer { lock.unlock() }
        if attempted { return cachedKey }
        attempted = true
        cachedKey = loadOrCreateKey()
        return cachedKey
    }

    // MARK: Files

    /// Encrypts (when a key exists) and writes atomically, readable by this user only.
    static func write(_ plain: Data, to url: URL) throws {
        let data = try key.map { try SealedFile.seal(plain, key: $0) } ?? plain
        try data.write(to: url, options: .atomic)
        DataProtection.keepPrivate(url)
    }

    /// Reads and decrypts. Plain (older) files are returned as they are and re-encrypted on the next write.
    /// A sealed file this Mac can't open is moved aside as `<name>.locked` and nil is returned.
    static func read(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard SealedFile.isSealed(data) else { return data }
        guard let key = key, let opened = try? SealedFile.open(data, key: key) else {
            logger.error("a sealed file can't be opened on this Mac; moved aside")
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("locked"))
            return nil
        }
        return opened.plain
    }

    /// Launch: encrypts every data file still written in plain (older builds) — the JSON files in the data folder
    /// and the clipboard images. Idempotent, off the main queue.
    static func migrateExistingFiles() {
        DispatchQueue.global(qos: .utility).async {
            guard key != nil else { return }
            let fm = FileManager.default
            let dir = AppDataStore.directory
            let top = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let clips = (try? fm.contentsOfDirectory(at: dir.appendingPathComponent("Clips"), includingPropertiesForKeys: nil)) ?? []
            let files = top.filter { $0.pathExtension == "json" } + clips.filter { $0.pathExtension == "png" }
            files.forEach(sealInPlace)
            logger.info("vault: checked \(files.count) files")
        }
    }

    /// Encrypts a plain file in place (migration of data written before encryption).
    static func sealInPlace(_ url: URL) {
        let modified = { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        let before = modified()
        guard key != nil, let data = try? Data(contentsOf: url), !SealedFile.isSealed(data) else { return }
        // A newer save (always sealed) may have landed meanwhile: never write older contents over it.
        guard modified() == before else { return }
        try? write(data, to: url)
    }

    // MARK: Key

    private static func loadOrCreateKey() -> SymmetricKey? {
        guard SecureEnclave.isAvailable else {
            status = "unavailable"
            logger.notice("no Secure Enclave: data files stay plain")
            return nil
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if let blob = try? Data(contentsOf: enclaveBlobURL), let peerRaw = try? Data(contentsOf: peerKeyURL) {
                if let enclaveKey = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: blob),
                   let peer = try? P256.KeyAgreement.PublicKey(rawRepresentation: peerRaw),
                   let secret = try? enclaveKey.sharedSecretFromKeyAgreement(with: peer) {
                    status = "on"
                    return SealedFile.fileKey(from: secret)
                }
                // A key made by another Mac's chip (restored backup): start a new one; old sealed files go aside.
                logger.error("vault key belongs to another Mac: creating a new one")
                status = "locked"
                try? fm.moveItem(at: enclaveBlobURL, to: enclaveBlobURL.appendingPathExtension("old"))
            }
            let enclaveKey = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            let peer = P256.KeyAgreement.PrivateKey()   // only its public half is kept
            let secret = try enclaveKey.sharedSecretFromKeyAgreement(with: peer.publicKey)
            try enclaveKey.dataRepresentation.write(to: enclaveBlobURL, options: .atomic)
            try peer.publicKey.rawRepresentation.write(to: peerKeyURL, options: .atomic)
            for url in [enclaveBlobURL, peerKeyURL] {
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true   // useless on another Mac anyway
                var target = url
                try? target.setResourceValues(values)
            }
            if status != "locked" { status = "on" }
            logger.info("vault key created in the Secure Enclave")
            return SealedFile.fileKey(from: secret)
        } catch {
            status = "unavailable"
            logger.error("Secure Enclave key failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
