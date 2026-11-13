# ThanasOS wallpapers

The Android build downloads the two original wallpaper files from the pinned
ThanasOS source revision using:

`./tool/fetch_thanasos_wallpapers.sh`

Run that script before `flutter pub get` when building locally. The build
workflow runs it automatically before Flutter analyzes and packages assets.
