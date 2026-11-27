#!/bin/bash
# 빌드 → /Applications 설치 → 실행. 로그인 항목은 앱이 첫 실행 시 스스로 등록한다.
#
# Developer ID 인증서가 있으면 배포본과 같은 방식(Developer ID + 하드닝)으로 서명한다.
# 손쉬운 사용(TCC) 허용은 서명 요구조건에 묶여 있어서, brew 배포본으로 허용해 둔 맥에
# Apple Development 서명 빌드를 덮으면 창 관리·힌트 모드가 조용히 죽는다.
# Developer ID로 서명하면 요구조건이 배포본과 같아 허용이 그대로 유지된다.
# (SIGN_IDENTITY를 직접 주면 그것을 쓴다.)
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${SIGN_IDENTITY:-}" ]; then
    # grep은 못 찾으면 실패를 돌려줘 pipefail 아래에서 스크립트를 끝낸다. awk 하나로 찾는다.
    DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Developer ID Application/ && !found {print $2; found=1}' || true)
    if [ -n "$DEVELOPER_ID" ]; then
        export SIGN_IDENTITY="$DEVELOPER_ID" HARDENED=1
    fi
fi

./scripts/make-app.sh

pkill -x Spot 2>/dev/null || true
sleep 0.5

rm -rf /Applications/Spot.app
ditto build/Spot.app /Applications/Spot.app

# 위젯은 설치된 앱 한 곳에서만 읽혀야 한다. 빌드 폴더의 사본이 등록돼 있으면 시스템이 어느 쪽을 쓸지 알 수 없다.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$PWD/build/Spot.app" >/dev/null 2>&1 || true
# 떠 있는 위젯 프로세스는 앱을 바꿔 넣어도 예전 코드로 계속 돈다. 꺼 두면 시스템이 새 코드로 다시 띄운다.
pkill -x SpotWidget 2>/dev/null || true

open /Applications/Spot.app
echo "설치 완료: /Applications/Spot.app (로그인 시 자동 실행 등록됨)"
