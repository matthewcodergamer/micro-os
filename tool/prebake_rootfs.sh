#!/usr/bin/env bash
# Build a fully provisioned Ubuntu ARM64 guest on the CI runner.
# Runs on a native ARM64 GitHub Actions runner; Docker executes ARM64 natively.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/rootfs/rootfs.tar.zst"
TMP="$(mktemp -d)"
NAME="microos-rootfs-prebake-$GITHUB_RUN_ID"
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$OUT")"
command -v zstd >/dev/null 2>&1 || {
  echo "zstd is required on the ARM64 build runner" >&2
  exit 1
}

echo "==> Provisioning Ubuntu 24.04 ARM64 in Docker"
docker run --platform linux/arm64 --name "$NAME" \
  -v "$ROOT/tool/setup.sh:/tmp/microos-setup.sh:ro" \
  -v "$ROOT/tool/test-novnc-render.cjs:/tmp/test-novnc-render.cjs:ro" \
  ubuntu:24.04 /bin/bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    export MICROOS_REQUIRE_LATEST_OPENCODE=1
    mkdir -p /root/.microos
    cp /tmp/microos-setup.sh /root/.microos/setup.sh
    chmod 755 /root/.microos/setup.sh
    bash /root/.microos/setup.sh

    echo "==> Installing Hugging Face CLI in an isolated Python environment"
    python3 -m venv /opt/huggingface-cli
    /opt/huggingface-cli/bin/pip install --no-cache-dir --upgrade "huggingface_hub[cli]"
    ln -sfn /opt/huggingface-cli/bin/hf /usr/local/bin/hf
    if [ -x /opt/huggingface-cli/bin/huggingface-cli ]; then
      ln -sfn /opt/huggingface-cli/bin/huggingface-cli /usr/local/bin/huggingface-cli
    fi
    hf --help >/dev/null
    command -v hf
    # Credentials are supplied to guest processes via HF_TOKEN from Android
    # secure storage. Do not persist access tokens in the rootfs or shell files.

    echo "==> Verifying the pre-baked developer workstation"
    for tool in git gh hf python3 node npm rustc cargo java javac jar unzip zip microos-jar microos-run xdotool xprop adb fastboot jadx apktool mitmproxy blender frida objection apkid google-chrome-stable zsh fzf rg fdfind batcat htop tree nvim; do
      command -v "$tool" >/dev/null 2>&1 || {
        echo "Required pre-baked tool is missing: $tool" >&2
        exit 1
      }
      printf "%-10s %s\\n" "$tool" "$(command -v "$tool")"
    done
    if command -v opencode >/dev/null 2>&1; then
      OPENCODE_BIN="$(command -v opencode)"
    elif [ -x /root/.opencode/bin/opencode ]; then
      OPENCODE_BIN=/root/.opencode/bin/opencode
    else
      echo "OpenCode is missing from the pre-baked image" >&2
      exit 1
    fi
    OPENCODE_VERSION_FILE=/usr/local/share/microos/opencode-version
    test -s "$OPENCODE_VERSION_FILE" || { echo "OpenCode release version manifest missing" >&2; exit 1; }
    EXPECTED_OPENCODE_VERSION="$(cat "$OPENCODE_VERSION_FILE")"
    ACTUAL_OPENCODE_VERSION="$(timeout 30 "$OPENCODE_BIN" --version | head -n 1 | tr -d '\r')"
    test "$ACTUAL_OPENCODE_VERSION" = "$EXPECTED_OPENCODE_VERSION" || {
      echo "OpenCode version mismatch: expected $EXPECTED_OPENCODE_VERSION, got $ACTUAL_OPENCODE_VERSION" >&2
      exit 1
    }
    echo "Verified latest OpenCode: $ACTUAL_OPENCODE_VERSION"
    python3 -c "import zipfile, json, pathlib"

    echo "==> Installing qBittorrent-nox headless torrent engine"
    # setup.sh removes APT indexes during its cleanup; refresh them before
    # installing this additional package in the pre-bake stage.
    apt-get update -y
    apt-get install -y --no-install-recommends qbittorrent-nox
    command -v qbittorrent-nox
    install -d -m 700 /root/.config/qBittorrent /mnt/android/Download
    cat > /root/.config/qBittorrent/qBittorrent.conf <<'QBTCONF'
