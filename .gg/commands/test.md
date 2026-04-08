# /test — Run All Tests

Run the full test suite, collect failures, and fix them.

## Steps

1. Run the test suite:
```bash
cd /Users/kenkai/Documents/UnstableMind/tamagotchai && xcodebuild -project Tamagotchai.xcodeproj -scheme Tamagotchai -configuration Debug test -destination 'platform=macOS' 2>&1 | grep -E '(✔|✘|Test run|TEST SUCCEEDED|TEST FAILED|error:.*\.swift:\d)' | grep -v '(wrap)\|(consecutiveBlankLines)\|(consecutiveSpaces)\|(redundantSelf)\|(preferCountWhere)\|(semicolons)\|(braces)\|(indent)\|Type Body Length'
```

2. If all tests pass, report the summary and stop.

3. If any tests fail:
   - Collect the failing test names and error messages
   - For each failing test, read the test file and the source file it tests
   - Diagnose the root cause (test bug vs source bug)
   - Fix the issue
   - Re-run the test suite to confirm the fix

4. If there are compilation errors in test files:
   - Read the failing test file
   - Fix the compilation error
   - Re-run

5. Repeat until all tests pass.
