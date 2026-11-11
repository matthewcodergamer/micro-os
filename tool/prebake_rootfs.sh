#!/usr/bin/env bash
# Build a fully provisioned Ubuntu ARM64 guest on the native ARM64 CI runner.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/rootfs/rootfs.tar.gz"
TMP="$(mktemp -d)"
NAME="microos-rootfs-prebake-$GITHUB_RUN_ID"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT
mkdir -p "$(dirname "$OUT")"

echo "==> Provisioning Ubuntu 24.04 ARM64 in native Docker"
docker run --platform linux/arm64 --name "$NAME" \
  -v "$ROOT/tool/setup.sh:/tmp/microos-setup.sh:ro" \
  ubuntu:24.04 /bin/bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    mkdir -p /root/.microos
    cp /tmp/microos-setup.sh /root/.microos/setup.sh
    chmod 755 /root/.microos/setup.sh
    bash /root/.microos/setup.sh

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
    # Do not use grep -q here: with pipefail it can SIGPIPE tar (exit 141).
    tar -tJf /tmp/firefox.tar.xz | grep -x "firefox/firefox" >/dev/null
    mkdir -p /opt
    tar -xJf /tmp/firefox.tar.xz -C /opt
    ln -sf /opt/firefox/firefox /usr/local/bin/firefox
    file /opt/firefox/firefox | grep -i "ARM aarch64" >/dev/null
    /opt/firefox/firefox --version

    rm -f /tmp/firefox.tar.xz /root/.microos/setup.sh
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
    if [ -d /usr/share/locale ]; then
      find /usr/share/locale -mindepth 1 -maxdepth 1 \
        ! -name en ! -name en_US ! -name C -exec rm -rf {} + || true
    fi
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
    touch /root/.microos/ready
    echo "==> Pre-baked guest ready"
  '

echo "==> Exporting prepared root filesystem"
docker export "$NAME" -o "$TMP/rootfs.tar"
mkdir -p "$TMP/rootfs"
tar -xf "$TMP/rootfs.tar" -C "$TMP/rootfs"

python3 - "$TMP/rootfs" <<'PY'
import os, posixpath, sys
root = os.path.abspath(sys.argv[1])
for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
    for name in dirs + files:
        path = os.path.join(current, name)
        if os.path.islink(path):
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

tar --hard-dereference --numeric-owner --owner=0 --group=0 \
  -czf "$OUT" -C "$TMP/rootfs" .
# Avoid grep -q with a streaming tar producer under pipefail.
tar -tzf "$OUT" | grep -xE '(\./)?root/\.microos/ready' >/dev/null
tar -tzf "$OUT" | grep -xE '(\./)?opt/firefox/firefox' >/dev/null
echo "==> Pre-baked ARM64 rootfs: $(du -h "$OUT" | cut -f1)"
