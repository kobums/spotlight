#!/bin/bash
# 빌드 → /Applications 설치 → 실행. 로그인 항목은 앱이 첫 실행 시 스스로 등록한다.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/make-app.sh

pkill -x Spot 2>/dev/null || true
sleep 0.5

rm -rf /Applications/Spot.app
cp -R build/Spot.app /Applications/Spot.app

open /Applications/Spot.app
echo "설치 완료: /Applications/Spot.app (로그인 시 자동 실행 등록됨)"
