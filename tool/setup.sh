#!/usr/bin/env bash
# =============================================================================
# MicroOS first-boot provisioning.
#
# Runs INSIDE the proot guest as fake root (uid 0 mapped), on Ubuntu 24.04 arm64.
# It is idempotent and every step is best-effort: a failed package must not
# leave the user with an unusable shell.
#
# Progress is reported to the Flutter UI with "[stage] ..." and "[progress] N"
# lines on stdout, which LinuxRuntime parses.
# =============================================================================
set -uo pipefail

# Use a writable, private temp directory inside the proot guest.
export TMPDIR=/tmp
mkdir -p /tmp
chmod 1777 /tmp
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH="/root/.opencode/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

log()  { printf '[microos] %s\n' "$*"; }
warn() { printf '[microos] WARN: %s\n' "$*"; }

# stage <percent> <text>  |  stage <text>
stage() {
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    printf '[progress] %s\n[stage] %s\n' "$1" "${2:-}"
  else
    printf '[stage] %s\n' "${1:-}"
  fi
}

mkdir -p /root/.microos /root/projects /root/.local/bin /root/.config /mnt/android/Download
ln -sfn /mnt/android/Download /root/Downloads

# Android shared storage is commonly mounted noexec. Copy a requested download
# into the guest's executable /tmp before running it, while keeping its working
# directory beside the original download for relative file access.
cat > /usr/local/bin/microos-run <<'MICROOS_RUN'
#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -lt 1 ]; then
  echo "Usage: microos-run ~/Downloads/script.sh [arguments...]" >&2
  exit 2
