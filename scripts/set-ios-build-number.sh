#!/usr/bin/env bash
#
# set-ios-build-number.sh
# -----------------------
# Keep version numbers in sync with the git commit count, matching
# the Android scheme exactly:
#   versionCode  ↔ CFBundleVersion            = git rev-list --count HEAD
#   versionName  ↔ CFBundleShortVersionString = {MAJOR}.{MINOR}.{count}
#
# Wire this into the Xcode scheme as a pre-action OR as a "Run Script"
# build phase placed BEFORE the "Copy Bundle Resources" phase so the
# rewritten Info.plist is picked up in the final IPA.
#
# Outside of a git checkout the script falls back to 1 so archive
# builds from a tarball still succeed.
#
set -euo pipefail

# Manual major/minor — bump for user-facing milestones. Keep in sync
# with okaiwaMajor / okaiwaMinor in okaiwa-android/app/build.gradle.kts.
readonly OKAIWA_MAJOR=1
readonly OKAIWA_MINOR=0

# Locate the repo root. When called as a build phase Xcode sets SRCROOT.
REPO_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"

# Monotonic build number from git history.
if git rev-parse --git-dir > /dev/null 2>&1; then
  BUILD_NUMBER=$(git rev-list --count HEAD)
else
  BUILD_NUMBER=1
fi

MARKETING_VERSION="${OKAIWA_MAJOR}.${OKAIWA_MINOR}.${BUILD_NUMBER}"

# Info.plist is passed via $INFOPLIST_FILE when run from Xcode.
# Fall back to the well-known path for manual runs.
INFOPLIST="${INFOPLIST_FILE:-$REPO_ROOT/Okaiwa/App/Info.plist}"

if [[ ! -f "$INFOPLIST" ]]; then
  echo "error: Info.plist not found at $INFOPLIST" >&2
  exit 1
fi

# Rewrite both fields in place. PlistBuddy is always available on
# macOS build agents (system framework, no brew install required).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFOPLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MARKETING_VERSION" "$INFOPLIST"

echo "→ CFBundleShortVersionString = $MARKETING_VERSION"
echo "→ CFBundleVersion            = $BUILD_NUMBER"
