#!/bin/sh
# Debug 빌드 전용: 음악을 틀지 않고 위젯에 보여 줄 상태를 바꾼다. (Debug로 설치했을 때만 듣는다: SPOT_CONFIG=debug make install)
#
#   Widget/tools/debug_state.sh playing [위치(초)]   지금 곡을 그 위치에서 재생 중인 것처럼
#   Widget/tools/debug_state.sh paused [위치(초)]    일시 정지한 것처럼
#   Widget/tools/debug_state.sh long                 제목·아티스트·앨범이 아주 긴 곡
#   Widget/tools/debug_state.sh noart                앨범 아트가 없는 곡
#   Widget/tools/debug_state.sh empty                재생 중이 아님
#   Widget/tools/debug_state.sh off                  실제 상태로 되돌리기
#
# App Group 폴더에 debug-state.json 을 두면 위젯이 그것을 실제 상태 대신 읽는다 (Sources/Spot/NowPlaying/Shared/DebugState.swift).
set -e
mode="${1:?playing | paused | long | noart | empty | off}"
position="${2:-72}"
dir=$(ls -d "$HOME/Library/Group Containers/"*.com.gowoobro.spot/NowPlaying 2>/dev/null | head -1)
[ -n "$dir" ] || { echo "App Group 폴더가 없습니다. 앱을 한 번 실행하세요." >&2; exit 1; }

if [ "$mode" = off ]; then
  [ ! -e "$dir/debug-state.json" ] || unlink "$dir/debug-state.json"
else
  python3 - "$dir" "$mode" "$position" <<'PY'
import json, os, sys, time
directory, mode, position = sys.argv[1], sys.argv[2], float(sys.argv[3])
now = time.time() - 978307200  # Swift의 Date는 2001년 기준 초
try:
    with open(os.path.join(directory, "now-playing.json")) as f:
        state = json.load(f)
except (OSError, ValueError):
    state = {}
if not state.get("title"):
    state.update(title="곡 제목", artist="아티스트", album="앨범", duration=214.0)
state.update(state="playing", position=position, positionDate=now, updatedAt=now)
if mode == "paused":
    state["state"] = "paused"
elif mode == "long":
    state.update(title="WOAHx7 (feat. 아주 길고 긴 피처링 아티스트 이름이 붙은 제목)",
                 artist="스윙스, hyeminsong, 율음, shinjihang & 그냥노창",
                 album="The Ship Of Theseus (Deluxe Anniversary Edition)", duration=3725.0, position=3000.0)
elif mode == "noart":
    state.pop("artworkFile", None)
    state.pop("backdropFile", None)
elif mode == "empty":
    state = {"state": "stopped", "updatedAt": now, "positionDate": now}
elif mode != "playing":
    sys.exit("모르는 상태: " + mode)
with open(os.path.join(directory, "debug-state.json"), "w") as f:
    json.dump(state, f, ensure_ascii=False)
PY
fi
notifyutil -p com.gowoobro.spot.nowplaying.debug.reload
echo "위젯 상태: $mode"
