# WebSearchTool — Free Multi-Engine HTML Scraping

## Overview

Add a `web_search` agent tool that performs web searches by scraping search engine HTML pages directly — no API keys, no costs, unlimited usage. Uses DuckDuckGo as the primary engine with Brave and Google as fallbacks when rate-limited.

Based on [BasedHardware/omi](https://github.com/BasedHardware/omi) for the core DDG parsing (clean async/await, proper `uddg=` unwrapping, snippet extraction) and [osaurus-ai/osaurus-tools](https://github.com/osaurus-ai/osaurus-tools) for resilience (rate limit detection, exponential backoff with jitter, multi-engine cascade, user-agent rotation).

## Design

### Search Provider Cascade
1. **DuckDuckGo** (`html.duckduckgo.com/html/`) — primary, most reliable HTML endpoint
2. **Brave** (`search.brave.com/search`) — fallback if DDG rate-limits
3. **Google** (`www.google.com/search`) — last resort fallback

If a provider returns a rate-limit signal (HTTP 429/403/503, or body contains anti-bot patterns), we move to the next provider. Each request uses exponential backoff with jitter (1s → 2s → 4s, up to 3 retries per provider).

### Architecture — Single File

`tamagotchai/Sources/AI/Tools/WebSearchTool.swift` (~250 lines)

```
WebSearchTool (AgentTool)
├── execute(args:) → dispatches to SearchEngine
├── SearchEngine (private enum: duckDuckGo, brave, google)
│   └── Each case knows its URL format + HTML parser
├── performSearch(query:, maxResults:) → tries engines in cascade
├── fetchWithRetry(request:, maxRetries:) → backoff + rate limit detection
├── parseDDGResults(html:) → from omi
├── parseBraveResults(html:) → from osaurus
├── parseGoogleResults(html:) → lightweight fallback
├── unwrapDDGRedirect(rawURL:) → from omi (URLComponents-based)
├── isRateLimited(statusCode:, html:) → from osaurus
└── Helpers: cleanHTML, randomUserAgent, HTML entity decoding
```

### Tool Schema

```json
{
  "name": "web_search",
  "description": "Search the web and return results. Use for current information, recent events, or facts beyond your knowledge.",
  "input_schema": {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Search query" },
      "max_results": { "type": "integer", "description": "Max results to return (default: 5, max: 20)" }
    },
    "required": ["query"]
  }
}
```

### Output Format

Returns a formatted string the LLM can reason over:

```
Web search results for: "swift concurrency 2026"

1. [Title of first result](https://example.com/page1)
   Snippet text from the search result...

2. [Title of second result](https://example.com/page2)
   Another snippet...

(5 results from DuckDuckGo)
```

### Resilience Features (from osaurus-tools)

- **Rate limit detection**: Check HTTP status (429, 403, 503) AND body patterns ("you appear to be a bot", "unusual traffic", "captcha", "rate limit", "too many requests", "blocked", "access denied")
- **Exponential backoff with jitter**: Base delay × 2^attempt × random(1.0–1.5), max 3 retries per engine
- **Engine cascade**: DDG → Brave → Google, automatic fallover on rate limit
- **User-agent rotation**: 5 realistic browser user-agents, randomly selected per request
- **Timeout**: 15s per request
- **Graceful degradation**: If all engines fail, return error message (not throw) so the agent can inform the user

### Logging

Category: `tool.search` (follows existing `tool.*` pattern from CLAUDE.md)

Log points:
- `info`: query, engine selected, result count
- `warning`: rate limited by engine X, falling back to Y
- `error`: all engines exhausted

## File Changes

- **New**: `tamagotchai/Sources/AI/Tools/WebSearchTool.swift` — the tool implementation
- **Edit**: `tamagotchai/Sources/AI/Tools/AgentTool.swift` — add `WebSearchTool()` to `defaultRegistry`

## Steps

1. Create `tamagotchai/Sources/AI/Tools/WebSearchTool.swift` with the full implementation: `WebSearchTool` conforming to `AgentTool` with `@unchecked Sendable`, private search engine cascade (DuckDuckGo → Brave → Google), HTML parsers for each engine (DDG parsing from omi's `OnboardingWebResearchService`, Brave parsing from osaurus-tools' `parseBraveResults`), rate limit detection (HTTP status codes 429/403/503 + body pattern matching from osaurus-tools), exponential backoff with jitter (from osaurus-tools' `performRequestWithRetry`), user-agent rotation (5 agents from osaurus-tools), DDG URL unwrapping via `URLComponents` (from omi), HTML entity decoding, and `os.Logger` with category `tool.search`.
2. Edit `tamagotchai/Sources/AI/Tools/AgentTool.swift` line 66 to add `WebSearchTool(),` to the `defaultRegistry` tools array (between `WebFetchTool()` and `CreateReminderTool()`).
3. Run `xcodegen generate` to regenerate the Xcode project with the new file, then build with `xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` and fix any compiler errors.
4. Run `swiftformat --config .swiftformat tamagotchai/Sources/AI/Tools/WebSearchTool.swift` and `swiftlint lint --config .swiftlint.yml tamagotchai/Sources/AI/Tools/WebSearchTool.swift` to ensure the new file passes formatting and lint checks.
