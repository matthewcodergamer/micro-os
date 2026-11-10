#!/usr/bin/env bash
# =============================================================================
# Generates the Android platform folder with the current Flutter SDK and applies
# the MicroOS-specific settings that the default template does not have.
#
# Generating (rather than committing) android/ keeps the Gradle/AGP/Kotlin
# template in sync with whatever Flutter version builds the APK.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

flutter create \
  --platforms=android \
  --org com.matthewcodergamer \
  --project-name micro_os \
  --description "MicroOS - native mobile Linux workstation" \
  . >/dev/null

rm -f test/widget_test.dart

python3 - "$ROOT" <<'PY'
import os, re, sys

root = sys.argv[1]
manifest = os.path.join(root, "android/app/src/main/AndroidManifest.xml")
gradle_kts = os.path.join(root, "android/app/build.gradle.kts")
gradle_groovy = os.path.join(root, "android/app/build.gradle")

# ---- Manifest ---------------------------------------------------------------
with open(manifest) as f:
    xml = f.read()

permissions = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
"""
if "MANAGE_EXTERNAL_STORAGE" not in xml:
    xml = re.sub(r"(<manifest[^>]*>)", r"\1\n" + permissions, xml, count=1)

xml = xml.replace('android:label="micro_os"', 'android:label="MicroOS"')

if "usesCleartextTraffic" not in xml:
    xml = xml.replace(
        "<application",
        '<application\n        android:usesCleartextTraffic="true"\n        android:largeHeap="true"',
        1,
    )

# Impeller is the default on modern Flutter, but pinning it makes the intent
# explicit and keeps the X11 surface from falling back to the legacy renderer.
if "EnableImpeller" not in xml:
    xml = xml.replace(
        "</application>",
        '        <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="true"/>\n    </application>',
        1,
    )

with open(manifest, "w") as f:
    f.write(xml)

# ---- Gradle: minSdk 26, targetSdk 28 ---------------------------------------
# targetSdk 28 is deliberate and is what Termux does: Android 10+ forbids
# execve() of files inside the app data dir for targetSdk >= 29, and the proot
# rootfs lives there. This is a sideload-only build.
target = gradle_kts if os.path.exists(gradle_kts) else gradle_groovy
with open(target) as f:
    g = f.read()

g = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 26", g)
g = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 26", g)
g = re.sub(r"targetSdk\s*=\s*flutter\.targetSdkVersion", "targetSdk = 28", g)
g = re.sub(r"targetSdkVersion\s+flutter\.targetSdkVersion", "targetSdkVersion 28", g)

# Pin the NDK to the version the workflow installs, whichever form the
# template uses.
g = re.sub(r'ndkVersion\s*=\s*flutter\.ndkVersion',
           'ndkVersion = "27.0.12077973"', g)
g = re.sub(r'ndkVersion\s+flutter\.ndkVersion',
           'ndkVersion "27.0.12077973"', g)

if "ndkVersion" not in g:
    g = re.sub(r"(compileSdk\s*=\s*flutter\.compileSdkVersion)",
               r"\1\n    ndkVersion = \"27.0.12077973\"", g, count=1)
    g = re.sub(r"(compileSdkVersion\s+flutter\.compileSdkVersion)",
               r"\1\n    ndkVersion \"27.0.12077973\"", g, count=1)

# Release builds already use the debug signing key in the Flutter template,
# which is exactly what a sideload-only APK needs.

with open(target, "w") as f:
    f.write(g)

print("patched:", manifest)
print("patched:", target)
PY

grep -q "targetSdk = 28\|targetSdkVersion 28" android/app/build.gradle.kts android/app/build.gradle 2>/dev/null \
  || { echo "!! could not patch targetSdk, inspect android/app/build.gradle*"; exit 1; }

echo "==> android project ready"
