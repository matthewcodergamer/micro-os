#!/usr/bin/env bash
# =============================================================================
# Fetches the two binary payloads the APK bundles:
#
#   assets/rootfs/rootfs.tar.gz  minimal Ubuntu 24.04 arm64 rootfs (~30 MB)
#   assets/proot/*               proot + loader + libs from Termux (arm64)
#
# Both are fetched at build time so the git repository stays source-only.
# Runs on the CI runner (ubuntu-latest) where dpkg-deb is available.
#
# Every URL is tried in order and the result is validated before it is accepted,
# so one dead mirror cannot break the build.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/assets/rootfs" "$ROOT/assets/proot"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ROOTFS_OUT="$ROOT/assets/rootfs/rootfs.tar.gz"

# Ubuntu base tarballs may or may not prefix members with "./", so match both.
valid_rootfs() {
  tar -tzf "$1" 2>/dev/null | grep -qE '^(\./)?etc/os-release$'
}

# -----------------------------------------------------------------------------
# 1. Ubuntu base rootfs
# -----------------------------------------------------------------------------
if [ -s "$ROOTFS_OUT" ] && valid_rootfs "$ROOTFS_OUT"; then
  echo "==> rootfs already present ($(du -h "$ROOTFS_OUT" | cut -f1))"
else
  ROOTFS_URLS=(
    "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-arm64.tar.gz"
    "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.2-base-arm64.tar.gz"
    "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.1-base-arm64.tar.gz"
    "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04-base-arm64.tar.gz"
    "https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-arm64.tar.gz"
  )

  fetched=""
  for url in "${ROOTFS_URLS[@]}"; do
    echo "==> trying $url"
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$TMP/rootfs.tar.gz" "$url"; then
      if valid_rootfs "$TMP/rootfs.tar.gz"; then
        mv "$TMP/rootfs.tar.gz" "$ROOTFS_OUT"
        fetched="$url"
        break
      fi
      echo "!! archive failed validation, trying next mirror"
    fi
  done

  [ -n "$fetched" ] || { echo "!! could not download a usable rootfs"; exit 1; }
  echo "==> rootfs from $fetched"
fi

# -----------------------------------------------------------------------------
# 2. proot (Termux arm64 packages)
# -----------------------------------------------------------------------------
if [ -x "$ROOT/assets/proot/proot" ] && [ -x "$ROOT/assets/proot/loader" ]; then
  echo "==> proot already present"
else
  MIRRORS=(
    "https://packages.termux.dev/apt/termux-main"
    "https://mirror.termux.dev/apt/termux-main"
    "https://grimler.se/termux/termux-main"
  )

  mirror=""
  for candidate in "${MIRRORS[@]}"; do
    echo "==> probing $candidate"
    if curl -fsSL --connect-timeout 20 "$candidate/dists/stable/main/binary-aarch64/Packages.gz" \
         -o "$TMP/Packages.gz"; then
      mirror="$candidate"
      break
    fi
  done

  [ -n "$mirror" ] || { echo "!! no Termux mirror reachable"; exit 1; }

  gunzip -f "$TMP/Packages.gz"
  echo "==> using $mirror"

  pkg_path() {
    awk -v pkg="$1" '
      /^Package: / { name=$2 }
      name==pkg && /^Filename: / { print $2; exit }
    ' "$TMP/Packages"
  }

  fetch_deb() {
    local name="$1"
    local rel
    rel="$(pkg_path "$name")"
    if [ -z "$rel" ]; then echo "!! package not found: $name" >&2; exit 1; fi
    echo "    $name -> $rel"
    curl -fsSL --retry 3 "$mirror/$rel" -o "$TMP/$name.deb"
    mkdir -p "$TMP/$name"
    dpkg-deb -x "$TMP/$name.deb" "$TMP/$name"
  }

  fetch_deb proot
  fetch_deb libtalloc
  fetch_deb libandroid-shmem

  PREFIX="data/data/com.termux/files/usr"

  install -m 755 "$TMP/proot/$PREFIX/bin/proot"              "$ROOT/assets/proot/proot"
  install -m 755 "$TMP/proot/$PREFIX/libexec/proot/loader"   "$ROOT/assets/proot/loader"
  install -m 644 "$TMP/libtalloc/$PREFIX/lib/libtalloc.so.2" "$ROOT/assets/proot/libtalloc.so.2"
  install -m 644 "$TMP/libandroid-shmem/$PREFIX/lib/libandroid-shmem.so" \
                "$ROOT/assets/proot/libandroid-shmem.so"
fi

# -----------------------------------------------------------------------------
# 3. Report
# -----------------------------------------------------------------------------
echo "==> bundled runtime:"
ls -lh "$ROOTFS_OUT" "$ROOT/assets/proot"
