#!/usr/bin/env bash
# Fetch the pinned, OFL-licensed JetBrains Mono faces used by the Flutter
# terminal renderer. Kept separate so local builds and CI use identical files.
set -euo pipefail

VERSION="v2.304"
BASE_URL="https://raw.githubusercontent.com/JetBrains/JetBrainsMono/${VERSION}"
FONT_DIR="assets/fonts"
mkdir -p "${FONT_DIR}"

curl --fail --location --silent --show-error --retry 3 \
  "${BASE_URL}/fonts/ttf/JetBrainsMono-Regular.ttf" \
  --output "${FONT_DIR}/JetBrainsMono-Regular.ttf"
curl --fail --location --silent --show-error --retry 3 \
  "${BASE_URL}/fonts/ttf/JetBrainsMono-Bold.ttf" \
  --output "${FONT_DIR}/JetBrainsMono-Bold.ttf"
curl --fail --location --silent --show-error --retry 3 \
  "${BASE_URL}/OFL.txt" --output "${FONT_DIR}/OFL.txt"

test -s "${FONT_DIR}/JetBrainsMono-Regular.ttf"
test -s "${FONT_DIR}/JetBrainsMono-Bold.ttf"
test -s "${FONT_DIR}/OFL.txt"
file "${FONT_DIR}/JetBrainsMono-Regular.ttf" "${FONT_DIR}/JetBrainsMono-Bold.ttf"
echo "JetBrains Mono ${VERSION} fonts downloaded and verified."
