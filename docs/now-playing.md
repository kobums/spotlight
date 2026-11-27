# 지금 재생 중 위젯

음악 앱(Apple Music)에서 지금 재생 중인 곡을 보여 주는 맥 위젯. 애플이 만들어 두지 않은 "지금 재생 중" 위젯을 채운다.
Spotify나 브라우저처럼 다른 앱에서 재생하는 것도 보여 준다(아래 "다른 앱의 재생").
따로 있던 NowPlaying 앱(메뉴 막대 도우미 + 위젯)을 2026-11-27에 Spot에 합쳤다. 도우미 노릇은 Spot이 한다.
아래 글에서 "앱"은 Spot이다.

- 위젯 "지금 재생 중": 작게·중간·크게. 앨범 아트, 제목·아티스트, 스스로 흐르는 진행 막대(누르면 그 위치로 이동), 재생/일시 정지·이전·다음 버튼
- **macOS 26 이상**, 그리고 **팀 서명된 Spot.app**(brew 배포본, `make install`)에서만 된다. `swift run`과 ad-hoc 빌드에는 위젯이 없다
- **Spot이 켜져 있어야 위젯이 갱신된다**
- 위젯을 놓지 않은 사람에게는 아무 일도 하지 않는다: 음악 앱 제어 허락을 묻지 않고 도우미 프로세스도 띄우지 않는다

## 쓰는 법

1. 바탕화면 control-클릭 › 위젯 편집에서 "Spot"의 "지금 재생 중"을 추가한다.
2. 음악 앱이 켜져 있으면 "Spot이 음악을 제어하려고 합니다" 창이 뜬다. 허용한다.
   거절하면 제목·아티스트는 보이지만 앨범 아트·정확한 재생 위치·버튼이 빠진다
   (메뉴바 › 지금 재생 중 위젯 › "음악 앱 제어 허용하기…"로 다시 열 수 있다).

메뉴바 › **지금 재생 중 위젯**

| 항목 | 동작 |
| --- | --- |
| (맨 위) | 지금 곡의 제목·아티스트, 또는 상태("위젯을 추가하면 시작합니다" 등) |
| 위젯에 재생 정보 표시 | 끄면 재생 상태를 따라가지 않고 위젯은 빈 화면이 된다 |
| 다른 앱의 재생도 표시 | 끄면 음악 앱만 보여 준다 (도우미 프로세스도 꺼진다) |

## 구조

위젯 확장은 SwiftPM으로 만들 수 없어 Xcode 프로젝트가 따로 있고, `scripts/make-app.sh`가 둘을 한 번들로 묶는다.

```
Sources/Spot/NowPlaying/        Spot 본체에 들어가는 쪽 (SwiftPM)
├── NowPlayingService           진입점: 쓸 수 있는 환경인지, 위젯이 놓여 있는지 보고 모니터를 켜고 끈다
├── NowPlayingMenuSection       메뉴바의 "지금 재생 중 위젯" 하위 메뉴
├── MusicBridge                 음악 앱과 Apple Event로 대화 (상태·곡·위치·아트 읽기, 재생 제어)
├── MusicMonitor                재생 알림 + 주기 확인으로 상태를 따라가며 상태 파일을 쓰고 위젯을 새로 고침
├── ArtworkProcessor            앨범 아트 줄이기, 흐린 배경 만들기(흰 글자가 읽히게 밝기 조절)
├── SystemNowPlaying            시스템의 "지금 재생 중"(다른 앱의 재생) 따라가기: 도우미를 띄우고 그 출력을 읽음
└── Shared/                     Spot과 위젯 확장이 함께 쓰는 코드. Xcode 프로젝트가 이 폴더를 그대로 가리킨다
    ├── NowPlayingSnapshot      위젯에 넘기는 상태
    ├── SharedStore             App Group 폴더의 상태 파일 읽기·쓰기
    ├── PlayerCommand           위젯 → Spot 재생 명령 (Darwin 알림)
    ├── PlayerIntents           버튼 동작 (App Intents)
    ├── WidgetPresence          위젯 → Spot "위젯이 놓여 있다" 신호 (Darwin 알림)
    ├── DebugState              Debug 전용: 위젯에 가짜 상태 보여 주기
    └── AppGroup                App Group·위젯 종류·딥링크 이름
Widget/                         Xcode로 빌드하는 쪽
├── SpotWidget.xcodeproj        타깃 둘: SpotWidget(위젯 확장), NowPlayingHelper(도우미 라이브러리). 서명하지 않는다
├── SpotWidget/                 위젯 확장 (타임라인 제공자, Views/NowPlayingCard)
├── Helper/NowPlayingHelper.m   시스템의 "지금 재생 중"을 읽어 내보내는 도우미 라이브러리
├── Config/                     위젯 확장 Info.plist 추가분
└── tools/                      위젯 화면 렌더링·캡처, 상태 바꾸기, 가짜 플레이어
```

