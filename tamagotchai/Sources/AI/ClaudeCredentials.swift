import CryptoKit
import Foundation

/// OAuth credentials for the Anthropic API.
struct OAuthCredentials: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

/// File-based persistence for Claude OAuth credentials.
///
/// Stores credentials as an encrypted JSON file in Application Support,
/// avoiding macOS Keychain password prompts that occur on every rebuild
/// during development (Keychain ties access to the exact code signature).
enum ClaudeCredentials {
    private static let fileName = "claude-oauth.enc"

    /// A stable device-derived key so credentials survive rebuilds.
    /// Falls back to a hardcoded key if the hardware UUID is unavailable.
    private nonisolated(unsafe) static var encryptionKey: SymmetricKey = {
        let seed = if let uuid = getHardwareUUID() {
            "com.unstablemind.tamagotchai.\(uuid)"
        } else {
            "com.unstablemind.tamagotchai.fallback-key"
        }
        let hash = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: hash)
    }()

    private static func credentialsURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Tamagotchai", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func save(_ credentials: OAuthCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let sealed = try ChaChaPoly.seal(data, using: encryptionKey)
        let combined = sealed.combined
        try combined.write(to: credentialsURL())
    }

    static func load() -> OAuthCredentials? {
        guard let url = try? credentialsURL(),
              let combined = try? Data(contentsOf: url),
              let box = try? ChaChaPoly.SealedBox(combined: combined),
              let data = try? ChaChaPoly.open(box, using: encryptionKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    static func delete() {
        guard let url = try? credentialsURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Reads the hardware UUID from IOKit (stable across rebuilds).
    private static func getHardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        let key = kIOPlatformUUIDKey as CFString
        guard let uuid = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
        else { return nil }
        return uuid
    }
}
