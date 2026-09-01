#!/bin/bash
# 릴리즈 빌드 후 Spot.app 번들 생성.
#
# 서명 방식은 환경 변수로 제어한다:
#   SIGN_IDENTITY  서명 identity (지정 없으면 Apple Development 자동 탐지, 없으면 ad-hoc)
#   HARDENED=1     하드닝된 런타임 + 보안 타임스탬프로 서명 (공증 전제 조건)
# 배포용 서명·공증은 scripts/release.sh가 이 두 변수를 채워 호출한다.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo "1")

swift build -c release

APP=build/Spot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Spot "$APP/Contents/MacOS/Spot"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Spot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.gowoobro.spot</string>
    <key>CFBundleName</key>
    <string>Spot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>브라우저 탭 검색이 열린 탭 목록을 읽고 전환하는 데 사용됩니다.</string>
</dict>
</plist>
PLIST

# 하드닝된 런타임에서 AppleEvents(브라우저 탭 검색)를 쓰기 위한 entitlements
ENTITLEMENTS=build/Spot.entitlements
cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENT

# 서명 identity 결정: SIGN_IDENTITY 우선, 없으면 Apple Development 자동 탐지, 그래도 없으면 ad-hoc.
# Apple Development/ad-hoc 서명은 손쉬운 사용(TCC) 권한이 재설치 후에도 유지되게 하지만,
# 다른 맥에 배포하면 Gatekeeper가 차단한다. 배포본은 release.sh(Developer ID + 공증)로 만들 것.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
fi

SIGN_ARGS=(--force)
if [ -n "${HARDENED:-}" ]; then
    SIGN_ARGS+=(--options runtime --timestamp --entitlements "$ENTITLEMENTS")
fi

if [ -n "$IDENTITY" ]; then
    codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APP"
    echo "서명: $IDENTITY${HARDENED:+ (하드닝)}"
else
    codesign "${SIGN_ARGS[@]}" --sign - "$APP"
    echo "서명: ad-hoc (재설치 시 손쉬운 사용 권한 재부여 필요)"
fi

echo "생성 완료: $APP ($VERSION build $BUILD)"
echo "실행: open $APP"