번들에 들어가는 자리: `Spot.app/Contents/PlugIns/SpotWidget.appex`, `Spot.app/Contents/Frameworks/libNowPlayingHelper.dylib`.

### 위젯이 놓여 있을 때만 켜기

`NowPlayingService`는 Spot이 켜질 때 `WidgetCenter.getCurrentConfigurations`로 "지금 재생 중" 위젯이 놓여 있는지 본다.
놓여 있으면 `MusicMonitor`를 켠다. Spot이 켜진 뒤에 위젯을 추가한 경우를 위해, 위젯은 타임라인을 만들 때마다
Darwin 알림(`WidgetPresence`)을 보낸다. 이 알림은 같은 사용자의 어떤 프로세스든 보낼 수 있어서, Spot은 알림을 받으면
바로 켜지 않고 위젯이 놓여 있는지 다시 확인한 뒤에 켠다. 위젯을 지워도 Spot을 다시 켤 때까지는 계속 돈다.

## 동작 방식

맥에는 다른 앱의 재생 정보를 읽는 공개 API가 없다(MediaRemote는 비공개이고 막혀 있다). 그래서 음악 앱이 여는 두 길을 쓴다.

1. **재생 알림** `com.apple.Music.playerInfo` (분산 알림): 곡이 바뀌거나 재생·일시 정지할 때 음악 앱이 보낸다. 제목·아티스트·앨범·길이·상태가 실려 온다. 허락이 필요 없다.
2. **Apple Event**: 재생 위치와 앨범 아트는 알림에 없어 직접 물어본다. "음악 앱 제어" 허락(자동화)이 필요하다. 곡 안에서 위치를 옮기는 것은 알림이 오지 않아 재생 중 4초(일시 정지 중 20초)마다 확인한다.

```
음악 앱 ──알림/Apple Event──▶ Spot ──now-playing.json + 아트·배경 JPEG──▶ App Group 폴더 ──▶ 위젯
                                   ▲                    WidgetCenter.reloadTimelines
                                   └──────── Darwin 알림(재생 명령) ◀── 위젯 버튼(App Intent)
```

- 상태 파일은 `~/Library/Group Containers/<팀 ID>.com.gowoobro.spot/NowPlaying/`에 둔다.
- 위젯 확장은 음악 앱을 제어할 권한이 없다. 버튼을 누르면 Darwin 알림으로 앱을 부르고, 앱이 음악 앱에 명령한다. 인텐트는 앱이 상태 파일을 고쳐 쓸 때까지(최대 1.2초) 기다렸다가 끝나므로, 시스템이 위젯을 다시 그릴 때 새 상태가 바로 보인다.
- 진행 막대와 시간은 시스템이 시각에 맞춰 흘려 주는 `ProgressView(timerInterval:)`·`Text(timerInterval:)`에 기대므로 위젯을 새로 그리지 않아도 움직인다. 위젯 갱신은 곡 변경·재생/정지·탐색 때만 일어난다.
- 위젯은 끌기를 받지 못하고 버튼만 누를 수 있다. 그래서 진행 막대 위에 보이지 않는 버튼을 14pt쯤마다 한 칸씩 깔아 두고(`SeekTargets`), 누른 칸의 가운데 위치로 옮긴다. 어디로 옮길지는 Darwin 알림에 실을 수 없어 App Group 폴더의 `seek-request.json`에 적고 알림으로 앱을 깨운다(`SeekRequest`). 요청에는 위젯이 그리고 있던 곡의 표(`trackToken`)를 함께 적어, 누르는 사이 곡이 넘어갔으면 앱이 버린다. 음악 앱은 `player position`을 고쳐 쓰고, 다른 앱은 도우미가 MediaRemote로 위치를 지정한다.
- 타임라인은 곡이 끝날 시각에 "끝에서 멈춘 모습"을 걸어 두고 그때 상태 파일을 다시 읽는다. 앱의 갱신 요청이 늦거나 앱이 꺼져 있어도 재생 중인 척 남지 않는다.
- 위젯을 누르면 `spot://now-playing`으로 Spot이 불리고, Spot이 음악 앱(다른 앱을 보여 주는 중이면 그 앱)을 앞으로 가져온다.
- 스트리밍 곡은 재생 알림에 고유 ID가 없다. 같은 곡인지는 제목·아티스트·앨범으로 가린다.

