---
name: commit
description: Run quality checks, commit with AI message, and push
---

1. **Auto-format then check:**
   ```bash
   swiftformat --config .swiftformat tamagotchai/Sources
   swiftlint lint --config .swiftlint.yml --quiet
   xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug build 2>&1 | grep "error:" | grep -v "lstat.*Highlightr"
   ```
   If any errors, fix them all before continuing. Warnings are acceptable.

2. **Review changes:** run `git status`, `git diff`, and `git diff --staged` to understand what changed.

3. **Stage relevant files** with `git add` (specific files — never `git add -A`). Only stage files related to the current work.

4. **Generate a commit message:** start with a verb (Add/Update/Fix/Remove/Refactor), be specific and concise, one line. If changes span multiple concerns, use a summary line plus bullet points.

5. **Commit and push:**
   ```bash
   git commit -m "your generated message"
   git push
   ```
