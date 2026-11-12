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
export LANG=C.UTF-8
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

mkdir -p /root/.microos /root/projects /root/.local/bin /root/.config

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
  ca-certificates curl wget gnupg apt-utils \
  git git-lfs openssh-client \
  build-essential pkg-config make cmake openjdk-21-jdk-headless \
  python3 python3-pip python3-venv python3-dev \
  unzip zip xz-utils tar less nano vim-tiny \
  procps file jq tmux sudo \
  || warn "some core packages failed to install"

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
# 4. X11 stack + window manager + VNC bridge
# -----------------------------------------------------------------------------
stage 76 "Installing X11 and VNC"
apt-get install "${APT_OPTS[@]}" \
  xvfb openbox xterm x11-xserver-utils x11vnc novnc websockify xauth dbus-x11 \
  libgl1-mesa-dri mesa-utils \
  fonts-dejavu-core fonts-liberation \
  || warn "some X11 packages failed to install"

# macOS-inspired X11 pointer theme (WhiteSur Cursors, upstream GPL-3.0).
# This affects X11 applications in the VNC desktop; it does not change the
# Android host pointer or create a pointer overlay for touch-only screens.
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
#    Firefox is downloaded from Mozilla and baked into the ARM64 rootfs by
#    tool/prebake_rootfs.sh. Run it as a dedicated unprivileged guest user:
#    Firefox intentionally refuses to run as root, and its profile must not
#    be owned by the proot root account.
# -----------------------------------------------------------------------------
stage 84 "Preparing Firefox desktop browser"
apt-get install "${APT_OPTS[@]}" passwd util-linux || warn "browser user tools unavailable"
if ! id microos-browser >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /home/microos-browser \
    --shell /usr/sbin/nologin microos-browser || warn "could not create Firefox user"
fi

cat > /usr/local/bin/microos-browse <<'BROWSER'
#!/usr/bin/env bash
set -euo pipefail
export DISPLAY="${DISPLAY:-:1}"

if command -v firefox >/dev/null 2>&1; then
  # PRoot runs the desktop as guest root. Firefox must run as a normal user.
  # The rootfs archive normalizes ownership to root, so give the browser a
  # persistent, explicitly writable profile home inside the guest instead.
  BROWSER_HOME=/home/microos-browser
  # Ensure the normalized rootfs home is writable by the browser account.
  # Firefox manages its default profile beneath HOME/.mozilla itself.
  install -d -o microos-browser -g microos-browser -m 700 \
    "$BROWSER_HOME" "$BROWSER_HOME/.mozilla" "$BROWSER_HOME/.cache"
  exec runuser -u microos-browser -- env \
    DISPLAY="$DISPLAY" \
    HOME="$BROWSER_HOME" \
    MOZ_DISABLE_CONTENT_SANDBOX=1 \
    MOZ_DISABLE_GMP_SANDBOX=1 \
    firefox --display=:1 "$@"
fi

echo "Firefox is missing from this MicroOS image. Reinstall/update MicroOS with a pre-baked Firefox build." >&2
exit 127
BROWSER
chmod 755 /usr/local/bin/microos-browse

# -----------------------------------------------------------------------------
# 6. ZRAM
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
# 7. TLS certificates + OpenCode agent
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

# -----------------------------------------------------------------------------
# 8. Local JAR / Minecraft inspection helper
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
# 9. Shell defaults, git, projects
# -----------------------------------------------------------------------------
stage 94 "Finalising shell"
cat > /etc/profile.d/microos.sh <<'EOF'
export PATH="/root/.opencode/bin:/root/.local/bin:$PATH"
export LANG=C.UTF-8
export TERM=xterm-256color
export DISPLAY=:1
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
export DISPLAY=:1
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
# 10. Display bridge + browser launcher
# -----------------------------------------------------------------------------
stage 96 "Writing display bridge"
cat > /root/.microos/start-gui.sh <<'EOF'
#!/usr/bin/env bash
# Supervise the complete X11 -> VNC -> noVNC chain for the Android WebView.
set -Eeuo pipefail
export DISPLAY=:1
export XCURSOR_THEME=WhiteSur-cursors
export XCURSOR_SIZE=24
export XDG_RUNTIME_DIR=/tmp/microos-runtime
GEOMETRY="${MICROOS_GEOMETRY:-1024x768x24}"
LOG=/tmp/.microos
mkdir -p "$LOG" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Stop stale servers by executable name. Avoid pkill -f patterns that can
# accidentally match this shell or another launcher command line.
pkill -x websockify 2>/dev/null || true
pkill -x x11vnc 2>/dev/null || true
pkill -x openbox 2>/dev/null || true
pkill -x Xvfb 2>/dev/null || true
sleep 0.4

