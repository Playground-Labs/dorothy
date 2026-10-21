#!/bin/bash
# Usage: scripts/release.sh <version>  (e.g. 1.1)
# Notarized build → Sparkle-signed zip + appcast.xml → tag v<version> → GitHub release with both as assets.
set -euo pipefail
cd "$(dirname "$0")/.."

V=${1:?usage: scripts/release.sh <version>}
[[ -z $(git status --porcelain) ]] || { echo "working tree is dirty; commit first" >&2; exit 1; }
# Fail before the ~15 min notarize: tag taken, gh logged out, or build number not above the live appcast's.
! git rev-parse -q --verify "refs/tags/v$V" >/dev/null && [[ -z $(git ls-remote --tags origin "v$V") ]] || { echo "tag v$V already exists" >&2; exit 1; }
gh auth status >/dev/null
LIVE=$(gh release download --pattern appcast.xml -O - 2>/dev/null | sed -n 's|.*<sparkle:version>\(.*\)</sparkle:version>.*|\1|p' || true)
(( $(git rev-list --count HEAD) > ${LIVE:-0} )) || { echo "build number must exceed live build $LIVE; release from a newer commit on main" >&2; exit 1; }

VERSION=$V scripts/bundle.sh --release
BUILD=$(plutil -extract CFBundleVersion raw -o - build/Dorothy.app/Contents/Info.plist)
SIG=$(.build/artifacts/sparkle/Sparkle/bin/sign_update --ed-key-file ~/.sparkle/dorothy_ed25519_private_key build/Dorothy.zip)  # sparkle:edSignature="…" length="…"

cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
    <title>Dorothy</title>
    <item>
        <title>Dorothy $V</title>
        <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
        <sparkle:version>$BUILD</sparkle:version>
        <sparkle:shortVersionString>$V</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        <enclosure url="https://github.com/Playground-Labs/dorothy/releases/download/v$V/Dorothy.zip" type="application/octet-stream" $SIG/>
    </item>
</channel>
</rss>
XML

git tag "v$V"
git push origin "v$V"
gh release create "v$V" build/Dorothy.zip build/appcast.xml --verify-tag --title "Dorothy $V" --generate-notes
