#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBRARY_SOURCE_DIR="$PROJECT_DIR/lib_wishboxcdekapiclient"
LIBRARY_MANIFEST_PATH="$LIBRARY_SOURCE_DIR/lib_wishboxcdekapiclient.xml"
PACKAGE_MANIFEST_PATH="$PROJECT_DIR/pkg_wishboxcdekapiclient.xml"
PACKAGE_SCRIPT_PATH="$PROJECT_DIR/script.php"
SOURCE_CODE_DIR="${WISHBOXCDEK_SOURCE_DIR:-$PROJECT_DIR/../wishboxcdek/src}"

LIBRARY_BASENAME="lib_wishboxcdekapiclient"
PACKAGE_BASENAME="pkg_wishboxcdekapiclient"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${PACKAGE_BASENAME}-build.XXXXXX")"
LIBRARY_STAGE_DIR="$BUILD_DIR/library"
PACKAGE_STAGE_DIR="$BUILD_DIR/package"

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

cleanup() {
    rm -rf -- "$BUILD_DIR"
}

fail() {
    printf '%bERROR:%b %s\n' "$RED" "$RESET" "$1" >&2
    exit 1
}

manifest_version() {
    sed -n 's/.*<version>[[:space:]]*\([^<][^<]*\)[[:space:]]*<\/version>.*/\1/p' "$1" \
        | head -n 1
}

trap cleanup EXIT

[[ -d "$LIBRARY_SOURCE_DIR" ]] || fail "Library source directory not found: $LIBRARY_SOURCE_DIR"
[[ -f "$LIBRARY_MANIFEST_PATH" ]] || fail "Joomla library manifest not found: $LIBRARY_MANIFEST_PATH"
[[ -f "$PACKAGE_MANIFEST_PATH" ]] || fail "Joomla package manifest not found: $PACKAGE_MANIFEST_PATH"
[[ -f "$PACKAGE_SCRIPT_PATH" ]] || fail "Joomla package installer script not found: $PACKAGE_SCRIPT_PATH"
[[ -d "$SOURCE_CODE_DIR" ]] || fail "Wishbox CDEK source directory not found: $SOURCE_CODE_DIR"

command -v zip >/dev/null 2>&1 || fail "The zip command is required"

PACKAGE_VERSION="$(manifest_version "$PACKAGE_MANIFEST_PATH")"
[[ -n "$PACKAGE_VERSION" ]] || fail "Package version not found in $PACKAGE_MANIFEST_PATH"

VERSIONED_ARCHIVE_PATH="$PROJECT_DIR/${PACKAGE_BASENAME}_${PACKAGE_VERSION}.zip"

# Build the Joomla library archive that will be embedded in the package.
mkdir -p "$LIBRARY_STAGE_DIR/src" "$PACKAGE_STAGE_DIR"
cp -a -- "$LIBRARY_MANIFEST_PATH" "$LIBRARY_STAGE_DIR/"
cp -a -- "$SOURCE_CODE_DIR/." "$LIBRARY_STAGE_DIR/src/"

find "$LIBRARY_STAGE_DIR" -name '.DS_Store' -delete
find "$LIBRARY_STAGE_DIR" -name '._*' -delete

if command -v dot_clean >/dev/null 2>&1; then
    dot_clean "$LIBRARY_STAGE_DIR" 2>/dev/null || true
fi

if command -v xattr >/dev/null 2>&1; then
    xattr -rc "$LIBRARY_STAGE_DIR" 2>/dev/null || true
fi

(
    cd "$LIBRARY_STAGE_DIR"
    COPYFILE_DISABLE=1 zip -X -q -r "$PACKAGE_STAGE_DIR/${LIBRARY_BASENAME}.zip" .
)

# Build the installable Joomla package around the library archive.
cp -a -- "$PACKAGE_MANIFEST_PATH" "$PACKAGE_STAGE_DIR/"
cp -a -- "$PACKAGE_SCRIPT_PATH" "$PACKAGE_STAGE_DIR/"

rm -f -- "$VERSIONED_ARCHIVE_PATH"

(
    cd "$PACKAGE_STAGE_DIR"
    COPYFILE_DISABLE=1 zip -X -q -r "$VERSIONED_ARCHIVE_PATH" .
)

if command -v shasum >/dev/null 2>&1; then
    SHA256="$(shasum -a 256 "$VERSIONED_ARCHIVE_PATH" | awk '{print $1}')"
elif command -v openssl >/dev/null 2>&1; then
    SHA256="$(openssl dgst -sha256 "$VERSIONED_ARCHIVE_PATH" | sed 's/^.*= //')"
else
    SHA256="unavailable"
fi

printf '%bOK:%b package -> %s\n' "$GREEN" "$RESET" "$VERSIONED_ARCHIVE_PATH"
printf '%bOK:%b sha256 -> %s\n' "$GREEN" "$RESET" "$SHA256"