### 다른 앱의 재생

메뉴 막대·제어 센터의 "지금 재생 중"에 나오는 것, 곧 시스템이 지금 재생 중이라고 꼽은 앱이 음악 앱이 아니면 그 앱의 곡을 보여 준다 (메뉴바 › 지금 재생 중 위젯 › "다른 앱의 재생도 표시", 켜진 것이 기본).

- **공개된 길이 아니다.** 이 정보는 비공개 프레임워크 MediaRemote에 있고, macOS 15.4부터는 애플이 정한 프로그램만 읽을 수 있다(보통 프로그램이 부르면 빈 답이 온다). 시스템에 들어 있는 `/usr/bin/perl`이 그 가운데 하나라, 앱이 perl을 띄워 도우미 라이브러리(`libNowPlayingHelper.dylib`)를 불러오게 하고 그 출력을 읽는다. **macOS가 바뀌면 언제든 멈출 수 있다.** 멈추면 도우미를 몇 번 다시 띄워 보다가 그만두고, 앱은 음악 앱만 보여 주던 동작으로 돌아간다.
- 도우미는 곡 정보·재생 여부·위치·앨범 아트를 한 줄에 JSON 하나로 내보내고, 바뀔 때 시스템 알림을 받아 다시 내보낸다. 앱이 끝나면 입력이 닫혀 같이 끝난다. 주고받는 형식은 `Widget/Helper/NowPlayingHelper.m` 머리에 있다.
- **음악 앱은 지금까지처럼 재생 알림과 Apple Event로 읽는다.** 도우미에 기대는 것은 다른 앱의 재생뿐이다.
- 어느 쪽을 보여 줄지: 시스템이 꼽은 앱이 재생 중이면 그 앱. 그 앱은 멈춰 있고 음악 앱이 재생 중이면 음악 앱. 둘 다 멈춰 있으면 시스템이 꼽은 앱.
- 다른 앱을 보여 주는 동안 위젯 버튼의 명령은 도우미를 거쳐 그 앱으로 가고(MediaRemote의 명령 보내기), 위젯을 누르면 그 앱이 열린다.
- 다른 앱이 시스템에 알린 값은 그대로 믿지 않는다. 길이·위치는 범위를 보고, 글자는 길이를 자른다(결합 문자를 끝없이 붙인 글자가 통과하지 않게 유니코드 스칼라로 센다).
- 배속 재생(1.5배 등)이면 진행 막대가 그 속도로 흐른다. 시스템의 시간 글자는 실제 시간으로만 흘러서, 이때는 시간 대신 속도(`1.5×`)와 전체 길이를 보여 준다.
- 앨범 아트는 곡이 바뀔 때 요청하고, 늦게 준비되거나 같은 제목에서 그림만 바뀌는 경우를 위해 조금 뒤와 정보가 바뀔 때 다시 본다.
- 음악 앱과 달리 "음악 앱 제어" 허락이 필요 없다.

### 위젯이 그려지는 모습

macOS 26에서 잰 값: 중간 위젯은 344×164pt, 안쪽 여백 18pt, 모서리 반지름 약 28pt (작게 164×164, 크게 344×344로 본다). 위젯 로그의 `타임라인 systemMedium 344×164`에서 확인할 수 있다.

시스템은 같은 위젯을 두 가지로 그린다.

- **전체 색상**: 흐리게 만든 앨범 아트를 배경으로 깔고 글자는 흰색.
- **단색**(바탕화면 위젯이 다른 창 뒤에서 흐려질 때): 시스템이 배경을 어두운 판으로 바꾸고, 내용은 색을 버리고 불투명도만 남겨 한 색으로 칠한다. 앨범 아트만 제 색으로 남긴다(`widgetAccentedRenderingMode(.fullColor)`).

