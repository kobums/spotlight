#!/bin/bash
# 릴리즈 빌드 후 Spot.app 번들 생성
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Spot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Spot "$APP/Contents/MacOS/Spot"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Spot</string>
    <key>CFBundleIdentifier</key>
    <string>com.gowoobro.spot</string>
    <key>CFBundleName</key>
    <string>Spot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo "생성 완료: $APP"
echo "실행: open $APP"
echo "로그인 시 자동 실행: 시스템 설정 > 일반 > 로그인 항목에 추가"
