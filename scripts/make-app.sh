#!/bin/bash
# 릴리즈 빌드 후 Spot.app 번들 생성.
#
# 서명 방식은 환경 변수로 제어한다:
#   SIGN_IDENTITY  서명 identity (지정 없으면 Apple Development 자동 탐지, 없으면 ad-hoc)
#   HARDENED=1     하드닝된 런타임 + 보안 타임스탬프로 서명 (공증 전제 조건)
#   CONFIG=debug   Debug로 빌드 (기본 release). 위젯 확인 도구(Widget/tools/debug_state.sh)는 Debug에서만 듣는다
#   SKIP_WIDGET=1  위젯 확장을 빌드·포함하지 않는다 (Xcode 없이 빌드할 때)
#
# "지금 재생 중" 위젯 확장(SpotWidget.appex)과 도우미 라이브러리는 SwiftPM으로 만들 수 없어
# Widget/SpotWidget.xcodeproj를 xcodebuild로 빌드해 번들에 넣는다. 서명은 여기서 안쪽부터 한꺼번에 한다.
# 배포용 서명·공증은 scripts/release.sh가 이 두 변수를 채워 호출한다.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo "1")

CONFIG="${CONFIG:-release}"
case "$CONFIG" in
    release) XCODE_CONFIG=Release ;;
    debug) XCODE_CONFIG=Debug ;;
    *) echo "CONFIG는 release 또는 debug" >&2; exit 1 ;;
esac

swift build -c "$CONFIG"

# 위젯 확장 + 도우미 라이브러리 (Xcode 빌드, 서명 없이). 버전은 앱과 맞춘다.
WIDGET_PRODUCTS="build/widget/$XCODE_CONFIG"
if [ -z "${SKIP_WIDGET:-}" ]; then
    xcodebuild -project Widget/SpotWidget.xcodeproj \
        -target SpotWidget -target NowPlayingHelper -configuration "$XCODE_CONFIG" \
        ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=NO \
        SYMROOT="$PWD/build/widget" OBJROOT="$PWD/build/widget/obj" \
        MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
        -quiet build
fi

APP=build/Spot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/Spot" "$APP/Contents/MacOS/Spot"
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
    <string>브라우저 탭 검색이 열린 탭 목록을 읽고 전환하는 데, 그리고 지금 재생 중 위젯이 음악 앱의 곡 정보를 읽고 재생을 제어하는 데 사용됩니다.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.gowoobro.spot</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>spot</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# 서명 identity 결정: SIGN_IDENTITY 우선, 없으면 Apple Development 자동 탐지, 그래도 없으면 ad-hoc.
# Apple Development/ad-hoc 서명은 다른 맥에 배포하면 Gatekeeper가 차단한다.
# 배포본은 release.sh(Developer ID + 공증)로 만들 것.
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | awk '{print $2}')
fi

SIGN_ARGS=(--force --sign "${IDENTITY:--}")
if [ -n "${HARDENED:-}" ]; then
    SIGN_ARGS+=(--options runtime --timestamp)
fi

# 위젯 확장·도우미를 번들에 넣고 안쪽부터 서명한다.
# 위젯은 App Group 폴더로 Spot과 상태 파일을 주고받는다. 맥의 App Group 이름은 팀 ID로 시작하고
# (<팀 ID>.com.gowoobro.spot) 프로비저닝 프로파일 없이 서명의 팀 ID만으로 인정된다.
# 그래서 팀이 없는 ad-hoc 서명에서는 위젯을 넣지 않는다.
HELPER="$APP/Contents/Frameworks/libNowPlayingHelper.dylib"
APPEX="$APP/Contents/PlugIns/SpotWidget.appex"
TEAM=""
if [ -z "${SKIP_WIDGET:-}" ]; then
    mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/PlugIns"
    cp "$WIDGET_PRODUCTS/libNowPlayingHelper.dylib" "$HELPER"
    ditto "$WIDGET_PRODUCTS/SpotWidget.appex" "$APPEX"

    codesign "${SIGN_ARGS[@]}" "$HELPER"
    TEAM=$(codesign -dv "$HELPER" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [ "$TEAM" = "not set" ] && TEAM=""

    if [ -n "$TEAM" ]; then
        cat > build/SpotWidget.entitlements <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>${TEAM}.com.gowoobro.spot</string>
    </array>
</dict>
</plist>
ENT
        codesign "${SIGN_ARGS[@]}" --entitlements build/SpotWidget.entitlements "$APPEX"
    else
        rm -rf "$APP/Contents/Frameworks" "$APP/Contents/PlugIns"
        echo "위젯 제외: 팀 서명이 아니라 App Group을 쓸 수 없음"
    fi
fi

# 앱 권한: AppleEvents(브라우저 탭 검색·음악 앱 제어, 하드닝된 런타임에서 필요) + 위젯과 나누는 App Group
ENTITLEMENTS=build/Spot.entitlements
{
    cat <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
ENT
    if [ -n "$TEAM" ]; then
        cat <<ENT
    <key>com.apple.security.application-groups</key>
    <array>
        <string>${TEAM}.com.gowoobro.spot</string>
    </array>
ENT
    fi
    cat <<ENT
</dict>
</plist>
ENT
} > "$ENTITLEMENTS"

codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
if [ -n "$IDENTITY" ]; then
    echo "서명: $IDENTITY${HARDENED:+ (하드닝)}${TEAM:+ · 위젯 포함}"
else
    echo "서명: ad-hoc (재설치 시 손쉬운 사용 권한 재부여 필요)"
fi

echo "생성 완료: $APP ($VERSION build $BUILD)"
echo "설치: make install  (위젯은 /Applications에 설치된 앱에서만 읽힌다)"
