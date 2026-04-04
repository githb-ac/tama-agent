import Foundation

/// Supported AI providers.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case moonshot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moonshot: "Moonshot"
        }
    }

    var description: String {
        switch self {
        case .moonshot: "Kimi K2.5"
        }
    }

    /// Base URL for the provider's API.
    var baseURL: String {
        switch self {
        case .moonshot: "https://api.moonshot.ai/v1/chat/completions"
        }
    }

    /// Whether this provider uses OpenAI-compatible API format.
    var isOpenAICompatible: Bool {
        switch self {
        case .moonshot: true
        }
    }
}

/// Information about an available model.
struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextWindow: Int
    let maxOutputTokens: Int
    let supportsTools: Bool
    let supportsThinking: Bool
}

/// Central registry of available models.
enum ModelRegistry {
    static let models: [ModelInfo] = [
        ModelInfo(
            id: "kimi-k2.5",
            name: "Kimi K2.5",
            provider: .moonshot,
            contextWindow: 200_000,
            maxOutputTokens: 16384,
            supportsTools: true,
            supportsThinking: true
        ),
    ]

    /// Returns models for a specific provider.
    static func models(for provider: AIProvider) -> [ModelInfo] {
        models.filter { $0.provider == provider }
    }

    /// Returns the default model for a provider.
    static func defaultModel(for provider: AIProvider) -> ModelInfo {
        switch provider {
        case .moonshot:
            models.first { $0.id == "kimi-k2.5" }!
        }
    }

    /// Finds a model by ID.
    static func model(withId id: String) -> ModelInfo? {
        models.first { $0.id == id }
    }

    /// Returns models only for providers that have credentials configured.
    @MainActor
    static func availableModels() -> [ModelInfo] {
        models.filter { ProviderStore.shared.hasCredentials(for: $0.provider) }
    }
}