단색 모드 때문에 진행 막대는 시스템 막대를 그대로 보여 주지 않는다. 맥의 시스템 막대는 바탕이 불투명한 회색이라 단색 모드에서는 채움과 바탕이 한 덩어리가 되어 늘 꽉 찬 것처럼 보인다. 그래서 바탕과 채움은 직접 그리고, 시스템 막대는 "지금 어디까지 찼는지"를 알려 주는 가리개로만 쓴다: 흰색으로 채운 막대에서 검은색으로 채운 막대를 빼면 채움만 남고, 그 밝기를 불투명도로 바꾼다 (`Widget/SpotWidget/Views/NowPlayingCard.swift`의 `TimerFillMask`). 시간에 따라 스스로 움직이는 것은 시스템 막대뿐이라 이렇게 한다.

### 권한과 서명

| 대상 | 권한 | 이유 |
| --- | --- | --- |
| Spot | `application-groups` (`<팀 ID>.com.gowoobro.spot`) | 위젯과 상태 파일 공유 |
| Spot | `automation.apple-events` | 음악 앱의 재생 상태·위치·아트 읽기, 재생 제어 (브라우저 탭 검색과 같은 권한) |
| 위젯 | `app-sandbox`, `application-groups` | 위젯 확장은 샌드박스여야 한다. 상태 파일 읽기 |

- App Group 이름은 팀 ID가 앞에 붙는 맥 방식이라 개발자 포털 등록도 프로비저닝 프로파일도 필요 없다.
  서명의 팀 ID만 맞으면 된다. 코드에서는 서명에 든 권한에서 이름을 읽는다(`AppGroup.identifier`).
- 권한 파일은 저장소에 없다. `scripts/make-app.sh`가 서명 인증서의 팀 ID를 읽어 만들고,
  도우미 → 위젯 확장 → 앱 순서로 안쪽부터 서명한다. 팀이 없는 ad-hoc 서명이면 위젯을 번들에서 뺀다.
- Spot은 샌드박스가 아니라서 음악 앱 스크립팅 대상(`scripting-targets`) 권한은 필요 없다.
- 버튼 인텐트(`PlayerIntents`)는 Spot 본체와 위젯 확장 양쪽에 컴파일해 넣는다. 실행은 위젯 확장 프로세스에서 된다.
  Spot 본체에는 인텐트 메타데이터(`Metadata.appintents`)가 없지만 버튼은 동작한다 (2026-11-27 확인).

## 개발

```sh
make install                  # 빌드 → /Applications/Spot.app 설치 → 실행 (Developer ID가 있으면 그것으로 서명)
SPOT_CONFIG=debug make install  # 로그에 곡 제목까지 남고 debug_state.sh를 듣는 Debug 빌드
SKIP_WIDGET=1 make build      # 위젯 없이 (Xcode가 없을 때)
```

위젯은 설치된 앱에서 읽어 가므로 `build/Spot.app`을 그대로 실행하지 않는다. 같은 위젯이 두 군데 등록되면
시스템이 어느 쪽을 쓸지 알 수 없어, 설치 스크립트가 빌드 폴더 사본의 등록을 지운다. 떠 있던 위젯 프로세스도 꺼서
새 코드로 다시 뜨게 한다(그러지 않으면 앱을 바꿔 넣어도 예전 코드로 계속 그린다).

```sh
# 위젯 화면을 PNG로 (작게·중간·크게 × 재생·일시 정지·긴 글자·아트 없음·빈 상태·배경 없는 모드·단색 모드)
Widget/tools/render_previews.sh /tmp/spot-widget-previews [앨범 아트 파일…]

# 바탕화면·알림 센터에 올려 둔 실제 위젯을 보이는 그대로 PNG로 (터미널에 화면 기록 권한 필요)
swift Widget/tools/capture_widget.swift /tmp/spot-widget-capture

# Debug 빌드에서 음악을 틀지 않고 위젯 상태 바꿔 보기
Widget/tools/debug_state.sh playing 60     # 60초 지점에서 재생 중인 것처럼 (paused · long · noart · empty)
Widget/tools/debug_state.sh off            # 실제 상태로

# 소리 없이 "재생 중"인 척하는 가짜 플레이어: 다른 앱의 재생이 위젯에 나오는지, 버튼 명령이 그 앱으로 가는지 확인
swiftc -O -o /tmp/fake_player Widget/tools/fake_player.swift && /tmp/fake_player 30

# Spot·위젯 로그 (zsh에는 log 내장 명령이 있어 경로를 다 적는다)
/usr/bin/log stream --level debug --predicate 'subsystem == "com.gowoobro.spot.nowplaying"'
```
