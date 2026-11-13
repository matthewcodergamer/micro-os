#!/usr/bin/env bash
set -euo pipefail

# Pin the source revision so builds remain reproducible if upstream main moves.
readonly source_revision="5a430db1abf4c4545c88c717b9eaebb1d789a0ae"
readonly source_base="https://raw.githubusercontent.com/Thanas-R/Thanas-OS/${source_revision}/src/assets"
readonly destination="assets/wallpapers"

mkdir -p "${destination}"

fetch_wallpaper() {
  local source_name="$1"
  local output_name="$2"
  local expected_bytes="$3"
  local expected_header="$4"
  local output="${destination}/${output_name}"

  curl --fail --silent --show-error --location --retry 3 \
    "${source_base}/${source_name}" --output "${output}"

  test -s "${output}"
  local actual_bytes
  actual_bytes="$(wc -c < "${output}" | tr -d ' ')"
  if [[ "${actual_bytes}" != "${expected_bytes}" ]]; then
    echo "Unexpected size for ${source_name}: ${actual_bytes} bytes" >&2
    exit 1
  fi

  local header
  header="$(od -An -tx1 -N8 "${output}" | tr -d ' \n')"
  if [[ "${header}" != "${expected_header}"* ]]; then
    echo "${source_name} has an unexpected image signature: ${header}" >&2
    exit 1
  fi
  echo "Fetched ${source_name} as ${output_name} (${actual_bytes} bytes)"
}

# Upstream labels this PNG file with a .jpg extension. Store it with the
# correct local extension so Flutter tooling and humans see the real format.
fetch_wallpaper "wallpaper-bigsur.jpg" "wallpaper-bigsur.png" "3104184" "89504e470d0a1a0a"
fetch_wallpaper "wallpaper-tahoe.jpg" "wallpaper-tahoe.jpg" "2747201" "ffd8"
