import AppKit

/// Maps raw errors to user-friendly display information for the error block UI.
enum AppError {
    case overloaded
    case authFailed
    case serverIssue(Int)
    case notConnected
    case timeout
    case streamInterrupted(String)
    case loginFailed(String)
    case unknown(String)

    /// The bold title shown at the top of the error block.
    var title: String {
        switch self {
        case .overloaded:
            "Server Overloaded"
        case .authFailed:
            "Authentication Failed"
        case .serverIssue:
            "Server Issue"
        case .notConnected:
            "Not Connected"
        case .timeout:
            "Connection Timed Out"
        case .streamInterrupted:
            "Stream Interrupted"
        case .loginFailed:
            "Login Failed"
        case .unknown:
            "Something Went Wrong"
        }
    }

    /// The descriptive message shown below the title.
    var message: String {
        switch self {
        case .overloaded:
            "The API server is under heavy load. Try again in a moment."
        case .authFailed:
            "Your session has expired. Check your API key in AI Settings."
        case let .serverIssue(code):
            "The API server is experiencing problems (HTTP \(code)). Try again shortly."
        case .notConnected:
            "Add an API key in AI Settings to get started."
        case .timeout:
            "Couldn't reach the API server. Check your internet and try again."
        case let .streamInterrupted(detail):
            detail.isEmpty
                ? "The response was interrupted. Try sending your message again."
                : detail
        case let .loginFailed(detail):
            detail.isEmpty
                ? "Couldn't connect. Please try again."
                : detail
        case let .unknown(detail):
            detail.isEmpty
                ? "An unexpected error occurred. Please try again."
                : detail
        }
    }

    /// The tint color for the error block background and border.
    var tint: NSColor {
        switch self {
        case .overloaded, .serverIssue, .streamInterrupted, .unknown, .notConnected:
            .systemRed
        case .authFailed, .loginFailed:
            .systemOrange
        case .timeout:
            .systemGray
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
                switch statusCode {
                case 429:
                    return .overloaded
                case 529 where body.contains("overloaded"):
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
}
