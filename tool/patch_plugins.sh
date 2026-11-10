#!/usr/bin/env bash
# MicroOS: raise every plugin module's compileSdk to the app's compileSdk.
#
# Why this exists:
#   Some Flutter plugins still hardcode an old compileSdk (34, 33, ...). AGP's
#   AAR metadata check then refuses the build because a transitive dependency
#   (typically flutter_plugin_android_lifecycle) was published against a newer
#   API level:
#
#     :some_plugin:checkReleaseAarMetadata
#     Dependency 'androidx.lifecycle:lifecycle-runtime:...' requires libraries
#     and apps that depend on it to compile against version 36 or later.
#
#   Doing this from Gradle (subprojects { afterEvaluate { ... } }) is fragile:
#   on recent Gradle the root build script can be evaluated *after* the plugin
#   projects, which fails with
#     "Cannot run Project.afterEvaluate(Action) when the project is already
#      evaluated."
#   and even when it works it runs after AGP has created its variants.
#
#   Rewriting the plugin sources in the pub cache happens before Gradle ever
#   starts, so it is deterministic and version independent.
#
# Usage: tool/patch_plugins.sh [compileSdk]   (default: 36)
set -euo pipefail

TARGET="${1:-36}"
CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
HOSTED="$CACHE/hosted/pub.dev"

if [ ! -d "$HOSTED" ]; then
  echo "!! pub cache not found at $HOSTED (run 'flutter pub get' first)"
  exit 1
fi

# Rewrites "compileSdkVersion 34", "compileSdkVersion = 34", "compileSdkVersion(34)",
# "compileSdk 34", "compileSdk = 34", "compileSdk(34)" -> $TARGET.
# minSdk / targetSdk are deliberately left alone.
rewrite() {
  perl -pi -e "s/(compileSdkVersion\s*[=:( ]+\s*)3\d(?!\d)/\${1}${TARGET}/g; s/(compileSdk\s*[=:( ]+\s*)3\d(?!\d)/\${1}${TARGET}/g" "$1"
}

patched=0
changed=()

while IFS= read -r file; do
  cp "$file" "$file.microos.bak"
  rewrite "$file"
  if cmp -s "$file" "$file.microos.bak"; then
    rm -f "$file.microos.bak"
  else
    rm -f "$file.microos.bak"
    changed+=("$file")
    patched=$((patched + 1))
  fi
done < <(find "$HOSTED" -maxdepth 4 -type f \
           \( -name 'build.gradle' -o -name 'build.gradle.kts' \) \
           -path '*/android*' 2>/dev/null | sort)

for f in "${changed[@]:-}"; do
  [ -n "$f" ] && echo "patched compileSdk -> $TARGET: $f"
done

echo "==> compileSdk patch complete ($patched file(s) updated)"
