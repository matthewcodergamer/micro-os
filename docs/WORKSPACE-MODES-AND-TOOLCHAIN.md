# Workspace Modes and Developer Toolchain

## One Linux guest, two interaction profiles

Misty OS keeps one Ubuntu 24.04 ARM64 PRoot installation and changes the shell's input/layout profile. It must not duplicate the root filesystem or create separate app/data stores.

### Desktop Mode

- Pointer-first interaction with a visible remote cursor.
- Relative finger movement through the virtual trackpad, plus click/context-menu gestures.
- Optimized for a Bluetooth/USB mouse, trackpad and physical keyboard.
- Full desktop window controls, selection, drag/drop and keyboard shortcuts.

### Mobile Desktop

- Touch-first interaction with direct touch-to-screen positioning.
- Larger touch targets, reduced chrome density and responsive window sizing.
- Android soft keyboard remains the primary text-entry path.
- Same Linux apps, home directory, files, sessions and browser profile.

The first-run chooser appears after the Linux guest is ready. The saved selection can be changed in **System Settings → Trackpad & Pointer → Workspace experience**. The mode selector also configures the pointer mapping; the separate Trackpad mode switch remains available as an advanced override.

## Browser architecture

The guest uses the official Google Chrome Stable ARM64 package in a normal X11 desktop window, with Firefox available as an alternate engine. This is the full browser application surface (tabs, address bar, bookmarks, Google account sign-in and normal browser controls), not a web page pretending to be a browser. The build verifies the package architecture and native executable before exporting the rootfs. Do not replace the native ARM64 package with Chromium Snap inside PRoot.

Browser rendering, VNC transport and network throughput are measured separately. A healthy noVNC page alone is not proof that the remote desktop rendered; the integration test checks actual framebuffer pixels and WebSocket traffic.

## Preinstalled developer and reverse-engineering tools

The Ubuntu provisioning step installs available ARM64 packages for:

- Java 17 and Java 21, Python 3, Git, unzip, wget, build tools, Node.js and Rust.
- Android platform tools: `adb`, `fastboot`.
- APK inspection: `jadx`, `apktool`, `apkid`.
- Dynamic analysis: `frida`, `frida-ps`, `frida-ls-devices`, `objection`.
- Traffic inspection: `mitmproxy`.
- 3D creation: `blender`.
- Web testing: `curl`, `wget`, Playwright and its headless Chromium runtime.
- AI coding: the official OpenCode installer is rerun during provisioning to refresh an existing installation; the existing binary is retained if the network is unavailable.
- Burp Suite Community: native Linux ARM64 installer, downloaded with a pinned SHA-256 check before silent installation.

Python security utilities are installed into `/opt/microos-security-tools` rather than Ubuntu's externally managed system Python. This avoids `pip` breaking distro-managed Python packages.

### Android host commands versus guest commands

Commands such as `grep`, `cp`, `find` and `unzip` run directly inside Ubuntu against guest files and mounted shared storage. Android's `pm` command belongs to the Android host, not the PRoot guest. Use ADB to invoke it on the host, for example:

```bash
adb devices
adb shell pm path com.dianyun.chikii
```

Copying a protected path under `/data/app` may still be denied by Android's app sandbox unless the device grants the required access. ADB installation does not bypass Android permissions or make the PRoot guest root on the host.

## OpenCode sessions

The Terminal app supports multiple independent terminal tabs. OpenCode also has its own persistent session manager: use `/new` to start a separate conversation and `/sessions` to list and resume saved conversations. Its TUI also supports session tabs and switching shortcuts; those are OpenCode features, separate from the OS terminal tabs.

## Performance and device constraints

Misty OS targets ARM64 Android devices, including low-memory 4 GB phones. Installing a tool does not mean every workload is suitable to run concurrently. Blender and Burp Suite are large desktop applications; close other heavy apps and keep memory headroom. Burp's published minimum is 4 GB RAM, so a 4 GB phone is at the minimum before Android, PRoot, VNC and other applications are counted. Hardware GPU acceleration is not guaranteed inside PRoot/X11; Blender may use a software rendering path.

The guest is Ubuntu userspace under PRoot, not a separate Linux kernel. It does not gain Android host root, kernel modules, systemd, kernel ZRAM control or unrestricted access to `/data/app`.
