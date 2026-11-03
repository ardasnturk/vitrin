#!/usr/bin/env bash
# Writes a notarized DMG built by scripts/build-mac.sh into the Homebrew cask and, once the release exists, attaches it.
#
#   scripts/prepare-release.sh           # the cask only: before tagging
#   scripts/prepare-release.sh --upload  # the DMG on the release: after the tag's Release workflow finished
#
# The Release workflow creates the GitHub Release from the tag; this script never publishes one.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*: *"?([0-9.]+)"?.*/\1/')"
TAG="v$VERSION"
DMG="dist/Vitrin-$VERSION.dmg"
CASK="../../Casks/vitrin.rb"

[[ -f "$DMG" ]] || { echo "Missing $DMG: run scripts/build-mac.sh first" >&2; exit 1; }
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
grep -q "$SHA" "$DMG.sha256" || { echo "$DMG.sha256 does not match the DMG: rebuild" >&2; exit 1; }
xcrun stapler validate "$DMG" >/dev/null || { echo "$DMG has no stapled notarization ticket: run scripts/build-mac.sh" >&2; exit 1; }

if [[ "${1:-}" == "--upload" ]]; then
  gh release view "$TAG" >/dev/null || { echo "The release $TAG doesn't exist yet: wait for the Release workflow" >&2; exit 1; }
  gh release upload "$TAG" "$DMG" "$DMG.sha256" --clobber
  echo "✔ $DMG is on $TAG"
  exit 0
fi

echo "▸ Updating $CASK → $VERSION ($SHA)"
python3 - "$CASK" "$VERSION" "$SHA" <<'PY'
import re, sys
path, version, sha = sys.argv[1:]
text = open(path, encoding="utf-8").read()
text = re.sub(r'version "[^"]*"', f'version "{version}"', text, count=1)
text = re.sub(r'sha256 (:no_check|"[0-9a-f]*")', f'sha256 "{sha}"', text, count=1)
open(path, "w", encoding="utf-8").write(text)
PY
echo "✔ Commit the cask, then tag $TAG: see docs/RELEASE.md"
