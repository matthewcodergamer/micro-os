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
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\nnameserver 9.9.9.9\n' > /etc/resolv.conf

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
  build-essential pkg-config make cmake \
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

# -----------------------------------------------------------------------------
# 5. Browser
#    Ubuntu arm64 ships Chromium only as a snap, and snaps cannot run in proot.
#    Falkon is a real .deb desktop browser built on QtWebEngine (Chromium's
#    Blink + V8), so it is the dependable default. If a genuine Chromium .deb
#    is ever available it is preferred automatically by microos-browse.
# -----------------------------------------------------------------------------
stage 84 "Installing desktop browser"
# Do not install Ubuntu's chromium transitional package: on arm64 it
# points to Snap, and snapd cannot operate inside this proot guest.
apt-get install "${APT_OPTS[@]}" falkon || warn "Falkon/QtWebEngine install failed"

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
# 8. Shell defaults, git, projects
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
# 9. Display bridge + browser launcher
# -----------------------------------------------------------------------------
stage 96 "Writing display bridge"
cat > /root/.microos/start-gui.sh <<'EOF'
#!/usr/bin/env bash
# Xvfb + openbox + x11vnc + noVNC. The Flutter app renders noVNC in a window.
set -uo pipefail
export DISPLAY=:1
GEOMETRY="${MICROOS_GEOMETRY:-1024x768x24}"
LOG=/tmp/.microos
mkdir -p "$LOG"

pkill -f 'Xvfb :1'            2>/dev/null
pkill -f 'x11vnc -display :1' 2>/dev/null
pkill -f 'websockify.*6080'   2>/dev/null
pkill -x openbox              2>/dev/null
sleep 0.5

Xvfb :1 -screen 0 "$GEOMETRY" -nolisten tcp -dpi 96 >"$LOG/xvfb.log" 2>&1 &
sleep 1.2

xsetroot -solid '#0f131b' 2>/dev/null

# Minimal openbox config so the desktop has a right-click menu.
mkdir -p /root/.config/openbox
cat > /root/.config/openbox/menu.xml <<'MENU'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu>
  <menu id="root-menu" label="MicroOS">
    <item label="Terminal"><action name="Execute"><command>xterm -fa Monospace -fs 10</command></action></item>
    <item label="Browser"><action name="Execute"><command>/usr/local/bin/microos-browse</command></action></item>
    <item label="OpenCode"><action name="Execute"><command>xterm -fa Monospace -fs 10 -e opencode</command></action></item>
    <separator/>
    <item label="Restart window manager"><action name="Restart"/></item>
  </menu>
</openbox_menu>
MENU
openbox >"$LOG/openbox.log" 2>&1 &

x11vnc -display :1 -forever -shared -rfbport 5900 -localhost -nopw \
       -repeat -wait 15 -defer 15 >"$LOG/x11vnc.log" 2>&1 &
sleep 0.8

if [ -d /usr/share/novnc ]; then
  websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 >"$LOG/websockify.log" 2>&1 &
else
  echo "[microos] noVNC missing; only raw VNC on 5900 is available" >&2
fi

echo "[microos] display :1 ready"
wait
EOF
chmod 755 /root/.microos/start-gui.sh

cat > /root/.microos/stop-gui.sh <<'EOF'
#!/usr/bin/env bash
pkill -f 'websockify.*6080'   2>/dev/null
pkill -f 'x11vnc -display :1' 2>/dev/null
pkill -x openbox              2>/dev/null
pkill -f 'Xvfb :1'            2>/dev/null
echo "[microos] display stopped"
EOF
chmod 755 /root/.microos/stop-gui.sh

# The browser launcher. Flags are the memory-conservative set requested for
# low-RAM phones; --single-process is opt-in because upstream deprecated it and
# it crashes on many sites.
cat > /usr/local/bin/microos-browse <<'EOF'
#!/usr/bin/env bash
set -u
export DISPLAY="${DISPLAY:-:1}"
export QTWEBENGINE_DISABLE_SANDBOX=1

BASE_FLAGS=(
  --no-sandbox
  --disable-gpu-sandbox
  --disable-dev-shm-usage
  --disable-background-networking
  --process-per-site
  --renderer-process-limit=1
  --js-flags=--max-old-space-size=512
)
[ "${MICROOS_SINGLE_PROCESS:-0}" = "1" ] && BASE_FLAGS+=(--single-process)

export QTWEBENGINE_CHROMIUM_FLAGS="${BASE_FLAGS[*]}"

URL="${1:-}"
if command -v falkon >/dev/null 2>&1; then
  exec falkon ${URL:+"$URL"}
elif command -v chromium >/dev/null 2>&1; then
  exec chromium "${BASE_FLAGS[@]}" ${URL:+"$URL"}
elif command -v chromium-browser >/dev/null 2>&1; then
  exec chromium-browser "${BASE_FLAGS[@]}" ${URL:+"$URL"}
fi
echo "No desktop browser is installed. Run: apt-get install falkon" >&2
exit 1
EOF
chmod 755 /usr/local/bin/microos-browse

# -----------------------------------------------------------------------------
# 10. Trim the image
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
