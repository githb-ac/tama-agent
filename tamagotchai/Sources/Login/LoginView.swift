import SwiftUI

struct LoginView: View {
    @State private var loginCode = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    let isLoggedIn: Bool
    let onLoginStateChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(isLoggedIn ? "Claude Account" : "Login to Claude")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 10)
                .padding(.bottom, 8)

            if isLoggedIn {
                loggedInContent
            } else {
                loggedOutContent
            }

            Divider().opacity(0.3)
                .padding(.top, 8)

            HStack(spacing: 8) {
                if !isLoggedIn {
                    GlassButton("Open Browser Login") {
                        ClaudeOAuth.startLogin()
                    }
                }
                Spacer()
                GlassButton("Done", isPrimary: true) {
                    LoginWindowController.dismiss()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 340)
    }

    private var loggedInContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                Text("You are logged in to Claude.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
            }

            Spacer()

            GlassButton("Logout") {
                ClaudeService.shared.logout()
                onLoginStateChanged(false)
                LoginWindowController.dismiss()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var loggedOutContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Connected")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Login to use Claude AI features.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().opacity(0.3).padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste Login Code")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))

                HStack(spacing: 8) {
                    TextField("code#state", text: $loginCode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .disabled(isLoggingIn)

                    GlassButton(isLoggingIn ? "Logging in…" : "Login", isPrimary: true) {
                        submitCode()
                    }
                    .disabled(loginCode.isEmpty || isLoggingIn)
                    .opacity(loginCode.isEmpty || isLoggingIn ? 0.5 : 1)
                }

                if let errorMessage {
                    HStack(spacing: 6) {
                        Text(errorMessage)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
    }

    private func submitCode() {
        isLoggingIn = true
        errorMessage = nil

        Task {
            do {
                let credentials = try await ClaudeOAuth.completeLogin(rawCode: loginCode)
                ClaudeService.shared.setCredentials(credentials)
                onLoginStateChanged(true)
                LoginWindowController.dismiss()
            } catch {
                let appError = AppError.loginFailed(error.localizedDescription)
                errorMessage = appError.message
            }
            isLoggingIn = false
        }
    }
}
