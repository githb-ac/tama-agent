---
name: release
description: Build, tag, and release a new version of Tama
---

Create a new GitHub release with signed build and DMG.

## Step 1: Verify Clean State

Check everything is committed:
```bash
git status
```

If there are uncommitted changes, commit them first using `/commit`.

## Step 2: Bump Version

Get the latest tag and automatically bump the patch version:
```bash
LATEST=$(git tag --sort=-version:refname | head -1 | sed 's/^v//')
MAJOR=$(echo $LATEST | cut -d. -f1)
MINOR=$(echo $LATEST | cut -d. -f2)
PATCH=$(echo $LATEST | cut -d. -f3)
NEW_PATCH=$((PATCH + 1))
VERSION="v${MAJOR}.${MINOR}.${NEW_PATCH}"
echo "Bumping: $LATEST -> $VERSION"
```

Use this computed VERSION for all subsequent steps. If the user wants a minor or major bump instead, adjust accordingly (e.g., v2.1.0 or v3.0.0).

## Step 3: Create and Push Tag

```bash
git tag <VERSION>
git push origin <VERSION>
```

## Step 4: Build Release

Build the signed Release binary:
```bash
xcodebuild -project Tama.xcodeproj \
  -scheme Tama \
  -configuration Release \
  -arch arm64 \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application: INDIANA RUSTAN DI (396M7LY29W)" \
  DEVELOPMENT_TEAM=396M7LY29W \
  "OTHER_CODE_SIGN_FLAGS=--options runtime" \
  clean build
```

Verify the build succeeded and the app is signed:
```bash
codesign -dv --verbose=4 build/Build/Products/Release/Tama.app 2>&1 | grep -E "(Signed|Authority|Signature)"
```

## Step 5: Create DMG

Create a compressed DMG from the signed app:
```bash
hdiutil create -volname "Tama" \
  -srcfolder build/Build/Products/Release/Tama.app \
  -ov -format UDZO \
  build/Tama-<VERSION>.dmg
```

## Step 6: Generate Release Notes

Get commits since last tag for release notes:
```bash
git log <PREVIOUS_VERSION>..<VERSION> --oneline
```

Generate a summary of changes organized by category (Features, Fixes, Improvements).

## Step 7: Create GitHub Release

Create the release with notes:
```bash
gh release create <VERSION> \
  --title "<VERSION>" \
  --notes "Generated release notes here"
```

Upload the DMG:
```bash
gh release upload <VERSION> build/Tama-<VERSION>.dmg --clobber
```

## Step 8: Verify

Confirm the release is live:
```bash
gh release view <VERSION> --json url,assets
```

Report the release URL and asset details to the user.
