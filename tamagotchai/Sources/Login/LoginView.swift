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
                .font(.headline)
                .padding(.top, 6)
                .padding(.bottom, 8)

            if isLoggedIn {
                loggedInContent
            } else {
                loggedOutContent
            }

            Divider()
                .padding(.top, 8)

            HStack {
                if !isLoggedIn {
                    Button("Open Browser Login") {
                        ClaudeOAuth.startLogin()
                    }
                }
                Spacer()
                Button("Done") {
                    LoginWindowController.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 380)
    }

    private var loggedInContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected").font(.body).fontWeight(.medium)
                    Text("You are logged in to Claude.").font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Button("Logout") {
                    ClaudeService.shared.logout()
                    onLoginStateChanged(false)
                    LoginWindowController.dismiss()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var loggedOutContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Not Connected").font(.body).fontWeight(.medium)
                    Text("Login to use Claude AI features.").font(.caption).foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste Login Code")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("code#state", text: $loginCode)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLoggingIn)

                    Button(isLoggingIn ? "Logging in…" : "Login") {
                        submitCode()
                    }
                    .disabled(loginCode.isEmpty || isLoggingIn)
                    .controlSize(.small)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
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
                errorMessage = error.localizedDescription
            }
            isLoggingIn = false
        }
    }
}
