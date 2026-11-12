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

# ---- Stream large bundled assets through Android AssetManager ---------------
# Flutter's rootBundle.load() materializes a whole asset in Dart memory. The
# pre-baked rootfs is hundreds of MB, so copy it to app-private storage using a
# native 64 KiB buffer on a worker thread instead.
MAIN_ACTIVITY="android/app/src/main/kotlin/com/matthewcodergamer/micro_os/MainActivity.kt"
mkdir -p "$(dirname "$MAIN_ACTIVITY")"
cat > "$MAIN_ACTIVITY" <<'KOTLIN'
package com.matthewcodergamer.micro_os

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val assetCopyExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "microos/rootfs")
            .setMethodCallHandler { call, result ->
                if (call.method != "copyAssetToFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val assetPath = call.argument<String>("assetPath")
                val destinationPath = call.argument<String>("destinationPath")
                if (assetPath.isNullOrBlank() || destinationPath.isNullOrBlank()) {
                    result.error("INVALID_ARGUMENT", "assetPath and destinationPath are required", null)
                    return@setMethodCallHandler
                }

                assetCopyExecutor.execute {
                    try {
                        val destination = File(destinationPath)
                        destination.parentFile?.mkdirs()
                        assets.open(assetPath).use { input ->
                            FileOutputStream(destination).use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    output.write(buffer, 0, count)
                                }
                                output.fd.sync()
                            }
                        }
                        runOnUiThread { result.success(destination.length()) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("ASSET_COPY_FAILED", error.message, null)
                        }
                    }
                }
            }
    }

    override fun onDestroy() {
        assetCopyExecutor.shutdown()
        super.onDestroy()
    }
}
KOTLIN

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

# Android 11+ only exposes installed TTS engines when this service query exists.
if "android.intent.action.TTS_SERVICE" not in xml:
    xml = xml.replace(
        "<application",
        """    <queries>
        <intent>
            <action android:name="android.intent.action.TTS_SERVICE"/>
        </intent>
    </queries>
    <application""",
        1,
    )

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

# ---- Adaptive launcher icon -------------------------------------------------
# android/ is generated during CI, so create the icon resources after flutter create.
res = os.path.join(root, "android/app/src/main/res")
os.makedirs(os.path.join(res, "mipmap-anydpi-v26"), exist_ok=True)
os.makedirs(os.path.join(res, "drawable"), exist_ok=True)
os.makedirs(os.path.join(res, "values"), exist_ok=True)

with open(os.path.join(res, "mipmap-anydpi-v26/ic_launcher.xml"), "w") as f:
    f.write("""<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/microos_icon_background"/>
    <foreground android:drawable="@drawable/microos_icon_foreground"/>
</adaptive-icon>
""")

with open(os.path.join(res, "drawable/microos_icon_foreground.xml"), "w") as f:
    f.write("""<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#00000000" android:strokeColor="#FFFFFFFF"
        android:strokeWidth="4" android:strokeLineCap="round"
        android:strokeLineJoin="round"
        android:pathData="M24,29 Q24,24 29,24 L79,24 Q84,24 84,29 L84,75 Q84,80 79,80 L29,80 Q24,80 24,75 Z"/>
    <path android:fillColor="#FF66B7FF"
        android:pathData="M37,43 L47,52 L37,61 L41,65 L55,52 L41,39 Z"/>
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M59,62 L75,62 L75,67 L59,67 Z"/>
    <path android:fillColor="#FF66B7FF"
        android:pathData="M32,88 L76,88 L76,92 L32,92 Z"/>
</vector>
""")

colors = os.path.join(res, "values/colors.xml")
if os.path.exists(colors):
    with open(colors) as f:
        color_xml = f.read()
else:
    color_xml = '<resources>\n</resources>\n'
if "microos_icon_background" not in color_xml:
    color_xml = color_xml.replace(
        "</resources>",
        '    <color name="microos_icon_background">#101522</color>\n</resources>',
    )
with open(colors, "w") as f:
    f.write(color_xml)

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

# Plugins are compiled against their own pinned compileSdk (34 in several of
# them), while flutter_plugin_android_lifecycle now demands 36. Force 36 here
# and in every subproject below.
g = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36", g)
g = re.sub(r"compileSdkVersion\s+flutter\.compileSdkVersion", "compileSdkVersion 36", g)

# Pin the NDK to the version the workflow installs, whichever form the
# template uses.
g = re.sub(r'ndkVersion\s*=\s*flutter\.ndkVersion',
           'ndkVersion = "28.2.13676358"', g)
g = re.sub(r'ndkVersion\s+flutter\.ndkVersion',
           'ndkVersion "28.2.13676358"', g)

if "ndkVersion" not in g:
    g = re.sub(r"(compileSdk\s*=\s*flutter\.compileSdkVersion)",
               r"\1\n    ndkVersion = \"28.2.13676358\"", g, count=1)
    g = re.sub(r"(compileSdkVersion\s+flutter\.compileSdkVersion)",
               r"\1\n    ndkVersion \"28.2.13676358\"", g, count=1)

# Release builds already use the debug signing key in the Flutter template,
# which is exactly what a sideload-only APK needs.


# targetSdk 28 is required by the current proot execution model. Suppress only
# the Play-Store target-SDK lint rule so sideload release APKs can be built;
# this does not make the APK Play-Store compliant.
if target.endswith(".kts"):
    g += '\nandroid { lint { disable += "ExpiredTargetSdkVersion" } }\n'
else:
    g += "\nandroid { lint { disable 'ExpiredTargetSdkVersion' } }\n"

with open(target, "w") as f:
    f.write(g)

print("patched:", manifest)
print("patched:", target)

# ---- compileSdk alignment lives in tool/patch_plugins.sh ----------------
# Plugin modules that pin an old compileSdk break AGP's AAR metadata check, but
# the fix has to run *before* Gradle configures anything, so the workflow calls
# tool/patch_plugins.sh right after `flutter pub get`. Patching Gradle from here
# is not possible: the root build script is evaluated after the plugin projects
# ("Cannot run Project.afterEvaluate(Action) when the project is already
# evaluated").
PY

grep -q "targetSdk = 28\|targetSdkVersion 28" android/app/build.gradle.kts android/app/build.gradle 2>/dev/null \
  || { echo "!! could not patch targetSdk, inspect android/app/build.gradle*"; exit 1; }

echo "==> android project ready"
