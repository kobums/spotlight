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

# Apple Development 인증서가 있으면 그걸로 서명 — 빌드가 바뀌어도 서명 identity가
# 유지되어 손쉬운 사용(TCC) 권한이 재설치 후에도 풀리지 않는다. 없으면 ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -n "${IDENTITY:-}" ]; then
    codesign --force --sign "$IDENTITY" "$APP"
    echo "서명: Apple Development ($IDENTITY)"
else
    codesign --force --sign - "$APP"
    echo "서명: ad-hoc (재설치 시 손쉬운 사용 권한 재부여 필요)"
fi

echo "생성 완료: $APP"
echo "실행: open $APP"
echo "로그인 시 자동 실행: 시스템 설정 > 일반 > 로그인 항목에 추가"