Xvfb :1 -screen 0 "$GEOMETRY" -nolisten tcp -ac -noreset -dpi 96 >"$LOG/xvfb.log" 2>&1 &
XVFB_PID=$!
cleanup() {
  kill "${WEBSOCKIFY_PID:-}" "${VNC_PID:-}" "${OPENBOX_PID:-}" "$XVFB_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Do not start the next layer until the X server answers real X11 requests.
for _ in $(seq 1 50); do
  if xset -display :1 q >/dev/null 2>&1; then break; fi
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    echo "[microos] ERROR: Xvfb exited during startup" >&2
    cat "$LOG/xvfb.log" >&2 || true
    exit 1
  fi
  sleep 0.2
done
if ! xset -display :1 q >"$LOG/xset.log" 2>&1; then
  echo "[microos] ERROR: Xvfb :1 did not become usable" >&2
  cat "$LOG/xvfb.log" >&2 || true
  exit 1
fi

xrdb -merge /root/.Xresources 2>/dev/null || true
xsetroot -solid '#0f131b' -cursor_name left_ptr 2>/dev/null || xsetroot -solid '#0f131b' 2>/dev/null || true

mkdir -p /root/.config/openbox
cat > /root/.config/openbox/menu.xml <<'MENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="MicroOS">
    <item label="Terminal"><action name="Execute"><command>xterm -fa Monospace -fs 10</command></action></item>
    <item label="Firefox"><action name="Execute"><command>/usr/local/bin/microos-browse</command></action></item>
    <item label="OpenCode"><action name="Execute"><command>xterm -fa Monospace -fs 10 -e opencode</command></action></item>
    <separator/>
    <item label="Restart window manager"><action name="Restart"/></item>
  </menu>
</openbox_menu>
MENU
openbox >"$LOG/openbox.log" 2>&1 &
OPENBOX_PID=$!

wait_for_port() {
  local port="$1" attempts="$2"
  for ((i=0; i<attempts; i++)); do
    if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then return 0; fi
    sleep 0.25
  done
  return 1
}

# Disable XDamage and MIT-SHM: both can be unreliable in a proot/Xvfb stack.
x11vnc -display :1 -forever -shared -rfbport 5900 -localhost -nopw \
       -noxdamage -noshm -repeat -wait 15 -defer 15 \
       >"$LOG/x11vnc.log" 2>&1 &
VNC_PID=$!
if ! wait_for_port 5900 60 || ! kill -0 "$VNC_PID" 2>/dev/null; then
  echo "[microos] ERROR: x11vnc failed; port 5900 is unavailable" >&2
  cat "$LOG/x11vnc.log" >&2 || true
  exit 1
fi

if [ ! -f /usr/share/novnc/vnc.html ]; then
  echo "[microos] ERROR: noVNC web client is missing (/usr/share/novnc/vnc.html)" >&2
  exit 1
fi
websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 >"$LOG/websockify.log" 2>&1 &
WEBSOCKIFY_PID=$!
if ! wait_for_port 6080 60 || ! kill -0 "$WEBSOCKIFY_PID" 2>/dev/null; then
  echo "[microos] ERROR: noVNC bridge failed; port 6080 is unavailable" >&2
  cat "$LOG/websockify.log" >&2 || true
  cat "$LOG/x11vnc.log" >&2 || true
  exit 1
fi

# Launch Firefox only after Xvfb, VNC and noVNC are accepting connections.
if ! pgrep -u microos-browser -f 'firefox' >/dev/null 2>&1; then
  /usr/local/bin/microos-browse --new-window about:home >"$LOG/firefox.log" 2>&1 &
  FIREFOX_PID=$!
fi

# Keep the parent alive only while every layer remains alive. This prevents a
# dead x11vnc from leaving a misleading, still-open noVNC HTTP port.
echo "[microos] display :1 ready (Xvfb, VNC 5900, noVNC 6080)"
while kill -0 "$XVFB_PID" 2>/dev/null &&
      kill -0 "$VNC_PID" 2>/dev/null &&
      kill -0 "$WEBSOCKIFY_PID" 2>/dev/null; do
  sleep 2
done
echo "[microos] ERROR: one of Xvfb/x11vnc/websockify exited; see $LOG/*.log" >&2
exit 1
EOF
chmod 755 /root/.microos/start-gui.sh
ln -sf /root/.microos/start-gui.sh /root/.microos/start-desktop.sh

cat > /root/.microos/stop-gui.sh <<'EOF'
#!/usr/bin/env bash
pkill -x websockify 2>/dev/null || true
pkill -x x11vnc 2>/dev/null || true
pkill -x openbox 2>/dev/null || true
pkill -x Xvfb 2>/dev/null || true
echo "[microos] display stopped"
EOF
chmod 755 /root/.microos/stop-gui.sh

# Browser launcher was installed above with the Firefox-first, unprivileged-user wrapper.

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
# 11. Trim the image
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
