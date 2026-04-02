# AI Connectivity — Claude Haiku 4.5 with OAuth Login

## Overview

Add AI chat capability to Tamagotchai using Claude Haiku 4.5 via the Anthropic Messages API with OAuth authentication (matching the gg-coder PKCE flow). The user logs in via the menu bar ("Login to Claude"), which opens their browser. They paste the returned code into a small input field in the menu bar. Tokens are stored in Keychain. The prompt panel's `handleSubmit` will call Claude instead of returning placeholder text.

## Architecture

```
Sources/
  AI/
    ClaudeCredentials.swift    — OAuthCredentials model + Keychain persistence
    ClaudeOAuth.swift          — PKCE flow: build auth URL, exchange code, refresh token
    ClaudeService.swift        — Messages API streaming via URLSession.bytes SSE
  PromptPanel/
    PromptPanelController.swift — wire handleSubmit → ClaudeService
    FloatingPanel.swift         — add streamResponse() for incremental text updates
  TamagotchaiApp.swift          — add "Login to Claude" menu item + code input alert
```

## Key Design Decisions

- **No external AI SDK** — Anthropic's Messages API is simple enough to call directly with `URLSession.bytes(for:)` for SSE streaming. Avoids adding a heavy dependency.
- **OAuth PKCE flow** — mirrors the gg-coder `packages/ggcoder/src/core/oauth/anthropic.ts` exactly: same client ID (`9d1c250a-e61b-44d9-88ed-5944d1962f5e`), same endpoints, same scopes, same `code#state` format.
- **Keychain storage** — tokens stored in Keychain via `Security` framework (not UserDefaults) for security.
- **Streaming responses** — SSE parsing of `event:` / `data:` lines from the Anthropic stream, updating the response text view incrementally.
- **OAuth token requires Claude Code identity** — when using OAuth, the system prompt must include "You are Claude Code, Anthropic's official CLI for Claude." and beta headers `claude-code-20250219`, `oauth-2025-04-20` must be sent (matching `anthropic.ts` lines 49-58, 107-108).
- **Token auto-refresh** — before each API call, check if token is expired and refresh using the refresh token.

## API Details

### OAuth Endpoints (from gg-coder `anthropic.ts`)
- **Authorize**: `https://claude.ai/oauth/authorize` with `?code=true&client_id=...&response_type=code&redirect_uri=...&scope=...&code_challenge=...&code_challenge_method=S256&state=...`
- **Token exchange**: `POST https://platform.claude.com/v1/oauth/token` with JSON body `{ grant_type, client_id, code, state, redirect_uri, code_verifier }`
- **Token refresh**: `POST https://platform.claude.com/v1/oauth/token` with JSON body `{ grant_type: "refresh_token", client_id, refresh_token }`
- **Redirect URI**: `https://platform.claude.com/oauth/code/callback`
- **Scopes**: `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`
- **Client ID**: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`

### Messages API
- **URL**: `https://api.anthropic.com/v1/messages`
- **Model**: `claude-haiku-4-5-20251001`
- **Headers for OAuth**: `Authorization: Bearer <token>`, `anthropic-version: 2023-06-01`, `anthropic-beta: claude-code-20250219,oauth-2025-04-20`, `content-type: application/json`, `user-agent: claude-cli/2.1.75`, `x-app: cli`
- **System prompt must start with**: `"You are Claude Code, Anthropic's official CLI for Claude."`
- **SSE stream events**: `message_start`, `content_block_start`, `content_block_delta` (with `text_delta`), `content_block_stop`, `message_delta`, `message_stop`

### Entitlements
Need to add `com.apple.security.network.client` for outgoing network access.

## Steps

1. Create `tamagotchai/Sources/AI/ClaudeCredentials.swift` — define `OAuthCredentials` struct (accessToken, refreshToken, expiresAt) with Keychain save/load/delete using the Security framework, keyed as `com.unstablemind.tamagotchai.claude-oauth`.
2. Create `tamagotchai/Sources/AI/ClaudeOAuth.swift` — implement PKCE generation (verifier + SHA-256 challenge via CryptoKit), build the authorize URL, and implement `exchangeCode(code:state:verifier:)` and `refreshToken(refreshToken:)` async functions calling `https://platform.claude.com/v1/oauth/token`. Store a pending `(verifier, state)` tuple for the active login flow.
3. Create `tamagotchai/Sources/AI/ClaudeService.swift` — a `@MainActor` singleton that holds the current `OAuthCredentials?`, exposes `func send(userMessage:systemPrompt:) -> AsyncThrowingStream<String, Error>` which calls the Anthropic Messages API at `https://api.anthropic.com/v1/messages` with model `claude-haiku-4-5-20251001`, streams SSE via `URLSession.shared.bytes(for:)`, parses `event:` / `data:` lines, extracts `text_delta` text and yields it. Auto-refreshes expired tokens before requests. Uses required OAuth headers (anthropic-beta, user-agent, x-app) and system prompt prefix.
4. Update `tamagotchai/Entitlements/Tamagotchai.entitlements` — add `com.apple.security.network.client = true` to allow outgoing HTTP requests.
5. Update `tamagotchai/Sources/TamagotchaiApp.swift` — add a "Login to Claude" / "Logout from Claude" menu item (dynamic based on auth state) and a "Paste Login Code" menu item. "Login to Claude" calls `ClaudeOAuth.startLogin()` which opens the browser via `NSWorkspace.shared.open(url)`. "Paste Login Code" shows an `NSAlert` with an `NSTextField` input accessory for the `code#state` string, then calls `ClaudeOAuth.completeLogin(rawCode:)` which exchanges the code and saves credentials via `ClaudeCredentials`.
6. Update `tamagotchai/Sources/PromptPanel/FloatingPanel.swift` — add a `func streamResponse(_ stream: AsyncThrowingStream<String, Error>)` method that iterates the stream, appending each text delta to `responseTextView.string` and recalculating height progressively, so the response area grows as text streams in.
7. Update `tamagotchai/Sources/PromptPanel/PromptPanelController.swift` — replace the placeholder `handleSubmit` with a call to `ClaudeService.shared.send(userMessage:)`, set mascot to `.waiting`, then call `panel?.streamResponse(stream)`, set mascot to `.responding` on first chunk, and `.idle` when done or on error. Show an error message in the response area if not logged in or if the API call fails.
8. Build and verify the project compiles with `cd /Users/kenkai/Documents/UnstableMind/tamagotchai && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | tail -30`.
