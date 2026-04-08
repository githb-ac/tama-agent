---
name: fix
description: Run linting, formatting checks, and build, then spawn parallel agents to fix all issues
---

# Project Code Quality Check

This command runs all linting, formatting, and build checks for this Swift/macOS project, collects errors, groups them by domain, and spawns parallel agents to fix them.

## Step 1: Run Linting, Formatting, and Build Checks

Run all three checks and capture their output:

```bash
# Lint
swiftlint lint --config .swiftlint.yml 2>&1

# Format check (dry run)
swiftformat --lint --config .swiftformat tamagotchai/Sources 2>&1

# Build
xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1
```

## Step 2: Collect and Parse Errors

Parse the output from all three commands. Group errors by domain:
- **Lint errors**: SwiftLint warnings and errors (style, convention, performance rules)
- **Format errors**: SwiftFormat violations (indentation, spacing, trailing commas)
- **Build errors**: Xcode build failures (type errors, missing imports, syntax errors)

Create a list of all files with issues and the specific problems in each file.

## Step 3: Spawn Parallel Agents

For each domain that has issues, spawn an agent in parallel using the Agent tool:

**IMPORTANT**: Use a SINGLE response with MULTIPLE Agent tool calls to run agents in parallel.

- Spawn a "lint-fixer" agent for SwiftLint errors — fix violations and re-run `swiftlint lint --config .swiftlint.yml` to verify
- Spawn a "format-fixer" agent for SwiftFormat errors — run `swiftformat --config .swiftformat tamagotchai/Sources` to auto-fix, then verify with `swiftformat --lint --config .swiftformat tamagotchai/Sources`
- Spawn a "build-fixer" agent for build errors — fix type errors, missing imports, etc. and re-run `xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build` to verify

Each agent should:
1. Receive the list of files and specific errors in their domain
2. Fix all errors in their domain
3. Run the relevant check command to verify fixes
4. Report completion

## Step 4: Verify All Fixes

After all agents complete, run the full check suite again to ensure all issues are resolved:

```bash
swiftlint lint --config .swiftlint.yml 2>&1
swiftformat --lint --config .swiftformat tamagotchai/Sources 2>&1
xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1
```
