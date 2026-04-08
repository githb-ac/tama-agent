---
name: fix
description: Auto-format, lint, and build — then spawn parallel agents to fix all issues
---

Run SwiftFormat, SwiftLint, and xcodebuild. Collect all errors, group by domain, and spawn parallel sub-agents to fix them.

## Step 1: Auto-format

Run SwiftFormat to auto-fix formatting issues first (this resolves most lint noise):

```bash
swiftformat --config .swiftformat tamagotchai/Sources
```

## Step 2: Run All Checks

Run these three commands and capture their full output. **Do not stop if one fails** — run all three regardless:

```bash
# Lint
swiftlint lint --config .swiftlint.yml --reporter emoji 2>&1 | tee /tmp/tamagotchai-lint.txt

# Build (catches type errors, missing imports, concurrency issues)
xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | grep -E "error:|warning:" | grep -v "ONLY_ACTIVE_ARCH" | grep -v "Run script" | grep -v "lstat.*Highlightr" | tee /tmp/tamagotchai-build.txt

# Format check (verify formatting is clean after auto-fix)
swiftformat --lint --config .swiftformat tamagotchai/Sources 2>&1 | tee /tmp/tamagotchai-format.txt
```

## Step 3: Collect and Group Errors

Parse the output from all three commands. Group errors into these domains:

- **Build errors**: Compile errors from xcodebuild (type mismatches, missing imports, concurrency violations, undeclared identifiers)
- **Lint errors**: SwiftLint violations (force_unwrapping, missing_docs, line_length, etc.)
- **Format errors**: Any remaining SwiftFormat issues not auto-fixed

If all three commands pass cleanly with zero errors and zero warnings, report success and stop.

## Step 4: Spawn Parallel Agents

For each domain that has issues, use the `subagent` tool to spawn a sub-agent to fix all errors in that domain. Include the full error output and specific file paths in each agent's task.

**Build errors agent prompt must include:**
- The exact error messages with file paths and line numbers
- Instruction to read each file before editing
- Instruction to re-run: `xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | grep "error:"` after fixes

**Lint errors agent prompt must include:**
- The exact SwiftLint violations with file paths and line numbers
- Instruction to read each file before editing
- Instruction to re-run: `swiftlint lint --config .swiftlint.yml` after fixes
- Note: Do NOT disable rules or add `swiftlint:disable` comments — fix the actual code

**Format errors agent prompt must include:**
- The exact files with issues
- Instruction to run: `swiftformat --config .swiftformat tamagotchai/Sources` to auto-fix

## Step 5: Verify

After all agents complete, re-run all three checks:

```bash
swiftformat --lint --config .swiftformat tamagotchai/Sources
swiftlint lint --config .swiftlint.yml --reporter emoji
xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | grep -E "error:|warning:" | grep -v "ONLY_ACTIVE_ARCH" | grep -v "Run script" | grep -v "lstat.*Highlightr"
```

If any issues remain, fix them directly (don't spawn more agents). Report final status.
