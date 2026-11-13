#!/usr/bin/env bash
set -euo pipefail

# Pin the source revision so builds remain reproducible if upstream main moves.
readonly source_revision="5a430db1abf4c4545c88c717b9eaebb1d789a0ae"
readonly source_base="https://raw.githubusercontent.com/Thanas-R/Thanas-OS/${source_revision}/src/assets"
readonly destination="assets/wallpapers"

mkdir -p "${destination}"

fetch_wallpaper() {
  local name="$1"
  local expected_bytes="$2"
  local output="${destination}/${name}"

  curl --fail --silent --show-error --location --retry 3 \
    "${source_base}/${name}" --output "${output}"

  test -s "${output}"
  local actual_bytes
  actual_bytes="$(wc -c < "${output}" | tr -d ' ')"
  if [[ "${actual_bytes}" != "${expected_bytes}" ]]; then
    echo "Unexpected size for ${name}: ${actual_bytes} bytes" >&2
    exit 1
  fi

  local header
  header="$(od -An -tx1 -N2 "${output}" | tr -d ' \n')"
  if [[ "${header}" != "ffd8" ]]; then
    echo "${name} is not a JPEG file" >&2
    exit 1
  fi
  echo "Fetched ${name} (${actual_bytes} bytes)"
}

fetch_wallpaper "wallpaper-bigsur.jpg" "3104184"
fetch_wallpaper "wallpaper-tahoe.jpg" "2747201"
