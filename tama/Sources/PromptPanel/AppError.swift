import AppKit

/// Maps raw errors to user-friendly display information for the error block UI.
enum AppError {
    case overloaded
    case authFailed
    case usageLimitReached(String)
    case subscriptionRequired(String)
    case notConnected
    case timeout
    case streamInterrupted(String)
    case unknown(String)

    /// The bold title shown at the top of the error block.
    /// Short, friendly titles that don't sound alarming.
    var title: String {
        switch self {
        case .overloaded:
            "API Busy"
        case .authFailed:
            "Sign In Required"
        case .usageLimitReached:
            "Usage Limit Reached"
        case .subscriptionRequired:
            "Subscription Needed"
        case .notConnected:
            "Add API Key"
        case .timeout:
            "Connection Issue"
        case .streamInterrupted:
            "Interrupted"
        case .unknown:
            "Oops"
        }
    }

    /// The descriptive message shown below the title.
    var message: String {
        switch self {
        case .overloaded:
            "The API is busy. Try again in a moment."
        case .authFailed:
            "Check your API key in AI Settings."
        case let .usageLimitReached(detail):
            detail
        case let .subscriptionRequired(detail):
            detail
        case .notConnected:
            "Open AI Settings to add your API key."
        case .timeout:
            "Check your connection and try again."
        case let .streamInterrupted(detail):
            detail.isEmpty
                ? "The response was interrupted. Try again."
                : detail
        case let .unknown(detail):
            detail.isEmpty
                ? "Something went wrong. Try again."
                : detail
        }
    }

    /// The tint color for the error block background and border.
    /// Uses subtle oranges/ambers for warnings, neutral grays for info.
    var tint: NSColor {
        switch self {
        case .notConnected:
            // Neutral amber for "add API key" — not an error, just a state
            .systemOrange
        case .authFailed, .subscriptionRequired, .usageLimitReached:
            // Softer orange for auth/billing issues
            .systemOrange
        case .overloaded, .streamInterrupted, .unknown, .timeout:
            // Neutral amber for transient issues
            .systemOrange
        }
    }

    /// Creates an `AppError` from any Swift `Error`.
    static func from(_ error: Error) -> AppError {
        // Handle provider store errors
        if error is ProviderStore.ProviderStoreError {
            return .notConnected
        }

        // Handle Claude service errors
        if let serviceError = error as? ClaudeService.ClaudeServiceError {
            switch serviceError {
            case .notLoggedIn:
                return .notConnected
            case let .apiError(statusCode, body):
                let lowerBody = body.lowercased()

                // Detect temporary usage limits (e.g. OpenAI free-tier cap)
                if let resetInfo = Self.usageLimitInfo(statusCode: statusCode, body: lowerBody) {
                    return .usageLimitReached(resetInfo)
                }

                // Detect subscription/billing errors from any provider
                if Self.isBillingError(statusCode: statusCode, body: lowerBody) {
                    return .subscriptionRequired(
                        "This model requires a paid plan. "
                            + "Check your subscription at your provider's settings, "
                            + "or switch to a different model in AI Settings."
                    )
                }

                switch statusCode {
                case 429:
                    return .overloaded
                case 529 where lowerBody.contains("overloaded"):
                    return .overloaded
                case 401, 403:
                    return .authFailed
                default:
                    // Include the body for non-Anthropic providers so the
                    // actual error message is visible to the user.
                    let shortBody = body.count > 200 ? String(body.prefix(200)) + "…" : body
                    return .unknown("HTTP \(statusCode): \(shortBody)")
                }
            case let .streamError(msg):
                return .streamInterrupted(msg)
            }
        }

        // Handle URL/network errors
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed:
                return .timeout
            default:
                return .unknown(error.localizedDescription)
            }
        }

        return .unknown(error.localizedDescription)
    }

    /// Detects temporary usage limits and returns a user-friendly message with reset time.
    private static func usageLimitInfo(statusCode: Int, body: String) -> String? {
        guard statusCode == 429,
              body.contains("usage_limit_reached") || body.contains("usage limit")
        else { return nil }

        // Try to extract resets_in_seconds from the JSON body
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorObj = json["error"] as? [String: Any],
           let resetSeconds = errorObj["resets_in_seconds"] as? Int
        {
            let resetStr = formatResetTime(seconds: resetSeconds)
            return "You've hit the usage limit for this model. Resets in \(resetStr). "
                + "Switch to a different model in AI Settings."
        }

        return "You've hit the usage limit for this model. "
            + "Try again later or switch to a different model in AI Settings."
    }

    /// Formats seconds into a human-readable duration like "2h 30m" or "45m".
    private static func formatResetTime(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "less than a minute"
        }
    }

    /// Detects subscription, billing, or quota errors that indicate a paid plan is needed.
    private static func isBillingError(statusCode: Int, body: String) -> Bool {
        // HTTP 402 Payment Required is an explicit billing error
        if statusCode == 402 { return true }

        let billingKeywords = [
            "insufficient balance",
            "no resource package",
            "quota exceeded",
            "billing",
            "recharge",
            "subscription plan",
            "does not yet include access",
            "not supported",
            "plan does not",
            "upgrade your plan",
            "rate limit",
        ]

        // Only match on 400/403/429 to avoid false positives on unrelated errors
        guard [400, 403, 429].contains(statusCode) else { return false }
        return billingKeywords.contains { body.contains($0) }
    }
}
