# 아키텍처와 구현 노트

코드를 고치려는 사람을 위한 문서. 기능 설명은 [features.md](features.md) 참조.

---

## 전체 그림

```
                    ┌─ HotKeyManager (Carbon RegisterEventHotKey — 권한 불필요)
                    │     ⌥Space → PanelController      ⌃Space → HintModeController
                    │
  런처 축           │                       키보드 화면 접근 축
  ─────────────────┴──────────            ──────────────────────────────
  PanelController (NSPanel)                HintModeController (오케스트레이터)
    └ ContentView (SwiftUI)                  ├ HintOverlayController  (라벨 오버레이)
       └ SearchViewModel                     ├ ScrollModeController   (HJKL + HUD)
          └ SearchEngine                     ├ GridModeController     (3×3 그리드)
             ├ SearchProvider[] (동기)       └ HintTargetCollector    (AX 트리 수집)
             ├ FileSearchProvider (비동기)        └ HintActionPerformer (AXPress/클릭 합성)
             └ UIElementProvider (비동기) ───────────┘ (수집기 공유)
```

## 런처 파이프라인

### 패널

`PanelController` — `.nonactivatingPanel` 스타일의 NSPanel(`canBecomeKey=true, canBecomeMain=false`).
포커스를 뺏지 않고 키 입력만 받는 Spotlight/Raycast 방식의 본질. `windowDidResignKey`에서 자동 닫힘.
결과 수에 따라 높이를 애니메이션으로 조절한다.

### 검색 흐름

`SearchViewModel.queryChanged` → `SearchEngine.syncResults`:

1. **전용 모드 분기** — 클립보드(`cb`/`클립`)와 UI 요소(`;`)는 다른 프로바이더와 섞이지 않는 전용 모드
2. **동기 프로바이더 순회** — `syncProviders: [SearchProvider]` 배열을 flatMap.
   `SearchProvider` 프로토콜은 `results(for:) -> [SearchResult]` 하나 — 새 기능은 배열에 한 줄 추가
3. **frecency 부스트** → 점수순 정렬 → 웹 폴백을 맨 뒤에 부착
4. **비동기 채널** — 파일 검색(NSMetadataQuery)과 UI 요소 수집(AX)은 콜백으로 나중에 도착:
   - 파일: `merge(fileResults:into:)`로 기존 결과에 병합 (웹 폴백은 항상 마지막 유지)
   - 요소: 전용 모드라 결과를 통째로 교체

### 랭킹

모든 점수 상수는 `Ranking.swift`의 `Score` 한 곳에 있다:

```
계산(1000) > 웹 프리픽스(900) > 클립보드(500) > 완전 일치 앱(100) > 액션(50)
> fuzzy 대역(대략 -1 ~ 5) > 웹 폴백(-1000, 항상 마지막)
```

- fuzzy 매칭은 `FuzzyMatch.swift` — fzy 알고리즘의 2행 DP 포팅. 단어 경계/camelCase/연속 매치 보너스, 갭 페널티, 접두사 보너스
- **한글 초성 검색**: needle이 전부 자음이면 haystack의 초성열과 부분수열 비교
- frecency: `FrecencyStore` — 선택 시각 목록을 저장하고 `Σ 2^(-경과시간/7일)` 로 부스트. 계산 결과·UI 요소는 학습 제외

### 영속화

`JSONFileStore<Value: Codable>` — `~/Library/Application Support/Spot/` 아래 JSON 저장 공통 헬퍼.
디바운스 저장(마지막 호출 후 N초 뒤 1회 기록). `ClipboardStore`(2초)·`FrecencyStore`(1초)가 사용.

클립보드는 0.5초 폴링으로 감지한다(macOS엔 클립보드 변경 알림이 없음).
Spot 자신이 쓸 때는 `ClipboardStore.copy()` 단일 경로 — `ignoreNextChange` 플래그로 폴링 중복을 막고 히스토리 최상단에 기록.

### 앱 이름 현지화

`FileManager.displayName`은 호출 앱(Spot)이 해당 언어 로컬라이제이션을 선언하지 않으면 **영어 이름만** 돌려준다.
그래서 `AppProvider`는 대상 앱 번들의 현지화 테이블을 직접 읽는다:

1. `Contents/Resources/InfoPlist.loctable` (신형식, 시스템 앱) → 사용자 언어 항목의 `CFBundleDisplayName`/`CFBundleName`
2. 없으면 `Contents/Resources/<lang>.lproj/InfoPlist.strings` (구형식)

영어·한글 이름을 모두 검색 인덱스에 넣고, 표시 이름은 사용자 언어 우선.

