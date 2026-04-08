---
name: release
description: Tag and trigger GitHub Actions workflow to build and release a new version of Tama
---

Create a new GitHub release using the GitHub Actions workflow.

The workflow (`.github/workflows/release.yml`) automatically:
- Builds the signed Release binary
- Deep signs all nested frameworks
- Notarizes the app
- Creates a DMG with `create-dmg`
- Notarizes the DMG
- Creates the GitHub release with auto-generated notes

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

Pushing a tag matching `v*` triggers the release workflow:

```bash
git tag <VERSION>
git push origin <VERSION>
```

## Step 4: Monitor Workflow

The workflow will start automatically. Monitor its progress:

```bash
gh run list --workflow=release.yml --limit 1
```

To watch the live logs:
```bash
gh run watch $(gh run list --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

Or open in browser:
```bash
gh run view --web $(gh run list --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

## Step 5: Verify Release

Once the workflow completes successfully, verify the release:

```bash
gh release view <VERSION> --json url,tagName,assets
```

The release should include:
- A notarized DMG asset (`Tamagotchai-<VERSION>.dmg`)
- Auto-generated release notes

Report the release URL and asset details to the user.

## Troubleshooting

If the workflow fails:
1. Check the logs: `gh run view <RUN_ID>`
2. Common issues:
   - Certificate expiration
   - Notarization timeout
   - Code signing errors
3. Fix the issue, delete the tag, and retry:
   ```bash
   git tag -d <VERSION>
   git push origin --delete <VERSION>
   ```
