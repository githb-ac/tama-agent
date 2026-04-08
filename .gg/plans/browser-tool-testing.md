# Browser Tool Testing Plan

## Approach

Two-tier testing:

### Tier 1: Unit Tests (Swift Testing, no browser required)
Run via `xcodebuild test`. Test all the things that don't require a live browser:
- BrowserTool input validation (missing action, missing params for each action)
- BrowserTool input schema structure validation
- Tool registration in registry (count + name lookup)
- Error enum coverage
- jsStringLiteral escaping correctness (test via the tool's evaluate action pattern)

### Tier 2: Integration Tests (standalone Swift script, requires Brave)
A standalone Swift script that exercises BrowserTool against a real browser. Tests:
- **Launch & Connect**: BrowserManager launches Brave in headless mode, gets CDP connection
- **Navigate**: Navigate to a `data:` URI HTML page (no network needed) — measure latency  
- **Evaluate**: Run JS expressions, verify return values for string/bool/number/object/array types
- **Get Text**: Extract text from specific elements on the data: page
- **Get HTML**: Get outerHTML for specific elements and full page
- **Click**: Click a button that modifies DOM state, verify the state changed
- **Type**: Type into an input field, verify the value was set
- **Wait**: Wait for a selector that already exists (should return immediately), and wait for a selector that doesn't exist (should timeout)
- **Screenshot**: Take screenshot, verify we get the expected response format
- **Error handling**: Navigate to invalid URL, click non-existent selector, evaluate bad JS
- **Speed**: Time each operation, report p50/p95 latencies
- **Connection reuse**: Verify multiple operations share one connection (no re-launch)
- **Cleanup**: BrowserManager.disconnect() kills the process

The data: URI page will contain a self-contained HTML page with:
- An h1 with known text
- A button that adds a paragraph when clicked
- An input field
- A hidden element (for wait testing)
- Known IDs for precise selector targeting

### Tier 3: Update existing ToolRegistryTests
The registry tool count changed from 13 to include `browser` and possibly `web_search` + `task`. Need to verify and update.

## Test HTML Page (data: URI)

```html
<html>
<body>
  <h1 id="title">Test Page</h1>
  <button id="btn" onclick="document.getElementById('output').innerText='clicked'">Click Me</button>
  <p id="output">not clicked</p>
  <input id="input" type="text" placeholder="type here">
  <div id="hidden" style="display:none">secret</div>
</body>
</html>
```

Encoded as `data:text/html,<html>...` (URL-encoded).

## Steps

1. Create `tamagotchai/Tests/Tools/BrowserToolTests.swift` with unit tests: missing action param, missing url for navigate, missing selector for click, missing text for type/evaluate, missing selector for wait, unknown action, input schema shape validation, jsStringLiteral escaping via evaluate
2. Create `tamagotchai/Tests/Tools/BrowserToolIntegrationTests.swift` with integration tests that launch Brave headless and exercise all 8 actions against a data: URI page, including speed measurements, error handling, and connection reuse verification — tagged with a custom trait so they can be run separately
3. Update `tamagotchai/Tests/Registry/ToolRegistryTests.swift` to account for the new browser tool (update tool count and expected names list)
4. Run `xcodegen generate` then `xcodebuild test` to execute all tests and verify results
5. Review test output, fix any failures, and report findings on speed/accuracy/efficiency