---

## 키보드 화면 접근

### AX 트리 수집 (`HintTargetCollector`)

- `AXUIElementCreateApplication(pid)` → 창들 + 메뉴 막대를 BFS 순회
- **요소당 IPC 1회**: `AXUIElementCopyMultipleAttributeValues`로 role·title·description·position·size·children을 배치 조회
- 가지치기: 유효 크기인데 클립 영역(창 프레임)과 안 겹치는 서브트리는 스킵(스크롤 밖 콘텐츠),
  닫힌 메뉴 아래로는 안 내려감. 상한: 요소 400 / 방문 4000 / 깊이 40
- 중복 제거: 요소 중심 좌표 기준
- **frontmost 판정**: `frontmostApplication`이 유니버설 컨트롤 같은 백그라운드 프로세스면 `menuBarOwningApplication`으로 폴백
- **Electron/Chromium**: 보조 기술이 감지될 때만 트리를 만들므로 `AXManualAccessibility`(신형)와
  `AXEnhancedUserInterface`(구형)를 앱 요소에 설정. 첫 순회가 비면 0.25초 후 1회 재시도

### 좌표계 (`ScreenCoords`)

AX API는 **주 화면 좌상단 원점(y 아래 방향)** CG 좌표, AppKit은 좌하단 원점.
두 공간은 x가 같고 y만 주 화면 높이 기준으로 뒤집힌다 — 변환식이 양방향 동일(involution).
SwiftUI 오버레이는 좌상단 원점이라 CG 좌표에서 화면 원점만 빼면 된다.

### 오버레이 패턴 (힌트/스크롤 HUD/그리드 공통)

- `.nonactivatingPanel` + `canBecomeKey` NSPanel을 `.screenSaver` 레벨로 띄우고 `makeKeyAndOrderFront`
- `ignoresMouseEvents = true` — 클릭은 통과, 키 입력만 받는다
- `NSEvent.addLocalMonitorForEvents(.keyDown)`으로 키를 처리하고 `nil` 반환으로 삼킨다
- `windowDidResignKey` → 자동 취소 (다른 곳 클릭하면 모드 종료)

### 한글 IME 대응

키 매칭은 전부 **keyCode(물리 키 위치)** 기준이다. `charactersIgnoringModifiers`는 한글 입력 상태에서
자모("ㅁ")를 돌려주므로 문자 기반 매칭은 깨진다. 힌트 라벨(A–Z), 스크롤(HJKL·D/U), 그리드(QWE/ASD/ZXC)
모두 `kVK_ANSI_*` 상수 매핑. 오버레이는 텍스트 필드가 아니라 IME 조합 자체가 일어나지 않는다.

주의: **런처 검색창은 실제 NSTextField라 IME가 적용된다** — 합성 키 이벤트로 검색창에 영문을 넣으려는
자동화는 한글 입력 상태에서 깨진다(개발 중 테스트가 이 문제로 실패했음).

### 실행 (`HintActionPerformer`)

1. `AXPress` 액션 우선 — 포인터 이동 없이 실행
2. 실패 또는 텍스트 입력류(`AXTextField`/`AXTextArea`/`AXSearchField`)는 CGEvent로 실제 클릭 합성
   (mouseMoved → leftMouseDown → leftMouseUp, `.cghidEventTap`에 post)

스크롤은 `CGEvent(scrollWheelEvent2Source:)` 라인 단위 — 스크롤 이벤트는 **포인터 아래 창**으로
가므로 스크롤 모드 진입 시 포인터를 포커스 창 중앙으로 워프한다.

### 모드 전환 (`HintModeController`)

```
⌃Space: 창/그리드/스크롤 켜져 있으면 끔 → 힌트 켜져 있으면 스크롤로 → 아니면 힌트 시작
힌트에서 Tab → 스크롤, "/" → 그리드, "." → 창 모드, 수집 결과 없음 → 그리드 자동 폴백
```

### 창 배치 (`WindowManager` / `WindowModeController`)

Rectangle 방식 — 포커스 창의 `kAXPositionAttribute`/`kAXSizeAttribute`를 set.
프레임 계산은 `NSScreen.visibleFrame`(메뉴바·Dock 제외) 기준, 대상 화면은 창과 교집합이 가장 큰 화면.

- **`AXEnhancedUserInterface` 임시 해제**: 힌트 모드가 Electron 앱에 켜는 이 플래그는 AX 창 이동을
  애니메이션시켜 위치를 어긋나게 한다 — 이동 동안만 끄고 복구