fi
SOURCE="$(realpath -e -- "$1")"
case "$SOURCE" in
  /mnt/android/Download/*) ;;
  *) echo "microos-run only executes files from /mnt/android/Download" >&2; exit 2 ;;
esac
if [ ! -f "$SOURCE" ]; then
  echo "Not a regular file: $SOURCE" >&2
  exit 2
fi
shift
WORK="$(mktemp -d /tmp/microos-run.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
TARGET="$WORK/$(basename "$SOURCE")"
cp -- "$SOURCE" "$TARGET"
chmod 700 "$TARGET"
cd "$(dirname "$SOURCE")"
case "$SOURCE" in
  *.sh) bash "$TARGET" "$@" ;;
  *.py) python3 "$TARGET" "$@" ;;
  *.js|*.mjs|*.cjs) node "$TARGET" "$@" ;;
  *) "$TARGET" "$@" ;;
esac
MICROOS_RUN
chmod 755 /usr/local/bin/microos-run

# -----------------------------------------------------------------------------
# 0. Sanity: are we really inside the guest?
# -----------------------------------------------------------------------------
if [ ! -f /etc/os-release ]; then
  echo "!! setup.sh must run inside the Linux rootfs" >&2
  exit 1
fi

# Android has no resolv.conf inside the rootfs; without this apt cannot resolve.
printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf

# Do not let package postinst scripts try to start services (there is no init).
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

# -----------------------------------------------------------------------------
# 1. APT sources
# -----------------------------------------------------------------------------
stage 60 "Configuring APT"
cat > /etc/apt/sources.list <<'EOF'
deb http://ports.ubuntu.com/ubuntu-ports noble main universe restricted multiverse
deb http://ports.ubuntu.com/ubuntu-ports noble-updates main universe restricted multiverse
deb http://ports.ubuntu.com/ubuntu-ports noble-security main universe restricted multiverse
EOF
# Ubuntu 24.04 base images ship deb822 sources; drop them to avoid duplicates.
rm -f /etc/apt/sources.list.d/ubuntu.sources

log "apt-get update"
apt_updated=0
for attempt in 1 2 3; do
  log "apt-get update attempt $attempt/3"
  if apt-get update -y; then apt_updated=1; break; fi
  warn "apt update attempt $attempt failed; retrying after network delay"
  sleep $((attempt * 4))
done
[ "$apt_updated" -eq 1 ] || warn "apt update failed after retries (offline?)"

APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::="--force-confold")

# -----------------------------------------------------------------------------
# 2. Core toolchain
# -----------------------------------------------------------------------------
stage 63 "Installing core toolchain"
apt-get install "${APT_OPTS[@]}" \
  ca-certificates curl wget gnupg apt-utils locales \
  git git-lfs openssh-client \
  build-essential pkg-config make cmake openjdk-21-jdk-headless \
  python3 python3-pip python3-venv python3-dev \
  unzip zip xz-utils tar less nano vim-tiny \
  procps file jq tmux sudo \
  || warn "some core packages failed to install"

# Generate the UTF-8 locale explicitly; merely exporting LANG does not create it.
if [ -f /etc/locale.gen ]; then
  sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
  locale-gen en_US.UTF-8 || warn "could not generate en_US.UTF-8 locale"
fi

# -----------------------------------------------------------------------------
# 3. Node.js + Rust + GitHub CLI
#    Ubuntu 24.04 ships node 18 / rust 1.75, which is enough for most work.
#    Node 20+ is installed from NodeSource when the network allows it.
# -----------------------------------------------------------------------------
stage 70 "Installing Node.js, Rust and GitHub CLI"
apt-get install "${APT_OPTS[@]}" nodejs npm rustc cargo gh || warn "node/rust/gh install had errors"

if ! node --version 2>/dev/null | grep -qE 'v(2[0-9])'; then
  log "upgrading Node.js to 20 via NodeSource"
  if curl -fsSL --max-time 60 https://deb.nodesource.com/setup_20.x -o /tmp/nodesource.sh; then
    bash /tmp/nodesource.sh || warn "nodesource setup failed"
    apt-get install "${APT_OPTS[@]}" nodejs || warn "nodejs upgrade failed"
  else
    warn "could not reach deb.nodesource.com, keeping distro Node"
  fi
fi
command -v npm >/dev/null && npm config set fund false --global 2>/dev/null

# -----------------------------------------------------------------------------
# 4. Native X11 stack + window manager
#    The Android app talks to Xvfb through MicroOS's own MIT-licensed bridge
#    (tool/x11_bridge.c). There is no VNC server or browser-based client.
# -----------------------------------------------------------------------------
stage 76 "Installing native X11"
apt-get install "${APT_OPTS[@]}" \
  xvfb openbox xterm x11-utils x11-xserver-utils xauth dbus-x11 xdotool \
  libx11-dev libxtst-dev libxdamage-dev libxfixes-dev libjpeg-turbo8-dev \
  pulseaudio pulseaudio-utils libasound2-plugins \
  libgl1-mesa-dri mesa-utils \
  fonts-dejavu-core fonts-liberation \
  || warn "some X11/audio packages failed to install"

stage 78 "Building native X11 and audio bridges"
if [ -f /root/.microos/x11_bridge.c ]; then
  if gcc -O2 -Wall -Wextra \
      -o /usr/local/bin/microos-xbridge /root/.microos/x11_bridge.c \
      -lX11 -lXtst -lXdamage -lXfixes -ljpeg; then
    chmod 755 /usr/local/bin/microos-xbridge
    log "native X11 bridge compiled (JPEG fast path)"
  else
    warn "native X11 bridge compilation failed; the desktop will not start"
  fi
else
  warn "native X11 bridge source is missing from /root/.microos"
fi
if [ -f /root/.microos/audio_bridge.c ]; then
  if gcc -O2 -Wall -Wextra \
      -o /usr/local/bin/microos-audio /root/.microos/audio_bridge.c; then
    chmod 755 /usr/local/bin/microos-audio
    log "native audio bridge compiled"
  else
    warn "native audio bridge compilation failed; desktop audio is unavailable"
  fi
else
  warn "native audio bridge source is missing from /root/.microos"
fi

# PulseAudio writes the complete mixed desktop signal into a FIFO. The audio
# bridge mirrors that FIFO to Android at 48 kHz stereo s16le, so apps do not
# resample on the phone and YouTube/VLC/Firefox all share one low-latency path.
stage 79 "Configuring low-latency desktop audio"
mkdir -p /etc/pulse
cat > /etc/pulse/microos.pa <<'PULSE'
load-module module-native-protocol-unix socket=/tmp/microos-pulse.sock auth-anonymous=1
load-module module-pipe-sink sink_name=microos file=/tmp/microos-audio.pcm format=s16le rate=48000 channels=2
set-default-sink microos
PULSE
cat > /etc/pulse/client.conf <<'PULSECLIENT'
default-server = unix:/tmp/microos-pulse.sock
autospawn = no
PULSECLIENT

# macOS-inspired X11 pointer theme (WhiteSur Cursors, upstream GPL-3.0).
# This affects X11 applications in the desktop; it does not change the
# Android host pointer, which Misty draws on the native X11 surface.
stage 80 "Installing WhiteSur X11 cursor theme"
apt-get install "${APT_OPTS[@]}" git x11-xserver-utils || warn "cursor prerequisites failed"
if [ ! -d /usr/share/icons/WhiteSur-cursors/cursors ]; then
  rm -rf /tmp/WhiteSur-cursors
  if git clone --depth 1 https://github.com/vinceliuice/WhiteSur-cursors.git /tmp/WhiteSur-cursors; then
    if [ -d /tmp/WhiteSur-cursors/dist/cursors ]; then
      install -d /usr/share/icons/WhiteSur-cursors
      cp -a /tmp/WhiteSur-cursors/dist/. /usr/share/icons/WhiteSur-cursors/
      [ -f /tmp/WhiteSur-cursors/LICENSE ] && install -m 644 /tmp/WhiteSur-cursors/LICENSE /usr/share/icons/WhiteSur-cursors/LICENSE
      log "WhiteSur cursor assets installed"
    else
      warn "WhiteSur upstream checkout has no compiled dist/cursors; retaining default cursor"
    fi
  else
    warn "WhiteSur cursor download failed; retaining default cursor"
  fi
fi
if [ -d /usr/share/icons/WhiteSur-cursors/cursors ]; then
  mkdir -p /root/.icons/default
  cat > /root/.icons/default/index.theme <<'CURSOR'
[Icon Theme]
Inherits=WhiteSur-cursors
CURSOR
  cat > /root/.Xresources <<'XRES'
Xcursor.theme: WhiteSur-cursors
Xcursor.size: 24
XRES
fi
rm -rf /tmp/WhiteSur-cursors

# -----------------------------------------------------------------------------
# 5. Browser
# Chromium is pre-baked as a native ARM64 .deb; do not use Ubuntu Snap.
stage 84 "Preparing Chromium desktop browser"
apt-get install "${APT_OPTS[@]}" passwd util-linux || warn "browser user tools unavailable"
if ! id microos-browser >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/microos-browser --shell /usr/sbin/nologin microos-browser || warn "browser user creation failed"
fi

cat > /usr/local/bin/start-browser.sh <<'BROWSER'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/microos-pulse.sock}"
BROWSER_HOME=/home/microos-browser
CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
if [ -z "$CHROMIUM_BIN" ]; then echo "[microos] Chromium .deb is not installed" >&2; exit 127; fi
install -d -o microos-browser -g microos-browser -m 700 "$BROWSER_HOME" "$BROWSER_HOME/.config/chromium" "$BROWSER_HOME/.config/chromium/Default" "$BROWSER_HOME/.cache"
CHROMIUM_PREFS="$BROWSER_HOME/.config/chromium/Default/Preferences"
python3 - "$CHROMIUM_PREFS" <<'CHROMIUM_PREFS'
import json
import os
import sys

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as source:
        preferences = json.load(source)
except FileNotFoundError:
    preferences = {}
if not isinstance(preferences, dict):
    preferences = {}
bookmark_bar = preferences.setdefault("bookmark_bar", {})
browser = preferences.setdefault("browser", {})
download = preferences.setdefault("download", {})
changed = False
if "show_on_all_tabs" not in bookmark_bar:
    bookmark_bar["show_on_all_tabs"] = True
    changed = True
if "show_home_button" not in browser:
    browser["show_home_button"] = True
    changed = True
if download.get("default_directory") != "/mnt/android/Download":
    download["default_directory"] = "/mnt/android/Download"
    changed = True
if download.get("prompt_for_download", True):
    download["prompt_for_download"] = False
    changed = True
if changed or not os.path.exists(path):
    temporary = path + ".microos-tmp"
    with open(temporary, "w", encoding="utf-8") as target:
        json.dump(preferences, target, separators=(",", ":"))
    os.replace(temporary, path)
CHROMIUM_PREFS
chown microos-browser:microos-browser "$CHROMIUM_PREFS"

# Seed a useful native Chromium bookmarks bar once. Never replace a user's
# existing Bookmarks database after their first browser launch.
BOOKMARKS_FILE="$BROWSER_HOME/.config/chromium/Default/Bookmarks"
if [ ! -s "$BOOKMARKS_FILE" ]; then
  cat > "$BOOKMARKS_FILE" <<'BOOKMARKS'
{
  "checksum": "",
  "roots": {
    "bookmark_bar": {
      "children": [
        {"date_added":"13370000000000000","id":"4","name":"Google","type":"url","url":"https://www.google.com/"},
        {"date_added":"13370000000000000","id":"5","name":"YouTube","type":"url","url":"https://www.youtube.com/"},
        {"date_added":"13370000000000000","id":"6","name":"GitHub","type":"url","url":"https://github.com/"}
      ],
      "date_modified": "0",
      "id": "1",
      "name": "Bookmarks bar",
      "type": "folder"
    },
    "other": {"children":[],"date_modified":"0","id":"2","name":"Other bookmarks","type":"folder"},
    "synced": {"children":[],"date_modified":"0","id":"3","name":"Mobile bookmarks","type":"folder"}
  },
  "version": 1
}
BOOKMARKS
  chown microos-browser:microos-browser "$BOOKMARKS_FILE"
fi

# Ensure the shared X11 session has only one browser engine at a time.
pkill -u microos-browser -f '[f]irefox' 2>/dev/null || true
sleep 0.4
CHROMIUM_EXTRA_ARGS=(
  --ignore-gpu-blocklist
  --canvas-oop-rasterization
  --enable-features=CanvasOopRasterization,ParallelDownloading
)
if [ "${MICROOS_DISABLE_GPU:-0}" = "1" ]; then
  # Used only by the CI Xvfb window test. Phone launches keep acceleration enabled.
  CHROMIUM_EXTRA_ARGS+=(--disable-gpu)
fi
if [ "${MICROOS_HARDWARE_GPU_ONLY:-0}" = "1" ]; then
  # Opt-in only: disabling SwiftShader/software fallback can blank rendering on
  # devices where PRoot cannot expose a usable host GPU. Enable after device test.
  CHROMIUM_EXTRA_ARGS+=(--disable-software-rasterizer)
fi
exec runuser -u microos-browser -- env DISPLAY="$DISPLAY" PULSE_SERVER="$PULSE_SERVER" HOME="$BROWSER_HOME" XDG_CONFIG_HOME="$BROWSER_HOME/.config" XDG_CACHE_HOME="$BROWSER_HOME/.cache" "$CHROMIUM_BIN" \
  "${CHROMIUM_EXTRA_ARGS[@]}" \
  --no-sandbox \
  --disable-gpu-sandbox \
  --process-per-site \
  --disable-background-networking \
  --disable-features=Translate,OptimizationHints,MediaRouter,CalculateNativeWinOcclusion \
  --disable-background-timer-throttling \
  --disable-renderer-backgrounding \
  --disable-backgrounding-occluded-windows \
  --autoplay-policy=no-user-gesture-required \
  --enable-quic \
  --force-device-scale-factor=1 \
  --renderer-process-limit=3 \
  --js-flags="--max-old-space-size=512" \
  --disable-dev-shm-usage --no-first-run \
  --disable-crash-reporter \
  --disable-low-res-tiling \
  --disk-cache-size=67108864 --media-cache-size=16777216 \
  --start-maximized \
  --user-data-dir="$BROWSER_HOME/.config/chromium" "$@"
BROWSER
chmod 755 /usr/local/bin/start-browser.sh

cat > /usr/local/bin/start-firefox.sh <<'BROWSER'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/microos-pulse.sock}"
BROWSER_HOME=/home/microos-browser
FIREFOX_BIN="$(command -v firefox || true)"
if [ -z "$FIREFOX_BIN" ]; then
  echo "[microos] Firefox is not installed in this rootfs image" >&2
  exit 127
fi
FIREFOX_PROFILE="$BROWSER_HOME/.mozilla/microos"
install -d -o microos-browser -g microos-browser -m 700 "$BROWSER_HOME" "$BROWSER_HOME/.mozilla" "$FIREFOX_PROFILE"
FIREFOX_PREFS="$FIREFOX_PROFILE/prefs.js"
if ! grep -q 'browser.toolbars.bookmarks.visibility' "$FIREFOX_PREFS" 2>/dev/null; then
  printf '%s\n' 'user_pref("browser.toolbars.bookmarks.visibility", "always");' >> "$FIREFOX_PREFS"
fi
if ! grep -q 'browser.startup.homepage' "$FIREFOX_PREFS" 2>/dev/null; then
  printf '%s\n' 'user_pref("browser.startup.homepage", "about:home");' >> "$FIREFOX_PREFS"
  printf '%s\n' 'user_pref("browser.startup.page", 1);' >> "$FIREFOX_PREFS"
fi
if ! grep -q 'browser.shell.checkDefaultBrowser' "$FIREFOX_PREFS" 2>/dev/null; then
  printf '%s\n' 'user_pref("browser.shell.checkDefaultBrowser", false);' >> "$FIREFOX_PREFS"
fi
if ! grep -q 'browser.download.dir' "$FIREFOX_PREFS" 2>/dev/null; then
  printf '%s\n' 'user_pref("browser.download.dir", "/mnt/android/Download");' \
    'user_pref("browser.download.folderList", 2);' \
    'user_pref("browser.download.useDownloadDir", true);' \
    'user_pref("browser.download.manager.showWhenStarting", false);' >> "$FIREFOX_PREFS"
fi
chown microos-browser:microos-browser "$FIREFOX_PREFS"
# Only one engine should own the remote desktop at a time.
pkill -u microos-browser -f '[c]hromium|[c]hrome' 2>/dev/null || true
sleep 0.4
# Run a regular Firefox window (not kiosk/app mode), then maximize it through
# Openbox once its real X11 window is available.
runuser -u microos-browser -- env DISPLAY="$DISPLAY" PULSE_SERVER="$PULSE_SERVER" HOME="$BROWSER_HOME" \
  MOZ_ENABLE_WAYLAND=0 MOZ_DISABLE_CONTENT_SANDBOX=1 MOZ_DISABLE_GMP_SANDBOX=1 \
  "$FIREFOX_BIN" --profile "$FIREFOX_PROFILE" --new-window "$@" &
FIREFOX_PID=$!
for attempt in $(seq 1 40); do
  WINDOW_ID="$(xdotool search --onlyvisible --class firefox 2>/dev/null | head -n 1 || true)"
  if [ -n "$WINDOW_ID" ]; then
    xdotool windowactivate --sync "$WINDOW_ID" 2>/dev/null || true
    xdotool key --clearmodifiers alt+F10 2>/dev/null || true
    break
  fi
  kill -0 "$FIREFOX_PID" 2>/dev/null || break
  sleep 0.2
done
wait "$FIREFOX_PID"
BROWSER
chmod 755 /usr/local/bin/start-firefox.sh

# Compatibility alias for older launchers; the canonical script switches engines.
cat > /usr/local/bin/microos-browse <<'BROWSER'
#!/usr/bin/env bash
exec /usr/local/bin/start-browser.sh "$@"
BROWSER
chmod 755 /usr/local/bin/microos-browse

cat > /usr/local/bin/microos-browser-control <<'BROWSER'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
ACTION="${1:-}"
case "$ACTION" in
  back)          KEY='alt+Left' ;;
  forward)       KEY='alt+Right' ;;
  reload)        KEY='ctrl+r' ;;
  new-tab)       KEY='ctrl+t' ;;
  close-tab)     KEY='ctrl+w' ;;
  new-window)    KEY='ctrl+n' ;;
  focus-address) KEY='ctrl+l' ;;
  home)          KEY='alt+Home' ;;
  bookmarks)     KEY='ctrl+shift+b' ;;
  fullscreen)    KEY='F11' ;;
  zoom-in)       KEY='ctrl+plus' ;;
  zoom-out)      KEY='ctrl+minus' ;;
  zoom-reset)    KEY='ctrl+0' ;;
  window-minimize|window-maximize|window-restore|window-close) KEY='' ;;
  *) echo "Unsupported browser action: $ACTION" >&2; exit 2 ;;
esac

# Select the real Linux browser window. Do not depend on EWMH
# _NET_ACTIVE_WINDOW: some Xvfb/proot window-manager configurations omit it.
WINDOW_ID="$(xdotool search --class 'chromium|Chromium|chrome|Chrome|firefox|Firefox|Navigator' 2>/dev/null | tail -n 1 || true)"
if [ -z "$WINDOW_ID" ]; then
  echo "[microos] no Chromium/Firefox window is available" >&2
  exit 1
fi

case "$ACTION" in
  window-minimize)
    exec xdotool windowminimize "$WINDOW_ID"
    ;;
  window-maximize)
    xdotool windowstate --add MAXIMIZED_VERT "$WINDOW_ID"
    exec xdotool windowstate --add MAXIMIZED_HORZ "$WINDOW_ID"
    ;;
  window-restore)
    xdotool windowmap "$WINDOW_ID" 2>/dev/null || true
    xdotool windowstate --remove MAXIMIZED_VERT "$WINDOW_ID" 2>/dev/null || true
    xdotool windowstate --remove MAXIMIZED_HORZ "$WINDOW_ID" 2>/dev/null || true
    exec xdotool windowfocus --sync "$WINDOW_ID"
    ;;
  window-close)
    exec xdotool windowclose "$WINDOW_ID"
    ;;
  *)
    xdotool windowraise "$WINDOW_ID" 2>/dev/null || true
    xdotool windowfocus --sync "$WINDOW_ID"
    exec xdotool key --clearmodifiers "$KEY"
    ;;
esac
BROWSER
chmod 755 /usr/local/bin/microos-browser-control

# -----------------------------------------------------------------------------
# 6. Desktop applications
#    Preinstall the everyday Linux software set so the desktop is useful on the
#    first launch, not an empty shell. Blender, the creative suite and the Git
#    GUIs are installed explicitly. --no-install-recommends keeps the image
#    small enough for a phone while still installing every required runtime.
# -----------------------------------------------------------------------------
stage 86 "Installing desktop applications"
# Install in small groups so one unavailable package cannot block Blender or
# the rest of the desktop suite.
for group in \
  "blender" \
  "gimp inkscape" \
  "vlc mpv ffmpeg" \
  "pcmanfm mousepad galculator file-roller ristretto evince" \
  "git-cola gitg geany sqlitebrowser" \
  "libreoffice-writer libreoffice-calc" \
  "fonts-noto-core fonts-noto-color-emoji"; do
  # shellcheck disable=SC2086
  apt-get install "${APT_OPTS[@]}" $group \
    || warn "desktop application group failed: $group"
done

# The same artwork used by Launchpad is copied into the guest by the app (or
# mounted by prebake_rootfs.sh). Installing it into hicolor guarantees that
# pcmanfm and Openbox show Blender, Chrome, GIMP, ... with their real icons
# instead of generic application glyphs.
stage 87 "Installing desktop shortcuts and icons"
ICON_DIR=/usr/share/icons/hicolor/256x256/apps
DESKTOP_DIR=/root/Desktop
install -d "$ICON_DIR" "$DESKTOP_DIR"
for icon in blender calc chrome files geany gimp gitcola inkscape texteditor vlc writer; do
  if [ -f "/root/.microos/icons/$icon.png" ]; then
    install -m 644 "/root/.microos/icons/$icon.png" "$ICON_DIR/microos-$icon.png"
  fi
done
icon_for() {
  if [ -f "$ICON_DIR/microos-$1.png" ]; then
    printf 'microos-%s' "$1"
  else
    printf '%s' "$2"
  fi
}
write_shortcut() {
  local file="$1"
  local label="$2"
  local exec_line="$3"
  local icon="$4"
  cat > "$DESKTOP_DIR/$file.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=$label
Exec=$exec_line
Icon=$icon
Terminal=false
StartupNotify=true
DESKTOP
  chmod 755 "$DESKTOP_DIR/$file.desktop"
  if command -v gio >/dev/null 2>&1; then
    gio set "$DESKTOP_DIR/$file.desktop" metadata::trusted true 2>/dev/null || true
  fi
}
write_shortcut chrome 'Chrome' '/usr/local/bin/start-browser.sh' "$(icon_for chrome chromium-browser)"
write_shortcut blender 'Blender' 'blender' "$(icon_for blender blender)"
write_shortcut files 'Files' 'pcmanfm' "$(icon_for files system-file-manager)"
write_shortcut texteditor 'Text Editor' 'mousepad' "$(icon_for texteditor accessories-text-editor)"
write_shortcut gimp 'GIMP' 'gimp' "$(icon_for gimp gimp)"
write_shortcut inkscape 'Inkscape' 'inkscape' "$(icon_for inkscape inkscape)"
write_shortcut vlc 'VLC' 'vlc' "$(icon_for vlc vlc)"
write_shortcut writer 'LibreOffice Writer' 'libreoffice --writer' "$(icon_for writer libreoffice-writer)"
write_shortcut calc 'LibreOffice Calc' 'libreoffice --calc' "$(icon_for calc libreoffice-calc)"
write_shortcut geany 'Geany' 'geany' "$(icon_for geany geany)"
write_shortcut gitcola 'Git Cola' 'git-cola' "$(icon_for gitcola git-cola)"
# The runtime can re-supply the PNGs on the next setup run.
rm -rf /root/.microos/icons

# Small automation-friendly Chromium launcher shared by OpenCode, Playwright
# and Puppeteer. It always runs headless-safe flags; callers may add their own
# --headless flag. The desktop still uses start-browser.sh directly.
cat > /usr/local/bin/chrome <<'CHROME'
#!/usr/bin/env bash
set -euo pipefail
BIN="$(command -v chromium || command -v chromium-browser || true)"
if [ -z "$BIN" ]; then
  echo "[microos] Chromium is not installed" >&2
  exit 127
fi
exec "$BIN" \
  --no-sandbox \
  --disable-gpu-sandbox \
  --disable-dev-shm-usage \
  --disable-crash-reporter \
  --no-first-run \
  --no-default-browser-check \
  "$@"
CHROME
chmod 755 /usr/local/bin/chrome
ln -sfn /usr/local/bin/chrome /usr/local/bin/google-chrome
ln -sfn /usr/local/bin/chrome /usr/local/bin/google-chrome-stable
ln -sfn /usr/local/bin/chrome /usr/local/bin/chromium-browser
ln -sfn /usr/local/bin/chrome /usr/local/bin/chromium-headless

cat > /usr/local/bin/microos-chrome-headless <<'CHROME_HEADLESS'
#!/usr/bin/env bash
exec /usr/local/bin/chrome --headless=new --disable-gpu "$@"
CHROME_HEADLESS
chmod 755 /usr/local/bin/microos-chrome-headless

cat > /usr/local/bin/microos-youtube <<'YOUTUBE'
#!/usr/bin/env bash
exec /usr/local/bin/start-browser.sh --new-window https://www.youtube.com/
YOUTUBE
chmod 755 /usr/local/bin/microos-youtube

# -----------------------------------------------------------------------------
# 7. ZRAM
#    ZRAM is a kernel feature owned by Android. A proot guest shares the host
#    kernel and cannot create or re-configure swap devices (swapon returns
#    EPERM). We install the tools and report the real numbers rather than
#    pretending we can enable it from inside the container.
# -----------------------------------------------------------------------------
stage 88 "Configuring memory"
apt-get install "${APT_OPTS[@]}" zram-tools 2>/dev/null || warn "zram-tools not installed"

if [ -e /sys/block/zram0 ]; then
  log "zram0 is present and managed by the Android kernel"
  if swapon --show 2>/dev/null | grep -q zram; then
    log "Android ZRAM swap is active; the guest shares it"
  else
    log "ZRAM device exists but no swap is active on it"
  fi
else
  log "no zram device exposed on this device"
fi

cat > /usr/local/bin/microos-mem <<'EOF'
#!/bin/sh
echo "Memory (host kernel, shared by the guest):"
awk '/MemTotal|MemAvailable|SwapTotal|SwapFree/ {printf "  %-14s %8.1f MB\n", $1, $2/1024}' /proc/meminfo
echo
echo "ZRAM:"
if [ -e /sys/block/zram0/mm_stat ]; then
  awk '{printf "  original %6.1f MB -> compressed %6.1f MB\n", $1/1048576, $2/1048576}' /sys/block/zram0/mm_stat
else
  echo "  not exposed by this kernel"
fi
EOF
chmod 755 /usr/local/bin/microos-mem

# -----------------------------------------------------------------------------
# 8. TLS certificates + OpenCode agent
# -----------------------------------------------------------------------------
stage 90 "Refreshing TLS certificates"
apt-get install "${APT_OPTS[@]}" ca-certificates || warn "ca-certificates package failed"
update-ca-certificates --fresh || warn "certificate refresh failed; retrying once"
update-ca-certificates || true

stage 91 "Installing OpenCode"
# Keep npm's V8 heap bounded for low-memory Android devices running proot.
# The official installer is preferred; npm is a bounded fallback, not a
# prerequisite for the rest of the Linux environment.
export NODE_OPTIONS="--max-old-space-size=384"
apt-get install "${APT_OPTS[@]}" curl wget unzip tar ca-certificates || warn "OpenCode prerequisites could not all be installed"
mkdir -p "$TMPDIR"
chmod 1777 "$TMPDIR"
update-ca-certificates || true

if ! command -v opencode >/dev/null 2>&1 && [ ! -x /root/.opencode/bin/opencode ]; then
  installed=0
  for attempt in 1 2 3; do
    log "OpenCode installer download attempt $attempt/3"
    rm -f /tmp/opencode-install.sh
    if curl --silent --show-error --fail --location \
        --connect-timeout 15 --max-time 90 --retry 2 --retry-delay 3 \
        --retry-all-errors \
        https://opencode.ai/install --output /tmp/opencode-install.sh \
        && [ -s /tmp/opencode-install.sh ]; then
      log "OpenCode installer downloaded ($(wc -c < /tmp/opencode-install.sh) bytes)"
      if timeout 240 bash /tmp/opencode-install.sh; then
        if command -v opencode >/dev/null 2>&1 || [ -x /root/.opencode/bin/opencode ]; then
          installed=1
          break
        fi
        warn "installer exited successfully but no OpenCode executable was found"
      else
        warn "OpenCode installer failed or timed out on attempt $attempt"
      fi
    else
      warn "OpenCode installer download failed or timed out on attempt $attempt"
    fi
    sleep $((attempt * 5))
  done
  if [ "$installed" -ne 1 ]; then
    warn "OpenCode not installed. Skipping npm fallback to avoid exhausting phone RAM; Linux remains usable."
  fi
fi

# Verify the binary exists; a successful download attempt alone is not proof.
if command -v opencode >/dev/null 2>&1; then
  log "OpenCode verified: $(command -v opencode)"
  opencode --version 2>&1 | head -n 1 || true
elif [ -x /root/.opencode/bin/opencode ]; then
  log "OpenCode verified: /root/.opencode/bin/opencode"
  /root/.opencode/bin/opencode --version 2>&1 | head -n 1 || true
else
  warn "OpenCode verification failed: executable not found; Linux setup will continue without it"
fi

# Give OpenCode a ready-to-use headless browser. The Playwright MCP server is
# installed into the pre-baked image by prebake_rootfs.sh; this configuration
# points it at the native Chromium wrapper and never needs a desktop window.
# Chromium runs with --no-sandbox because Android PRoot has no user namespaces.
mkdir -p /root/.config/opencode
cat > /root/.config/opencode/opencode.json <<'OPENCODE'
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "servers": {
      "playwright": {
        "type": "local",
        "command": [
          "/usr/local/bin/playwright-mcp",
          "--headless",
          "--browser",
          "chromium",
          "--executable-path",
          "/usr/local/bin/chrome",
          "--no-sandbox",
          "--viewport-size",
          "1280x720"
        ],
        "timeout": {
          "startup": 60000,
          "catalog": 60000
        }
      }
    }
  }
}
OPENCODE
chmod 644 /root/.config/opencode/opencode.json

# The TUI uses the same macOS Terminal profile as the shell that launched it.
# The terminal app supplies OPENCODE_CLI_CONFIG_CONTENT per tab; this file is
# the safe default for X11 terminals and for a first `opencode` run.
cat > /root/.config/opencode/cli.json <<'OPENCODE_CLI'
{
  "$schema": "https://opencode.ai/v2/cli.json",
  "theme": {
    "name": "github",
    "mode": "light"
  },
  "highlights": false
}
OPENCODE_CLI
chmod 644 /root/.config/opencode/cli.json

# -----------------------------------------------------------------------------
# 9. Local JAR / Minecraft inspection helper
#    Works on files the user has downloaded to Android shared storage. It does
#    not download, bundle, or redistribute Minecraft game assets.
# -----------------------------------------------------------------------------
stage 93 "Preparing local JAR inspection tools"
cat > /usr/local/bin/microos-jar <<'JAR'
#!/usr/bin/env python3
import pathlib
import stat
import sys
import zipfile

def usage():
    print("Usage:")
    print("  microos-jar inspect <file.jar>")
    print("  microos-jar extract <file.jar> [destination]")
    raise SystemExit(2)

if len(sys.argv) < 3 or sys.argv[1] not in {"inspect", "extract"}:
    usage()

action = sys.argv[1]
source = pathlib.Path(sys.argv[2]).expanduser()
if not source.is_file():
    raise SystemExit(f"File not found: {source}")

try:
    archive = zipfile.ZipFile(source)
except (OSError, zipfile.BadZipFile) as error:
    raise SystemExit(f"Not a readable ZIP/JAR archive: {error}")

with archive:
    entries = archive.infolist()
    assets = [entry for entry in entries if entry.filename.startswith("assets/")]
    total = sum(entry.file_size for entry in entries)
    print(f"Archive: {source}")
    print(f"Entries: {len(entries)}")
    print(f"Uncompressed size: {total:,} bytes")
    print(f"assets/ entries: {len(assets)}")
    if action == "inspect":
        for entry in entries[:80]:
            print(f"{entry.file_size:>12,}  {entry.filename}")
        if len(entries) > 80:
            print(f"... {len(entries) - 80} more entries")
        raise SystemExit(0)

    destination = pathlib.Path(sys.argv[3]).expanduser() if len(sys.argv) > 3 else source.with_name(source.name + ".extracted")
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    written = 0
    for entry in entries:
        name = pathlib.PurePosixPath(entry.filename)
        if name.is_absolute() or ".." in name.parts:
            print(f"Skipping unsafe path: {entry.filename}", file=sys.stderr)
            continue
        mode = entry.external_attr >> 16
        if stat.S_ISLNK(mode):
            print(f"Skipping symlink entry: {entry.filename}", file=sys.stderr)
            continue
        target = (root / pathlib.Path(*name.parts)).resolve()
        if target != root and root not in target.parents:
            print(f"Skipping unsafe path: {entry.filename}", file=sys.stderr)
            continue
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entry) as incoming, target.open("wb") as outgoing:
            while True:
                chunk = incoming.read(1024 * 1024)
                if not chunk:
                    break
                outgoing.write(chunk)
        written += 1
    print(f"Extracted {written} files to: {root}")
JAR
chmod 755 /usr/local/bin/microos-jar

# -----------------------------------------------------------------------------
# 10. Shell defaults, git, projects
# -----------------------------------------------------------------------------
stage 94 "Finalising shell"
cat > /etc/profile.d/microos.sh <<'EOF'
export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color
export DISPLAY=:0
export PULSE_SERVER=unix:/tmp/microos-pulse.sock
export CHROME_BIN=/usr/local/bin/chrome
export CHROME_PATH=/usr/local/bin/chrome
export CHROMIUM_BIN=/usr/local/bin/chrome
export PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/chrome
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
export NODE_PATH=/opt/node-global
[ -d /mnt/android ] && export MICROOS_STORAGE=/mnt/android
EOF
chmod 644 /etc/profile.d/microos.sh

git config --global --add safe.directory '*'
git config --global init.defaultBranch main
git config --global credential.helper store
git config --global user.name "MicroOS User" 2>/dev/null
git config --global user.email "microos@localhost" 2>/dev/null

cat >> /root/.bashrc <<'EOF'

# --- MicroOS ---------------------------------------------------------------
export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"
export DISPLAY=:0
export PULSE_SERVER=unix:/tmp/microos-pulse.sock
export CHROME_BIN=/usr/local/bin/chrome
export CHROME_PATH=/usr/local/bin/chrome
export CHROMIUM_BIN=/usr/local/bin/chrome
export PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/chrome
export XCURSOR_THEME=WhiteSur-cursors
export XCURSOR_SIZE=24
export PS1='\[\e[38;5;39m\]\u@microos\[\e[0m\]:\[\e[38;5;114m\]\w\[\e[0m\]\$ '
command -v microos-mem >/dev/null && :
alias ll='ls -alF'
[ -d /mnt/android ] && alias phone='cd /mnt/android'
[ -z "$MICROOS_BANNER_SHOWN" ] && [ -n "$PS1" ] && {
  export MICROOS_BANNER_SHOWN=1
  printf '\n  MicroOS · Ubuntu 24.04 · %s\n' "$(uname -m)"
  printf '  /mnt/android = phone storage · opencode · gh · rustc · node\n\n'
}
EOF

# -----------------------------------------------------------------------------
# 11. Display bridge + browser launcher
# -----------------------------------------------------------------------------
stage 96 "Writing display bridge"
cat > /root/.microos/start-gui.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="${DISPLAY:-:0}"
export XCURSOR_THEME=WhiteSur-cursors
export XCURSOR_SIZE=24
export PULSE_SERVER=unix:/tmp/microos-pulse.sock
export XDG_RUNTIME_DIR=/tmp/microos-runtime
GEOMETRY="${MICROOS_DESKTOP_GEOMETRY:-1280x720x24}"
SOCKET=/tmp/microos-x11.sock
AUDIO_SOCKET=/tmp/microos-audio.sock
AUDIO_FIFO=/tmp/microos-audio.pcm
LOG=/tmp/.microos
mkdir -p "$LOG" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
for process in microos-audio microos-xbridge pulseaudio openbox Xvfb; do
  pkill -9 -x "$process" 2>/dev/null || true
done
# Chromium/Firefox keep separate processes and a singleton profile lock. Kill
# them with the old X server so a restarted desktop always gets a fresh window.
pkill -9 -u microos-browser -f 'chromium|firefox' 2>/dev/null || true
sleep 0.5
rm -f "$SOCKET" "$AUDIO_SOCKET" "$AUDIO_FIFO" /tmp/microos-pulse.sock

# Audio comes up first: the bridge creates the FIFO, then PulseAudio opens its
# pipe sink. This order prevents the sink from blocking on a missing reader.
if [ -x /usr/local/bin/microos-audio ]; then
  microos-audio --socket "$AUDIO_SOCKET" --fifo "$AUDIO_FIFO" >"$LOG/audio.log" 2>&1 &
  AUDIO_PID=$!
  for _ in $(seq 1 40); do
    [ -S "$AUDIO_SOCKET" ] && [ -p "$AUDIO_FIFO" ] && break
    sleep 0.1
  done
fi
if command -v pulseaudio >/dev/null 2>&1; then
  pulseaudio -n -F /etc/pulse/microos.pa --daemonize=no --exit-idle-time=-1 \
    --disable-shm --log-target=stderr >"$LOG/pulse.log" 2>&1 &
  PULSE_PID=$!
  for _ in $(seq 1 40); do
    [ -S /tmp/microos-pulse.sock ] && break
    sleep 0.1
  done
  if [ ! -S /tmp/microos-pulse.sock ]; then
    echo "[microos] WARN: PulseAudio did not start; inspect $LOG/pulse.log" >&2
  fi
fi

Xvfb "$DISPLAY" -screen 0 "$GEOMETRY" -nolisten tcp -ac -noreset -dpi 96 >"$LOG/xvfb.log" 2>&1 &
XVFB_PID=$!
cleanup() {
  kill ${PULSE_PID:-} ${AUDIO_PID:-} ${BRIDGE_PID:-} ${OPENBOX_PID:-} ${PCMANFM_PID:-} "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
wait_for_x() { for _ in $(seq 1 60); do xset -display "$DISPLAY" q >/dev/null 2>&1 && return 0; kill -0 "$XVFB_PID" 2>/dev/null || { cat "$LOG/xvfb.log" >&2 || true; return 1; }; sleep 0.2; done; return 1; }
if ! wait_for_x; then echo "[microos] ERROR: Xvfb $DISPLAY did not become usable" >&2; exit 1; fi
xrdb -merge /root/.Xresources 2>/dev/null || true
xsetroot -solid '#0f131b' -cursor_name left_ptr 2>/dev/null || true
mkdir -p /root/.config/openbox
cat > /root/.config/openbox/menu.xml <<'MENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu><menu id="root-menu" label="MicroOS">
<item label="Chromium"><action name="Execute"><command>/usr/local/bin/start-browser.sh</command></action></item>
<item label="YouTube"><action name="Execute"><command>/usr/local/bin/microos-youtube</command></action></item>
<item label="Terminal"><action name="Execute"><command>xterm -fa Monospace -fs 10</command></action></item>
<separator/>
<item label="Files"><action name="Execute"><command>pcmanfm</command></action></item>
<item label="Text Editor"><action name="Execute"><command>mousepad</command></action></item>
<item label="Calculator"><action name="Execute"><command>galculator</command></action></item>
<item label="Archive Manager"><action name="Execute"><command>file-roller</command></action></item>
<item label="Image Viewer"><action name="Execute"><command>ristretto</command></action></item>
<item label="Document Viewer"><action name="Execute"><command>evince</command></action></item>
<separator/>
<item label="Blender"><action name="Execute"><command>blender</command></action></item>
<item label="GIMP"><action name="Execute"><command>gimp</command></action></item>
<item label="Inkscape"><action name="Execute"><command>inkscape</command></action></item>
<item label="VLC"><action name="Execute"><command>vlc</command></action></item>
<item label="LibreOffice Writer"><action name="Execute"><command>libreoffice --writer</command></action></item>
<item label="LibreOffice Calc"><action name="Execute"><command>libreoffice --calc</command></action></item>
<separator/>
<item label="Git Cola"><action name="Execute"><command>git-cola</command></action></item>
<item label="Gitg"><action name="Execute"><command>gitg</command></action></item>
<item label="Geany"><action name="Execute"><command>geany</command></action></item>
<item label="SQLite Browser"><action name="Execute"><command>sqlitebrowser</command></action></item>
</menu></openbox_menu>
MENU
DISPLAY="$DISPLAY" openbox --sm-disable >"$LOG/openbox.log" 2>&1 &
OPENBOX_PID=$!
# Draw the real application icons from /root/Desktop. pcmanfm uses the
# hicolor artwork installed by setup.sh, so the X11 desktop matches Launchpad.
mkdir -p /root/.config/pcmanfm/default
cat > /root/.config/pcmanfm/default/pcmanfm.conf <<'PCMANFM'
[desktop]
wallpaper_mode=color
bg_color=#0F131B
show_desktop=1
show_wm_menu=1
PCMANFM
PCMANFM_PID=
if command -v pcmanfm >/dev/null 2>&1; then
  DISPLAY="$DISPLAY" pcmanfm --desktop --profile=default --wallpaper-mode=color \
    >"$LOG/pcmanfm.log" 2>&1 &
  PCMANFM_PID=$!
  sleep 0.8
fi
if [ ! -x /usr/local/bin/microos-xbridge ]; then
  echo "[microos] ERROR: native X11 bridge is missing" >&2
  exit 1
fi
microos-xbridge --display "$DISPLAY" --socket "$SOCKET" >"$LOG/xbridge.log" 2>&1 &
BRIDGE_PID=$!
for _ in $(seq 1 80); do
  [ -S "$SOCKET" ] && kill -0 "$BRIDGE_PID" 2>/dev/null && break
  sleep 0.25
done
if [ ! -S "$SOCKET" ] || ! kill -0 "$BRIDGE_PID" 2>/dev/null; then
  echo "[microos] ERROR: native X11 bridge did not create $SOCKET" >&2
  cat "$LOG/xbridge.log" >&2 || true
  exit 1
fi
if ! pgrep -u microos-browser -f 'chromium|firefox' >/dev/null 2>&1; then /usr/local/bin/start-browser.sh --new-window chrome://newtab/ >"$LOG/chromium.log" 2>&1 & fi
echo "[microos] native display $DISPLAY ready (Xvfb $GEOMETRY, Openbox, socket $SOCKET, audio $AUDIO_SOCKET)"
while kill -0 "$XVFB_PID" 2>/dev/null && kill -0 "$BRIDGE_PID" 2>/dev/null && kill -0 "$OPENBOX_PID" 2>/dev/null; do sleep 2; done
echo "[microos] ERROR: native X11 process exited; inspect $LOG/*.log" >&2
exit 1
EOF
chmod 755 /root/.microos/start-gui.sh
ln -sf /root/.microos/start-gui.sh /root/.microos/start-desktop.sh

cat > /root/.microos/stop-gui.sh <<'EOF'
#!/usr/bin/env bash
pkill -x microos-audio 2>/dev/null || true
pkill -x pulseaudio 2>/dev/null || true
pkill -x microos-xbridge 2>/dev/null || true
pkill -x openbox 2>/dev/null || true
pkill -x Xvfb 2>/dev/null || true
rm -f /tmp/microos-x11.sock /tmp/microos-audio.sock /tmp/microos-audio.pcm /tmp/microos-pulse.sock
echo "[microos] display and audio stopped"
EOF
chmod 755 /root/.microos/stop-gui.sh

# Chromium is launched through the unprivileged ARM64 wrapper above.

# Optional Steam/Box64 feasibility check. This intentionally does not install
# Steam or alter the guest: the Steam Linux client has 32-bit components and
# needs a compatible Box86/Box32 path in addition to Box64.
cat > /usr/local/bin/microos-steam-check <<'STEAMCHECK'
#!/usr/bin/env bash
set -u
echo "MicroOS Steam compatibility check"
echo "Guest architecture: $(dpkg --print-architecture 2>/dev/null || uname -m)"
if command -v box64 >/dev/null 2>&1; then
  echo "Box64: $(box64 --version 2>&1 | head -n 1)"
else
  echo "Box64: not installed"
fi
if command -v box86 >/dev/null 2>&1; then
  echo "Box86: $(box86 --version 2>&1 | head -n 1)"
else
  echo "Box86/Box32: not installed"
fi
echo
echo "Steam package availability:"
apt-cache policy steam 2>/dev/null | sed -n '1,8p' || true
echo
echo "No Steam install was attempted. Do not assume Box64 alone is enough:"
echo "Steam's Linux client includes 32-bit components and Chromium/CEF processes."
echo "A real test also needs compatible 32-bit userspace libraries, graphics"
echo "drivers, and a working display/audio stack. PRoot may impose further limits."
STEAMCHECK
chmod 755 /usr/local/bin/microos-steam-check

# -----------------------------------------------------------------------------
# 12. Trim the image
# -----------------------------------------------------------------------------
stage 98 "Cleaning up"
apt-get autoremove -y >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* 2>/dev/null || true
find /usr/share/locale -mindepth 1 -maxdepth 1 \
     ! -name 'en' ! -name 'en_US' ! -name 'C' -exec rm -rf {} + 2>/dev/null || true
rm -f /tmp/opencode-install.sh /tmp/nodesource.sh

printf '[stage] Linux ready\n[progress] 100\n' 
touch /root/.microos/ready
log "setup complete — footprint: $(du -sh / 2>/dev/null | cut -f1)"
exit 0
