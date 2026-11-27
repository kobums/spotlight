#!/bin/sh
# 위젯 화면을 PNG로 뽑는다 (작게·중간·크게 × 여러 상태).
#
#   Widget/tools/render_previews.sh <출력 폴더> [앨범 아트 파일…]
#
# 위젯과 같은 뷰·같은 아트 처리 코드를 그대로 컴파일해서 그리므로, 배치나 배경 밝기를 고친 뒤 바로 확인할 수 있다.
set -e
cd "$(dirname "$0")/../.."
out="${1:?출력 폴더를 지정하세요}"
shift
bin="$(mktemp -d)/render_previews"
swiftc -O -o "$bin" \
  Sources/Spot/NowPlaying/Shared/*.swift \
  Widget/SpotWidget/Views/*.swift \
  Sources/Spot/NowPlaying/ArtworkProcessor.swift \
  Widget/tools/preview/main.swift
"$bin" "$out" "$@"
