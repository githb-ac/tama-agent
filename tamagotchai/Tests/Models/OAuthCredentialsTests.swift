import Foundation
import Testing
@testable import Tamagotchai

@Suite("OAuthCredentials")
struct OAuthCredentialsTests {
    @Test("isExpired returns true for past date")
    func expiredForPastDate() {
        let creds = OAuthCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSinceNow: -60)
        )
        #expect(creds.isExpired)
    }

    @Test("isExpired returns false for future date")
    func notExpiredForFutureDate() {
        let creds = OAuthCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSinceNow: 3600)
        )
        #expect(!creds.isExpired)
    }

    @Test("isExpired returns true for exact now (edge case)")
    func expiredForNow() {
        let creds = OAuthCredentials(
            accessToken: "token",
            refreshToken: "refresh",
            expiresAt: Date()
        )
        // Date() >= expiresAt should be true since Date() is at or after
        #expect(creds.isExpired)
    }
}
