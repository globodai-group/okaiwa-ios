#!/usr/bin/env bash
#
# set-ios-build-number.sh
# -----------------------
# Keep CFBundleVersion in sync with the git commit count, matching the
# Android scheme (versionCode = `git rev-list --count HEAD`).
#
# Wire this into the Xcode scheme as a pre-action OR as a "Run Script"
# build phase placed BEFORE the "Copy Bundle Resources" phase so the
# rewritten Info.plist is picked up in the final IPA.
#
# Example build phase script (paste into Xcode):
#   "${SRCROOT}/scripts/set-ios-build-number.sh"
#
# Outside of a git checkout the script falls back to "1" so archive
# builds from a tarball still succeed.
#
set -euo pipefail

# Locate the repo root. When called as a build phase Xcode sets SRCROOT.
REPO_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"

# Compute the monotonic build number from git history.
if git rev-parse --git-dir > /dev/null 2>&1; then
  BUILD_NUMBER=$(git rev-list --count HEAD)
else
  BUILD_NUMBER=1
fi

# Info.plist is passed via $INFOPLIST_FILE when run from Xcode.
# Fall back to the well-known path for manual runs.
INFOPLIST="${INFOPLIST_FILE:-$REPO_ROOT/Okaiwa/App/Info.plist}"

if [[ ! -f "$INFOPLIST" ]]; then
  echo "error: Info.plist not found at $INFOPLIST" >&2
  exit 1
fi

# Rewrite CFBundleVersion in place. PlistBuddy is always available on
# macOS build agents (system framework, no brew install required).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFOPLIST"

echo "→ CFBundleVersion set to $BUILD_NUMBER (from git rev-list --count HEAD)"
