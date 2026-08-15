#!/bin/sh

# Based on the KindleForge KOReader installer.  KPM invokes this from the
# unpacked package directory, so CHANNEL is part of this signed package.
set -eu

REPOSITORY="m-tky/koreader-tategumi"
PACKAGE_ID="koreader-tategumi"
CHANNEL="$(cat ./channel)"
TMP_ARCHIVE="/mnt/us/kmc/kpm/tmp/${PACKAGE_ID}.targz"

mkdir -p /mnt/us/kmc/kpm/tmp

if [ -f /lib/ld-linux-armhf.so.3 ]; then
    TARGET="kindlehf"
else
    TARGET="kindlepw2"
fi

if [ "$CHANNEL" = "nightly" ]; then
    RELEASE_TAG="nightly"
    ASSET="koreader-${TARGET}-latest-nightly.targz"
else
    RELEASE_TAG="$(curl -fsSL "https://api.github.com/repos/${REPOSITORY}/releases/latest" | sed -n 's/^[[:space:]]*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    if [ -z "$RELEASE_TAG" ]; then
        echo "Could not determine the latest KOReader Tategumi release."
        exit 1
    fi
    ASSET="koreader-${TARGET}-${RELEASE_TAG}.targz"
fi

URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}/${ASSET}"

echo "Installing KOReader Tategumi (${CHANNEL}, ${TARGET})..."
curl -fL --retry 3 "$URL" -o "$TMP_ARCHIVE"

# The existing Kindle release archive owns the koreader and extensions trees.
# Keep the extensions tree: it is harmless on hdnext and preserves compatibility
# with devices that still have KUAL installed.
tar -xzf "$TMP_ARCHIVE" -C /mnt/us
rm -f "$TMP_ARCHIVE"

cp './scriptlets/KOReader Tategumi.sh' '/mnt/us/documents/KOReader Tategumi.sh'
chmod 755 '/mnt/us/documents/KOReader Tategumi.sh'

echo "KOReader Tategumi installation complete."
