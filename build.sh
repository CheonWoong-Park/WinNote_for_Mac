#!/bin/bash
# notepad.app 빌드 스크립트
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
# Apple Silicon + Intel 유니버설 바이너리
for ARCH in arm64 x86_64; do
  swift build -c "$CONFIG" --triple "$ARCH-apple-macosx13.0"
done
BIN=".build/notepad-universal"
lipo -create -output "$BIN" ".build/arm64-apple-macosx/$CONFIG/Notepad" ".build/x86_64-apple-macosx/$CONFIG/Notepad"

APP="build/notepad.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Resources/Images"
cp "$BIN" "$APP/Contents/MacOS/notepad"
cp Resources/Fonts/*.ttf "$APP/Contents/Resources/Fonts/"
cp Resources/Images/*.png "$APP/Contents/Resources/Images/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
    <key>CFBundleExecutable</key><string>notepad</string>
    <key>CFBundleIdentifier</key><string>com.cheonwoong.winnote</string>
    <key>CFBundleName</key><string>notepad</string>
    <key>CFBundleDisplayName</key><string>notepad</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>11.2607.14</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>텍스트 문서</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.plain-text</string>
                <string>public.text</string>
                <string>public.source-code</string>
                <string>public.data</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# 배포용 zip (GitHub Releases / Homebrew)
VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
ZIP="build/notepad-${VERSION:-dev}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "완료: $APP"
echo "배포용: $ZIP"