[Preferences]
WebUI\Address=127.0.0.1
WebUI\Port=8080
WebUI\LocalHostAuth=false
WebUI\CSRFProtection=false
Downloads\SavePath=/mnt/android/Download/
Downloads\TempPath=/mnt/android/Download/.incomplete/
Downloads\TempPathEnabled=true
QBTCONF
    cat > /root/.microos/start-torrent.sh <<'TORRENT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /root/.config/qBittorrent /mnt/android/Download/.incomplete
if (echo >/dev/tcp/127.0.0.1/8080) >/dev/null 2>&1; then exit 0; fi
if pgrep -x qbittorrent-nox >/dev/null 2>&1; then exit 0; fi
nohup setsid qbittorrent-nox --confirm-legal-notice --webui-port=8080 \
  </dev/null >/tmp/microos-qbittorrent.log 2>&1 &
echo "[microos] qBittorrent-nox started on 127.0.0.1:8080"
TORRENT
    chmod 755 /root/.microos/start-torrent.sh

    echo "==> Preparing the unified phone Downloads directory"
    install -d -m 0775 /mnt/android/Download
    ln -sfn /mnt/android/Download /root/Downloads
    test -L /root/Downloads
    test "$(readlink /root/Downloads)" = /mnt/android/Download

    echo "==> Installing Playwright and its headless Chromium runtime"
    npm install --global playwright
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright playwright install chromium --with-deps
    PLAYWRIGHT_NODE_MODULES="$(npm root -g)"
    ln -sfn "$PLAYWRIGHT_NODE_MODULES" /opt/node-global
    cat > /etc/profile.d/microos-playwright.sh <<'PLAYWRIGHT_ENV'
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
export NODE_PATH=/opt/node-global
PLAYWRIGHT_ENV
    chmod 0644 /etc/profile.d/microos-playwright.sh
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright NODE_PATH="$PLAYWRIGHT_NODE_MODULES" node <<PLAYWRIGHT_SMOKE
const { chromium } = require("playwright");
(async () => {
  const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
  const page = await browser.newPage();
  await page.setContent("<title>MicroOS Playwright</title><h1>Headless automation ready</h1>");
  if (!(await page.title()).includes("Playwright")) throw new Error("Playwright page title mismatch");
  await page.screenshot({ path: "/tmp/microos-playwright-smoke.png" });
  await browser.close();
})().catch(error => { console.error(error); process.exit(1); });
PLAYWRIGHT_SMOKE
    test -s /tmp/microos-playwright-smoke.png
    rm -f /tmp/microos-playwright-smoke.png

    echo "==> Installing official Google Chrome Stable for Linux ARM64"
    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates curl
    GOOGLE_CHROME_DEB=/tmp/google-chrome-stable_current_arm64.deb
    curl --fail --location --retry 3 --retry-delay 3 --connect-timeout 20 --max-time 600 \
      https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb \
      --output "$GOOGLE_CHROME_DEB"
    test "$(dpkg-deb -f "$GOOGLE_CHROME_DEB" Architecture)" = arm64
    apt-get install -y --no-install-recommends "$GOOGLE_CHROME_DEB"
    CHROME_BIN="$(command -v google-chrome-stable)"
    CHROME_REAL=/opt/google/chrome/chrome
    test -x "$CHROME_REAL"
    file "$CHROME_REAL" | grep -Eqi "ARM aarch64|ARM64"
    if ldd "$CHROME_REAL" 2>&1 | tee /tmp/google-chrome-ldd.txt | grep -q "not found"; then cat /tmp/google-chrome-ldd.txt >&2; exit 1; fi
    "$CHROME_BIN" --version
    runuser -u microos-browser -- env HOME=/home/microos-browser timeout 90 "$CHROME_BIN" --headless --no-sandbox --disable-gpu --disable-dev-shm-usage --no-first-run --dump-dom "data:text/html,<title>Misty OS Google Chrome smoke test</title><h1>Google Chrome is ready</h1>" > /tmp/microos-chrome-smoke.html
    grep -q "Google Chrome is ready" /tmp/microos-chrome-smoke.html
    echo "==> Official Google Chrome ARM64 startup and DOM rendering test passed"

    # Exercise the actual Linux desktop browser window, not only headless DOM
    # rendering. This runs the same launcher used by the Android PRoot guest.
    echo "==> Testing native Google Chrome X11 window, tabs and mobile control helper"
    # Initialize every PID before starting background processes so strict
    # nounset mode can safely handle early startup failures.
    MICROOS_XVFB_PID=""
    MICROOS_OPENBOX_PID=""
    MICROOS_BROWSER_PID=""
    cleanup_x11_smoke() {
      [ -z "${MICROOS_BROWSER_PID:-}" ] || kill "$MICROOS_BROWSER_PID" 2>/dev/null || true
      [ -z "${MICROOS_OPENBOX_PID:-}" ] || kill "$MICROOS_OPENBOX_PID" 2>/dev/null || true
      [ -z "${MICROOS_XVFB_PID:-}" ] || kill "$MICROOS_XVFB_PID" 2>/dev/null || true
      pkill -u microos-browser -f '[c]hrome' 2>/dev/null || true
    }
    trap cleanup_x11_smoke EXIT
    Xvfb :99 -screen 0 1280x800x24 -nolisten tcp -ac >/tmp/microos-xvfb.log 2>&1 &
    MICROOS_XVFB_PID=$!
    export DISPLAY=:99
    for attempt in $(seq 1 40); do
      if xset -display :99 q >/dev/null 2>&1; then break; fi
      sleep 0.25
    done
    xset -display :99 q >/dev/null
    # DISPLAY is already :99; Openbox has no --display command-line option.
    # Create the log before launch so diagnostics remain available even if
    # Openbox exits before writing anything. Some builds may fork/replace the
    # launcher process, so the EWMH handshake—not the original PID—is the
    # authoritative readiness check.
    : > /tmp/microos-openbox.log
    openbox --sm-disable >/tmp/microos-openbox.log 2>&1 &
    MICROOS_OPENBOX_PID=$!
    WM_READY=0
    for attempt in $(seq 1 40); do
      if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id"; then
        WM_READY=1
        break
      fi
      sleep 0.25
    done
    if [ "$WM_READY" -ne 1 ]; then
      echo "Openbox did not publish the EWMH window-manager handshake" >&2
      cat /tmp/microos-openbox.log >&2 || true
      exit 1
    fi
    MICROOS_DISABLE_GPU=1 timeout 45 /usr/local/bin/start-browser.sh about:blank >/tmp/microos-chrome-x11.log 2>&1 &
    MICROOS_BROWSER_PID=$!
    WINDOW_ID=""
    for attempt in $(seq 1 100); do
      WINDOW_ID="$(xdotool search --onlyvisible --class "google-chrome|Google-chrome|chrome|Chrome|chromium|Chromium" 2>/dev/null | tail -n 1 || true)"
      if [ -n "$WINDOW_ID" ]; then break; fi
      if [ -z "${MICROOS_BROWSER_PID:-}" ] || ! kill -0 "$MICROOS_BROWSER_PID" 2>/dev/null; then break; fi
      sleep 0.25
    done
    if [ -z "$WINDOW_ID" ]; then
      cat /tmp/microos-chrome-x11.log >&2 || true
      echo "Google Chrome X11 window did not appear within 25 seconds" >&2
      cat /tmp/microos-xvfb.log /tmp/microos-openbox.log >&2 || true
      exit 1
    fi
    /usr/local/bin/microos-browser-control new-tab
    /usr/local/bin/microos-browser-control focus-address
    /usr/local/bin/microos-browser-control bookmarks
    sleep 0.5
    GEOMETRY="$(xdotool getwindowgeometry --shell "$WINDOW_ID")"
    WIDTH="$(printf "%s\n" "$GEOMETRY" | sed -n "s/^WIDTH=//p")"
    HEIGHT="$(printf "%s\n" "$GEOMETRY" | sed -n "s/^HEIGHT=//p")"
    if [ "${WIDTH:-0}" -lt 1000 ] || [ "${HEIGHT:-0}" -lt 600 ]; then
      echo "Google Chrome X11 window did not maximize: $GEOMETRY" >&2
      cat /tmp/microos-chrome-x11.log >&2 || true
      kill -9 "${MICROOS_BROWSER_PID:-}" "${MICROOS_OPENBOX_PID:-}" "${MICROOS_XVFB_PID:-}" 2>/dev/null || true
      exit 1
    fi
    echo "==> Native Google Chrome window verified: ${WIDTH}x${HEIGHT}"
    /usr/local/bin/microos-browser-control window-close || true
    wait "$MICROOS_BROWSER_PID" 2>/dev/null || true
    MICROOS_BROWSER_PID=""
    cleanup_x11_smoke
    trap - EXIT

    # Verify the full X11 -> x11vnc -> websockify -> noVNC canvas path.
    # A changing, known root-window color must arrive as real canvas pixels.
    echo "==> Testing noVNC WebSocket/RFB framebuffer updates"
    MICROOS_VNC_XVFB_PID=""
    MICROOS_VNC_OPENBOX_PID=""
    MICROOS_VNC_PID=""
    MICROOS_WEBSOCKIFY_PID=""
    cleanup_novnc_smoke() {
      [ -z "$MICROOS_WEBSOCKIFY_PID" ] || kill "$MICROOS_WEBSOCKIFY_PID" 2>/dev/null || true
      [ -z "$MICROOS_VNC_PID" ] || kill "$MICROOS_VNC_PID" 2>/dev/null || true
      [ -z "$MICROOS_VNC_OPENBOX_PID" ] || kill "$MICROOS_VNC_OPENBOX_PID" 2>/dev/null || true
      [ -z "$MICROOS_VNC_XVFB_PID" ] || kill "$MICROOS_VNC_XVFB_PID" 2>/dev/null || true
      pkill -x websockify 2>/dev/null || true
      pkill -x x11vnc 2>/dev/null || true
    }
    trap cleanup_novnc_smoke EXIT
    Xvfb :100 -screen 0 1280x720x24 -nolisten tcp -ac -noreset > /tmp/microos-novnc-xvfb.log 2>&1 &
    MICROOS_VNC_XVFB_PID=$!
    export DISPLAY=:100
    for attempt in $(seq 1 40); do
      if xset -display :100 q >/dev/null 2>&1; then break; fi
      kill -0 "$MICROOS_VNC_XVFB_PID" 2>/dev/null || {
        cat /tmp/microos-novnc-xvfb.log >&2 || true
        exit 1
      }
      sleep 0.25
    done
    xset -display :100 q >/dev/null
    xsetroot -display :100 -solid "#123456"
    DISPLAY=:100 openbox > /tmp/microos-novnc-openbox.log 2>&1 &
    MICROOS_VNC_OPENBOX_PID=$!
    WM_READY=0
    for attempt in $(seq 1 40); do
      if xprop -display :100 -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id"; then
        WM_READY=1
        break
      fi
      kill -0 "$MICROOS_VNC_OPENBOX_PID" 2>/dev/null || break
      sleep 0.25
    done
    if [ "$WM_READY" -ne 1 ]; then
      cat /tmp/microos-novnc-openbox.log >&2 || true
      echo "Openbox did not start for noVNC framebuffer test" >&2
      exit 1
    fi
    x11vnc -display :100 -forever -shared -nopw -rfbport 5901 -localhost \
      -noxdamage -noshm -wait 1 -defer 1 > /tmp/microos-novnc-x11vnc.log 2>&1 &
    MICROOS_VNC_PID=$!
    for attempt in $(seq 1 40); do
      if (echo >/dev/tcp/127.0.0.1/5901) >/dev/null 2>&1; then break; fi
      kill -0 "$MICROOS_VNC_PID" 2>/dev/null || {
        cat /tmp/microos-novnc-x11vnc.log >&2 || true
        exit 1
      }
      sleep 0.25
    done
    (echo >/dev/tcp/127.0.0.1/5901) >/dev/null 2>&1 || {
      cat /tmp/microos-novnc-x11vnc.log >&2 || true
      echo "x11vnc did not open port 5901" >&2
      exit 1
    }
    websockify --verbose --host=127.0.0.1 --web /usr/share/novnc 6081 localhost:5901 \
      > /tmp/microos-novnc-websockify.log 2>&1 &
    MICROOS_WEBSOCKIFY_PID=$!
    for attempt in $(seq 1 40); do
      if curl -fsS --max-time 2 http://127.0.0.1:6081/vnc.html -o /dev/null 2>/dev/null; then break; fi
      kill -0 "$MICROOS_WEBSOCKIFY_PID" 2>/dev/null || {
        cat /tmp/microos-novnc-websockify.log >&2 || true
        exit 1
      }
      sleep 0.25
    done
    curl -fsS --max-time 2 http://127.0.0.1:6081/vnc.html -o /dev/null || {
      cat /tmp/microos-novnc-websockify.log >&2 || true
      echo "websockify did not serve noVNC on port 6081" >&2
      exit 1
    }
    if ! DISPLAY=:100 MICROOS_NOVNC_URL="http://127.0.0.1:6081/vnc.html?autoconnect=1&resize=scale&path=websockify&quality=6&compression=2" \
      PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright NODE_PATH=/opt/node-global \
      timeout 60 node /tmp/test-novnc-render.cjs; then
      echo "noVNC framebuffer test failed; service logs follow" >&2
      cat /tmp/microos-novnc-xvfb.log /tmp/microos-novnc-openbox.log \
        /tmp/microos-novnc-x11vnc.log /tmp/microos-novnc-websockify.log >&2 || true
      exit 1
    fi
    test -s /tmp/microos-novnc-render.png
    echo "==> noVNC canvas received two distinct X11 framebuffer updates"
    cleanup_novnc_smoke
    trap - EXIT
    rm -f /tmp/microos-novnc-render.png /tmp/microos-novnc-render-failure.png \
      /tmp/microos-novnc-xvfb.log /tmp/microos-novnc-openbox.log \
      /tmp/microos-novnc-x11vnc.log /tmp/microos-novnc-websockify.log
    unset DISPLAY

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
    bash -n /usr/local/bin/start-browser.sh /usr/local/bin/start-firefox.sh /usr/local/bin/microos-browse /usr/local/bin/microos-browser-control
    test -x /usr/local/bin/start-firefox.sh
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
    BROWSER_HOME=/home/microos-browser
    # Let Firefox create its own default profile. Passing --profile to the
    # Mozilla launcher in this container produced a false "profile folder"
    # failure even when the directory existed.
    install -d -o microos-browser -g microos-browser -m 700 \
      "$BROWSER_HOME" "$BROWSER_HOME/.mozilla" "$BROWSER_HOME/.cache"
    runuser -u microos-browser -- env \
      HOME="$BROWSER_HOME" \
      MOZ_DISABLE_CONTENT_SANDBOX=1 \
      MOZ_DISABLE_GMP_SANDBOX=1 \
      timeout 90 /opt/firefox/firefox --headless --no-remote \
        --screenshot /tmp/microos-firefox-smoke.png \
        "data:text/html,<title>MicroOS Firefox smoke test</title><h1>Firefox is ready</h1>"
    test -s /tmp/microos-firefox-smoke.png
    echo "==> Firefox ARM64 headless startup and rendering test passed"
    # Keep the browser home in the exported rootfs; the runtime launcher expects
    # this path to exist and will repair ownership before starting Firefox.
    rm -rf "$BROWSER_HOME/.mozilla" "$BROWSER_HOME/.cache"
    install -d -o microos-browser -g microos-browser -m 700 "$BROWSER_HOME"
    rm -f /tmp/microos-firefox-smoke.png /tmp/firefox-ldd.txt

    rm -f /tmp/firefox.tar.xz /tmp/google-chrome-ldd.txt /tmp/microos-chrome-smoke.html /root/.microos/setup.sh
    apt-get clean
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
    printf "15\\n" > /root/.microos/image-version
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
# Stream the tar directly into zstd so no second uncompressed archive is written.
tar --hard-dereference --numeric-owner --owner=0 --group=0 \
  -cf - -C "$TMP/rootfs" . | zstd -T0 -10 -f -o "$OUT"

