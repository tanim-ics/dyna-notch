import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Encrypted files on disk (docs/SECURITY.md §6). Format: "DNV1" + AES-256-GCM combined (12-byte nonce, ciphertext,
/// 16-byte tag). The key comes from the Mac's Secure Enclave (app side, `Vault`); this file only seals and opens.
public enum SealedFile {
    public static let magic = Data("DNV1".utf8)

    public static func isSealed(_ data: Data) -> Bool {
        data.count >= magic.count + 28 && data.prefix(magic.count) == magic
    }

    #if canImport(CryptoKit)
    public static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw CryptoKitError.incorrectParameterSize }
        return magic + combined
    }

    /// The plaintext of a sealed file; legacy plain files come back unchanged (`wasSealed == false`) so they can be
    /// migrated. Throws when a sealed file can't be opened (wrong key, tampered).
    public static func open(_ data: Data, key: SymmetricKey) throws -> (plain: Data, wasSealed: Bool) {
        guard isSealed(data) else { return (data, false) }
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return (try AES.GCM.open(box, using: key), true)
    }

    /// The file key from a Secure Enclave key agreement: HKDF-SHA256 over the shared secret, fixed salt and purpose.
    public static func fileKey(from secret: SharedSecret) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("DynaNotch vault v1".utf8),
                                       sharedInfo: Data("files".utf8), outputByteCount: 32)
    }
    #endif
}