- **position→size 두 번 적용**: 앱 최소 크기 클램프·화면 경계 걸침 대응 (Rectangle과 동일)
- **사이클 판정**: 현재 프레임이 ½·⅔·⅓ 후보와 오차 5px 내로 일치하면 다음 단계 적용
- **복원**: 창별 첫 스냅 직전 프레임을 (AXUIElement, frame) 목록에 저장 (CFEqual 비교, 최근 20개)
- 상세 설계·조사 배경: [window-management.md](window-management.md)

---

## 잠자기 방지 (`AwakeSessionManager`)

- `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep)` — caffeinate와 같은 API
- 권한 불필요, 프로세스 종료 시 어설션 자동 해제. 시간 지정 세션은 Timer로 해제
- 디버깅: `pmset -g assertions`에서 "Spot 깨어있기 세션" 확인
- 뚜껑 닫힘은 공개 API로 막을 수 없다(Amphetamine의 해당 기능은 비공개 API)

---

## 키 리맵 (`KeyRemapManager`)

카라비너 Simple Modifications 대체. `hidutil property --set '{"UserKeyMapping":[...]}'` 호출로
macOS 내장 HID 드라이버 레벨 리맵을 설정한다 (우측⌘→F18, Caps→좌⌃).

- **권한 불필요** — CGEventTap이 아니라서 입력 모니터링도, 손쉬운 사용도 필요 없다.
  드라이버 레벨이라 지연이 없고 보안 입력 중에도 동작
- 매핑은 시스템 속성 — Spot이 죽어도 유지, 대신 **재부팅·Bluetooth 재연결 시 초기화**될 수 있다
  → IOHIDManager 키보드 매칭 콜백(장치 열람만, 입력은 안 읽음) + `NSWorkspace.didWakeNotification`에서
  0.5초 디바운스 후 재적용
- caps→⌃를 기기 구분 없이 전역 적용하는 이유: HHKB는 그 위치가 하드웨어 Control이라
  caps_lock 자체를 보내지 않는다. 기기별 매핑(`--matching`)은 같은 기기에 두 번 set하면
  병합이 아니라 **교체**라 관리가 복잡해져 전역 하나로 통일
- 주의: Karabiner가 실행 중이면 실제 기기를 독점(seize)하고 가상 키보드로 재전송하므로
  hidutil 매핑은 가상 키보드 쪽에 적용된다. 동작은 같지만 카라비너 제거가 최종 상태

## 권한과 서명

### 권한 지도

| 기능 | 필요 권한 |
|---|---|
| 런처·계산·클립보드 복사·awake·핫키 | 없음 (핫키는 Carbon이라 입력 모니터링도 불필요) |
| 힌트/스크롤/그리드, `;` 요소 검색, 자동 붙여넣기 | 손쉬운 사용 (Accessibility) |

### 서명과 TCC — 중요

macOS TCC(권한 DB)는 앱을 **코드 서명 기준**으로 식별한다.

- **ad-hoc 서명은 빌드마다 서명이 바뀐다** → 재설치하면 기존 "허용" 기록과 서명이 안 맞아
  조용히 untrusted가 되고, 기록이 이미 있어서 **권한 프롬프트도 다시 안 뜬다**
- 그래서 `make-app.sh`는 **Apple Development 인증서**가 있으면 그걸로 서명한다
  — identity가 유지되어 재설치해도 권한이 풀리지 않는다

### 트러블슈팅

| 증상 | 원인 | 해법 |
|---|---|---|
| ⌃Space에 아무 반응 없음 | Spot이 실행 중이 아님 | `open /Applications/Spot.app`, `pgrep -x Spot`으로 확인 |
| 권한 프롬프트가 안 뜸 | 낡은 TCC 기록이 프롬프트를 억제 | `tccutil reset Accessibility com.gowoobro.spot` 후 재시도 |
| 재설치 후 힌트 모드가 조용히 죽음 | ad-hoc 서명 불일치 | 위와 동일 + Apple Development 서명으로 설치됐는지 `codesign -dv /Applications/Spot.app` 확인 |
| 특정 앱에서 라벨이 안 뜸 | 접근성 트리 없음/지연 | 한 번 더 시도(Electron 재시도), 그래도 없으면 자동 그리드 폴백 |
| `swift run` 개발 중 권한 | 터미널이 responsible process | 터미널 앱에 손쉬운 사용 권한 부여 |

### 배포 제약

접근성 API는 샌드박스와 양립하지 않아 App Store 배포 불가.
Homerow·Shortcat과 같은 직접 배포(서명된 앱 번들) 방식이다. `scripts/install.sh`가 빌드→서명→설치를 담당.
