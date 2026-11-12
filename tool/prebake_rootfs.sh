#!/usr/bin/env bash
# Build a fully provisioned Ubuntu ARM64 guest on the CI runner.
# Runs on a native ARM64 GitHub Actions runner; Docker executes ARM64 natively.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/rootfs/rootfs.tar.gz"
TMP="$(mktemp -d)"
NAME="microos-rootfs-prebake-$GITHUB_RUN_ID"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$OUT")"

echo "==> Provisioning Ubuntu 24.04 ARM64 in Docker"
docker run --platform linux/arm64 --name "$NAME" \
  -v "$ROOT/tool/setup.sh:/tmp/microos-setup.sh:ro" \
  ubuntu:24.04 /bin/bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /root/.microos
    cp /tmp/microos-setup.sh /root/.microos/setup.sh
    chmod 755 /root/.microos/setup.sh
    bash /root/.microos/setup.sh

    echo "==> Verifying the pre-baked developer workstation"
    for tool in git gh python3 node npm rustc cargo java javac jar unzip zip microos-jar; do
      command -v "$tool" >/dev/null 2>&1 || {
        echo "Required pre-baked tool is missing: $tool" >&2
        exit 1
      }
      printf '%-10s %s\n' "$tool" "$(command -v "$tool")"
    done
    if command -v opencode >/dev/null 2>&1; then
      OPENCODE_BIN="$(command -v opencode)"
    elif [ -x /root/.opencode/bin/opencode ]; then
      OPENCODE_BIN=/root/.opencode/bin/opencode
    else
      echo "OpenCode is missing from the pre-baked image" >&2
      exit 1
    fi
    timeout 30 "$OPENCODE_BIN" --version
    python3 -c "import zipfile, json, pathlib"

    echo "==> Installing official Mozilla Firefox ARM64"
    apt-get update -y
    apt-get install -y --no-install-recommends \
      libgtk-3-0t64 libdbus-glib-1-2 libxt6 libx11-xcb1 \
      libasound2t64 libpulse0 libnss3 libxcomposite1 libxdamage1 \
      libxrandr2 libgbm1 libxss1 libatk1.0-0t64 libatk-bridge2.0-0t64 \
      libcups2t64 libdrm2 libxkbcommon0 libwayland-client0 libegl1 \
      libgl1 libpango-1.0-0 libcairo2

    curl -fL --retry 3 --connect-timeout 20 \
      "https://download.mozilla.org/?lang=en-US&os=linux64-aarch64&product=firefox-latest-ssl" \
      -o /tmp/firefox.tar.xz
    tar -tJf /tmp/firefox.tar.xz > /tmp/firefox-archive.list
    grep -qx "firefox/firefox" /tmp/firefox-archive.list
    rm -f /tmp/firefox-archive.list
    mkdir -p /opt
    tar -xJf /tmp/firefox.tar.xz -C /opt
    ln -sf /opt/firefox/firefox /usr/local/bin/firefox
    # The shell launcher is a script; verify the actual ARM64 ELF binary.
    test -x /opt/firefox/firefox-bin
    file /opt/firefox/firefox-bin | grep -Eqi "ARM aarch64|ARM64"
    if ldd /opt/firefox/firefox-bin 2>&1 | tee /tmp/firefox-ldd.txt | grep -q "not found"; then
      echo "Firefox has unresolved shared-library dependencies:" >&2
      cat /tmp/firefox-ldd.txt >&2
      exit 1
    fi
    /opt/firefox/firefox --version

    # Firefox refuses to start as root. Exercise the same unprivileged account
    # and headless Gecko startup path used by MicroOS before shipping the image.
    id microos-browser
    BROWSER_HOME=/root/.microos/browser-home
    mkdir -p "$BROWSER_HOME"
    chmod 1777 "$BROWSER_HOME"
    runuser -u microos-browser -- env \
      HOME="$BROWSER_HOME" \
      MOZ_DISABLE_CONTENT_SANDBOX=1 \
      MOZ_DISABLE_GMP_SANDBOX=1 \
      timeout 90 /opt/firefox/firefox --headless --no-remote \
        --profile "$BROWSER_HOME/smoke-profile" \
        --screenshot /tmp/microos-firefox-smoke.png \
        "data:text/html,<title>MicroOS Firefox smoke test</title><h1>Firefox is ready</h1>"
    test -s /tmp/microos-firefox-smoke.png
    echo "==> Firefox ARM64 headless startup and rendering test passed"
    rm -rf "$BROWSER_HOME/smoke-profile"
    rm -f /tmp/microos-firefox-smoke.png /tmp/firefox-ldd.txt

    rm -f /tmp/firefox.tar.xz /root/.microos/setup.sh
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
    printf "2\\n" > /root/.microos/image-version
    touch /root/.microos/ready
    echo "==> Pre-baked guest ready"
  '

echo "==> Exporting the prepared root filesystem"
docker export "$NAME" -o "$TMP/rootfs.tar"
mkdir -p "$TMP/rootfs"
tar -xf "$TMP/rootfs.tar" -C "$TMP/rootfs"

# Android's toybox tar handles relative symlinks reliably. Convert absolute
# Linux guest symlinks to equivalent relative links before creating the asset.
python3 - "$TMP/rootfs" <<'PY'
import os, posixpath, sys
root = os.path.abspath(sys.argv[1])
for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
    for name in dirs + files:
        path = os.path.join(current, name)
        if not os.path.islink(path):
            continue
        target = os.readlink(path)
        if target.startswith("/"):
            rel_path = os.path.relpath(path, root).replace(os.sep, "/")
            relative = posixpath.relpath(
                posixpath.normpath(target.lstrip("/")),
                posixpath.dirname(rel_path) or ".",
            )
            os.unlink(path)
            os.symlink(relative, path)
PY

# Keep ownership metadata and ordinary files instead of hard-link records.
tar --hard-dereference --numeric-owner --owner=0 --group=0 \
  -czf "$OUT" -C "$TMP/rootfs" .

tar -tzf "$OUT" > "$TMP/rootfs-archive.list"
grep -qxE '(\./)?root/\.microos/ready' "$TMP/rootfs-archive.list"
grep -qxE '(\./)?root/\.microos/image-version' "$TMP/rootfs-archive.list"
grep -qxE '(\./)?opt/firefox/firefox' "$TMP/rootfs-archive.list"
grep -qxE '(\./)?usr/local/bin/microos-jar' "$TMP/rootfs-archive.list"
grep -qxE '(\./)?root/.opencode/bin/opencode' "$TMP/rootfs-archive.list"
echo "==> Pre-baked ARM64 rootfs: $(du -h "$OUT" | cut -f1)"
