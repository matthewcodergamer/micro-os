#!/usr/bin/env bash
# =============================================================================
# Generates the iOS platform folder for the unsigned .ipa build.
#
# Important: iOS cannot run the proot guest. Apple does not allow an app to
# spawn binaries it ships, so the Linux backend is Android-only. This target
# builds the same desktop shell so the UI can be developed and side-loaded, and
# so the remote-host backend (SSH to a real Linux box) has somewhere to live.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

flutter create \
  --platforms=ios \
  --org com.matthewcodergamer \
  --project-name micro_os \
  --description "MicroOS - native mobile Linux workstation" \
  . >/dev/null

PLIST="ios/Runner/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName MicroOS" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string MicroOS" "$PLIST"

# The noVNC client talks to 127.0.0.1 over plain HTTP when a local helper is
# available, and to a LAN host in the remote-backend mode.
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity dict" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NSAppTransportSecurity:NSAllowsLocalNetworking true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string MicroOS connects to your Linux host on the local network." "$PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :NSLocalNetworkUsageDescription \"MicroOS connects to your Linux host on the local network.\"" "$PLIST"

echo "==> ios project ready"
