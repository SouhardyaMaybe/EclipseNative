#!/usr/bin/env bash
# Download and verify every source archive named in sources.lock.json.
#
# Archives are cached by SHA-256 and extracted into .build/src/<name>. An
# existing tree is reused only when its marker matches the locked digest, so a
# lock change forces a clean re-extract. Any mismatch is fatal.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/scripts/lib.sh"

MARKER_DIR="$BUILD_ROOT/markers"
mkdir -p "$SOURCE_DIR" "$CACHE_DIR" "$MARKER_DIR"

for name in $(python3 "$LOCK" --names); do
    url="$(lock_field "$name" url)"
    sha="$(lock_field "$name" sha256)"
    dest="$SOURCE_DIR/$name"
    marker="$MARKER_DIR/$name.sha256"

    if [ -f "$marker" ] && [ "$(cat "$marker")" = "$sha" ] && [ -d "$dest" ]; then
        note "$name: cached"
        continue
    fi

    archive="$CACHE_DIR/$name-$sha.tar.gz"
    if [ ! -f "$archive" ] || ! printf '%s  %s\n' "$sha" "$archive" | sha256sum -c --quiet - 2>/dev/null; then
        note "$name: downloading $url"
        rm -f "$archive" "$archive.part"
        curl -fsSL --retry 4 --retry-delay 5 --connect-timeout 20 \
            -o "$archive.part" "$url"
        mv "$archive.part" "$archive"
    else
        note "$name: archive cached"
    fi

    printf '%s  %s\n' "$sha" "$archive" | sha256sum -c --quiet -

    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xzf "$archive" -C "$dest" --strip-components=1 --no-same-owner
    printf '%s\n' "$sha" > "$marker"
    note "$name: extracted"
done

note "sources ready in $SOURCE_DIR"
