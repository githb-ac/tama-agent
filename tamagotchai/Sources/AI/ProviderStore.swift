import CryptoKit
import Foundation
import os

private let logger = Logger(
    subsystem: "com.unstablemind.tamagotchai",
    category: "provider-store"
)

/// Credential for a single provider — an API key.
struct ProviderCredential: Codable {
    let accessToken: String

    /// Create from a simple API key.
    static func apiKey(_ key: String) -> ProviderCredential {
        ProviderCredential(accessToken: key)
    }
}

/// Persisted state for all provider credentials and model selection.
private struct StoreData: Codable {
    var credentials: [String: ProviderCredential]
    var selectedModelId: String?

    static let empty = StoreData(credentials: [:], selectedModelId: nil)
}

/// Manages API keys for all providers and persists selected model.
@MainActor
final class ProviderStore {
    static let shared = ProviderStore()

    private var data: StoreData
    private static let fileName = "provider-store.enc"

    private init() {
        data = Self.loadFromDisk() ?? .empty
    }

    // MARK: - Credentials

    func hasCredentials(for provider: AIProvider) -> Bool {
        data.credentials[provider.rawValue] != nil
    }

    func credential(for provider: AIProvider) -> ProviderCredential? {
        data.credentials[provider.rawValue]
    }

    func setCredential(_ credential: ProviderCredential, for provider: AIProvider) {
        data.credentials[provider.rawValue] = credential
        save()
    }

    func removeCredential(for provider: AIProvider) {
        data.credentials.removeValue(forKey: provider.rawValue)
        // If the selected model belongs to this provider, clear it
        if let modelId = data.selectedModelId,
           let model = ModelRegistry.model(withId: modelId),
           model.provider == provider
        {
            data.selectedModelId = nil
        }
        save()
    }

    /// Returns the access token for the given provider.
    func validAccessToken(for provider: AIProvider) async throws -> String {
        guard let cred = data.credentials[provider.rawValue] else {
            throw ProviderStoreError.noCredentials(provider)
        }
        return cred.accessToken
    }

    // MARK: - Model Selection

    var selectedModel: ModelInfo {
        if let id = data.selectedModelId, let model = ModelRegistry.model(withId: id) {
            if hasCredentials(for: model.provider) {
                return model
            }
        }
        // Fall back to first available model
        if let first = ModelRegistry.availableModels().first {
            return first
        }
        // Ultimate fallback
        return ModelRegistry.defaultModel(for: .moonshot)
    }

    func setSelectedModel(_ model: ModelInfo) {
        data.selectedModelId = model.id
        save()
    }

    /// Whether any provider has credentials configured.
    var hasAnyCredentials: Bool {
        !data.credentials.isEmpty
    }

    // MARK: - Persistence

    private func save() {
        do {
            let jsonData = try JSONEncoder().encode(data)
            let key = ClaudeCredentials.sharedEncryptionKey
            let sealed = try ChaChaPoly.seal(jsonData, using: key)
            try sealed.combined.write(to: Self.fileURL())
            logger.info("Provider store saved")
        } catch {
            logger.error("Failed to save provider store: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> StoreData? {
        do {
            let url = try fileURL()
            let combined = try Data(contentsOf: url)
            let box = try ChaChaPoly.SealedBox(combined: combined)
            let key = ClaudeCredentials.sharedEncryptionKey
            let jsonData = try ChaChaPoly.open(box, using: key)
            return try JSONDecoder().decode(StoreData.self, from: jsonData)
        } catch {
            return nil
        }
    }

    private static func fileURL() throws -> URL {
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

    // MARK: - Errors

    enum ProviderStoreError: LocalizedError {
        case noCredentials(AIProvider)

        var errorDescription: String? {
            switch self {
            case let .noCredentials(provider):
                "No API key configured for \(provider.displayName). Add one in Settings."
            }
        }
    }
}
