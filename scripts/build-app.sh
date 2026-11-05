#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app="dist/MemPulse.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources"
cp "$binary_dir/MemPulse" "$app/Contents/MacOS/MemPulse"
cp Assets/MemPulse.icns "$app/Contents/Resources/MemPulse.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MemPulse</string>
<key>CFBundleIdentifier</key><string>local.mempulse.app</string>
<key>CFBundleName</key><string>MemPulse</string>
<key>CFBundleIconFile</key><string>MemPulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
# Finder/Dock 按 bundle 目录的修改时间缓存图标，覆盖构建时需要刷新
touch "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
printf 'Built %s/%s\n' "$PWD" "$app"