zstd -t "$OUT"
# Store the exact uncompressed tar-stream size so the Android installer can
# report bytes actually extracted, not compressed-input estimates.
zstd -dc "$OUT" | wc -c | tr -d '[:space:]' > "$ROOT/assets/rootfs/rootfs.tar.size"
test "$(cat "$ROOT/assets/rootfs/rootfs.tar.size")" -gt 0
zstd -dc "$OUT" | tar -tf - > "$TMP/rootfs-archive.list"
require_archive_path() {
  local expected="$1"
  if ! grep -qE "^(\\./)?${expected}(/)?$" "$TMP/rootfs-archive.list"; then
    echo "ERROR: exported rootfs is missing required path: ${expected}" >&2
    echo "Archive entries matching the expected basename:" >&2
    grep -F "$(basename "$expected")" "$TMP/rootfs-archive.list" | head -n 30 >&2 || true
    exit 1
  fi
}
# Keep this list in sync with the APK workflow's transfer validation.
require_archive_path 'root/\.microos/ready'
require_archive_path 'root/\.microos/image-version'
require_archive_path 'usr/bin/zsh'
require_archive_path 'usr/bin/fzf'
require_archive_path 'usr/bin/rg'
require_archive_path 'usr/bin/fdfind'
require_archive_path 'usr/bin/batcat'
require_archive_path 'usr/bin/htop'
require_archive_path 'usr/bin/tree'
require_archive_path 'usr/bin/nvim'
require_archive_path 'root/.zshrc'
require_archive_path 'usr/bin/adb'
require_archive_path 'usr/bin/fastboot'
require_archive_path 'usr/bin/apktool'
require_archive_path 'usr/bin/mitmproxy'
require_archive_path 'usr/bin/blender'
require_archive_path 'usr/local/bin/jadx'
require_archive_path 'opt/jadx/bin/jadx'
require_archive_path 'usr/local/bin/pip3'
require_archive_path 'usr/local/bin/frida'
require_archive_path 'usr/local/bin/objection'
require_archive_path 'usr/local/bin/apkid'
require_archive_path 'usr/local/share/microos/opencode-version'
require_archive_path 'usr/bin/google-chrome-stable'
require_archive_path 'opt/google/chrome/chrome'
require_archive_path 'usr/local/bin/start-browser.sh'
require_archive_path 'usr/local/bin/microos-browser-control'
require_archive_path 'usr/bin/xdotool'
require_archive_path 'root/.microos/start-desktop.sh'
require_archive_path 'opt/firefox/firefox'
require_archive_path 'opt/firefox/firefox-bin'
require_archive_path 'opt/ms-playwright'
require_archive_path 'opt/huggingface-cli'
require_archive_path 'opt/node-global'
require_archive_path 'root/Downloads'
require_archive_path 'etc/profile.d/microos-playwright.sh'
require_archive_path 'usr/local/bin/microos-browse'
require_archive_path 'usr/local/bin/microos-jar'
require_archive_path 'usr/local/bin/microos-run'
require_archive_path 'root/.opencode/bin/opencode'
require_archive_path 'home/microos-browser'
require_archive_path 'usr/bin/qbittorrent-nox'
require_archive_path 'root/.microos/start-torrent.sh'
echo "==> All required rootfs paths verified"
echo "==> Pre-baked ARM64 rootfs (zstd): $(du -h "$OUT" | cut -f1)"
