# Spot

개인용 macOS 생산성 앱. 두 개의 축으로 이루어져 있다:

1. **런처 (⌥Space)** — Spotlight/Raycast/Alfred/LaunchBar의 장점만 모은 검색창.
   앱·파일·북마크·브라우저 탭·계산(환율)·클립보드·스니펫·이모지·메뉴 항목·시스템 액션·
   시스템 설정·모니터 제어·창 배치·한/영 규칙·웹 검색·UI 요소 클릭·잠자기 방지.
2. **키보드 화면 접근 (⌃Space)** — Homerow/Vimium/warpd 방식.
   마우스 없이 화면의 아무 요소나 클릭·스크롤하는 힌트/스크롤/그리드 모드.

여기에 상시 유틸리티로 **키 리맵**(Karabiner 대체), **모니터 밝기·볼륨 미디어 키**
(MonitorControl 대체), **앱별 한/영 자동 전환**(Input Source Pro 대체)이 붙어 있다.

Swift 네이티브(SwiftPM + AppKit + SwiftUI), 외부 의존성 0개, 텔레메트리 없음.
네트워크는 환율 시세(open.er-api.com, 24시간 캐시) 하나만 쓴다.

## 설치

```bash
# Homebrew (권장) — 서명·공증된 배포본
brew tap kobums/tap
brew trust kobums/tap        # 서드파티 tap 신뢰 (최신 Homebrew 필수)
brew install --cask spot
```

## 실행 (개발)

```bash
# 개발 실행
swift run

# 로컬 설치 (빌드 → 서명 → /Applications 복사 → 실행)
./scripts/install.sh
```

릴리스·배포 절차는 [docs/RELEASE.md](docs/RELEASE.md) 참조.

첫 실행 시 로그인 항목에 자동 등록된다. 끄려면 메뉴바 아이콘 → "로그인 시 자동 실행" 토글.

## 기능 한눈에

### 런처 — ⌥Space

| 입력 | 동작 |
|---|---|
| (빈 입력) | 자주 쓰는 앱 (frecency 순) |
| `sa`, `음악`, `ㅋㅋㅇ` | 앱 fuzzy 검색 — 한글 이름·초성 검색, 쓸수록 학습 |
| 3글자 이상 | 파일 검색 (Spotlight 인덱스, ⌥⏎ = Finder에서 보기) |
| 2글자 이상 | **브라우저 북마크** 검색 (Chrome·Whale·Edge·Brave) |
| `1+2*3`, `10km to mi`, `100달러`, `1000$` | 계산기 + 단위 변환 + **환율** (단독 수량도 자동 변환) |
| `cb` 또는 `클립` | 클립보드 히스토리 — 텍스트·**이미지**, ⌘⏎ **고정(pin)**, ⏎ 붙여넣기, ⌥⏎ 복사만 |
| `>저장`, `>내보내기` | 최전면 앱 **메뉴 항목** 검색·실행 (Paletro 방식) |
| `:하트`, `:smile` | **이모지** 검색 — ⏎ 붙여넣기, 최근 사용 우선 |
| `잠자기`, `다크모드`, `lock` | 시스템 액션 |
| `디스플레이`, `배터리`, `키보드` | **시스템 설정 패널** 바로 열기 (Spotlight 방식) |
| `깨어있기`, `awake 30분` | 잠자기 방지 세션 (Amphetamine 방식) |
| `밝기 50`, `볼륨 +5`, `대비 70`, `음소거` | 외장 **모니터 밝기·볼륨·대비** 제어 (MonitorControl 방식, DDC·감마) |
| `입력규칙`, `한영` | 앱별 **한/영 자동 전환** + 전환 배지 (Input Source Pro 방식) |
| `;저장`, `;뒤로` | 최전면 앱 **UI 요소 검색·클릭** (Shortcat 방식) |
| `창 왼쪽`, `창 최대화` | **창 배치** 명령 — 창 모드와 같은 16개 액션을 런처에서 바로 |
| `스니펫`, `스니펫 추가 인사 안녕하세요` | **스니펫** — 키워드 입력 → ⏎ 붙여넣기, ⌘⏎ 삭제 |
| `탭`, `탭 검색어` | 실행 중인 브라우저의 **열린 탭** 검색·전환 (Chrome·Whale·Edge·Brave·Safari) |
| `서식제거`, `plain` | 현재 클립보드를 **일반 텍스트로** 붙여넣기 |
| `g`/`yt`/`gh`/`nv` + 검색어 | 웹 검색 (구글/유튜브/깃허브/네이버) |

### 키보드 화면 접근 — ⌃Space

| 상황 | 방법 |
|---|---|
| 보이는 요소 클릭 | **⌃Space** → 노란 라벨 타이핑 (힌트 모드) |
| 스크롤 | 힌트 모드에서 **⌃Space** 또는 **Tab** → HJKL |
| 접근성 정보 없는 앱 | 힌트 모드에서 **`/`** → 3×3 그리드 (수집 실패 시 자동 폴백) |
| 창 배치 (Rectangle 방식) | 힌트 모드에서 **`.`** → HJKL 절반·YUBN 코너·M 최대화·R 복원 |
| 창 배치 전역 단축키 | Rectangle 단축키 호환 — ⌥⌘화살표, ⌥⌘F, ⌃⌥⌫ 등 16개 |
| 설정 창 | 메뉴바 → "설정…" — 창 단축키·크기 순환·간격, 입력 소스 규칙·인디케이터 |
| 이름 아는 요소 | ⌥Space → `;이름` → Enter |

### 키 리맵 — Karabiner-Elements 대체

우측⌘→F18(한/영 전환), Caps Lock→좌⌃. macOS 내장 hidutil 리맵이라 권한 불필요.
외장 키보드에 한해 F1·F2→밝기, F10~F12→음소거·볼륨 미디어 키도 매핑한다
(HHKB에서 `fn+F1/F2` = 밝기, `fn+F11/F12` = 볼륨). 내장 키보드는 진짜 F키를 유지한다.
메뉴바 → "키 리맵"으로 켜고 끈다.

### 모니터 밝기·볼륨 — MonitorControl 대체

macOS는 제어 가능한 디스플레이가 없으면 밝기 키를 그냥 버리고, DP/HDMI 오디오에는
볼륨 키를 아예 전달하지 않는다. Spot이 그 키를 잡아 외장 모니터를 직접 조절한다 —
DDC가 되면 하드웨어(백라이트·스피커), 안 되면 감마 디밍(밝기만).

- **미디어 키**: 밝기(fn+F1/F2)는 커서가 올라간 화면, 볼륨·음소거(fn+F10~F12)는
  **소리가 나가는 모니터**(기본 오디오 출력 장치와 이름 매칭)가 대상
- **메뉴바 슬라이더**: 메뉴바 아이콘 클릭 → 모니터별 밝기·볼륨 슬라이더 (MonitorControl 스타일)
- **런처 명령**: `밝기 50`, `볼륨 +5`, `대비 70`, `음소거` — 권한 불필요
- 조절 시 대상 화면 하단에 HUD 표시 (macOS 기본 HUD가 안 뜨는 영역이라 직접 그린다)
- 메뉴바 → "모니터 밝기·볼륨 키"로 켜고 끈다 (미디어 키만 손쉬운 사용 권한 필요)

> 볼륨은 모니터가 DDC 볼륨(VCP 0x62)을 지원할 때 동작한다. DisplayPort/HDMI로 나가는
> 오디오는 macOS 자체로는 볼륨을 못 바꾸지만, DDC로 모니터 스피커를 직접 조절하면 된다.
> DDC가 안 되는 모니터에서는 볼륨 키를 삼키지 않고 시스템에 그대로 넘긴다.
> `볼륨` 명령이 현재 라우팅·권한 상태를 진단 행으로 보여준다.

상세 키맵과 각 기능 설명은 [docs/features.md](docs/features.md) 참조.

## 권한

- 기본 기능(런처·계산·클립보드 복사·awake·키 리맵)은 **권한 불필요**
- 힌트/스크롤/그리드 모드, UI 요소 검색, 클립보드 자동 붙여넣기, 모니터 밝기·볼륨 키는
  **손쉬운 사용(Accessibility)** 권한 필요
  — 첫 사용 시 시스템 프롬프트로 안내된다. 문제가 생기면 [docs/architecture.md의 권한·서명 절](docs/architecture.md#권한과-서명) 참조
- 브라우저 탭 검색(`탭`)은 브라우저별 **자동화(Automation)** 권한 필요 — 첫 사용 시 프롬프트

## 문서

| 문서 | 내용 |
|---|---|
| [docs/readme.md](docs/readme.md) | 문서 인덱스 |
| [docs/features.md](docs/features.md) | 전체 기능 상세 설명과 키맵 |
| [docs/architecture.md](docs/architecture.md) | 코드 구조, 구현 방식, 권한·서명, 트러블슈팅 |
| [docs/research.md](docs/research.md) | 설계 전 조사 (기존 런처·키보드 접근 앱 분석) |

## 구조

```
Sources/Spot/
├── main.swift / AppDelegate.swift        # 부트스트랩, 메뉴바 (모니터 슬라이더 포함)
├── HotKeyManager.swift                   # 글로벌 핫키 (Carbon, ⌥Space·⌃Space)
├── PanelController.swift                 # nonactivating NSPanel
├── ContentView / ResultRow / PanelChrome / SearchField   # 런처 UI
├── SearchViewModel / SearchEngine        # 쿼리 라우팅·랭킹·비동기 병합
├── Models / Ranking / FuzzyMatch         # 결과 모델·점수 상수·fzy 매칭+한글 초성
├── FrecencyStore / ClipboardStore / JSONFileStore   # 학습·히스토리(텍스트·이미지·pin)·영속화
├── SnippetStore.swift                    # 스니펫 저장소 (snippets.json)
├── CurrencyRates.swift                   # 환율 시세 캐시 (open.er-api.com, 24시간)
├── BundleLocalization.swift              # 앱 번들 현지화 이름 읽기 (loctable/lproj)
├── AwakeSessionManager.swift             # 잠자기 방지 (IOPMAssertion)
├── KeyRemapManager.swift                 # 키 리맵 (hidutil, 카라비너 대체 + 외장 미디어 키)
├── LoginItemManager.swift                # 로그인 항목 (SMAppService)
├── SettingsWindowController.swift        # 설정 창 (단축키·일반·입력 소스 탭, 버전 표시)
├── Display/                              # 모니터 제어 (MonitorControl 방식)
│   ├── DDCService.swift                  #   Apple Silicon DDC/CI (IOAVService dlsym)
│   ├── GammaDimmer.swift                 #   DDC 불가 모니터 감마 디밍
│   ├── DisplayControlManager.swift       #   통합 계층·상태 캐시·결합 디밍·핫플러그 재스캔
│   ├── AudioOutputMonitor.swift          #   기본 오디오 출력 감시 (볼륨 키 대상 매칭)
│   ├── MediaKeyManager.swift             #   밝기·볼륨 미디어 키 이벤트 탭
│   ├── DisplayHUD.swift                  #   조절 표시기 (기본 HUD 대체)
│   └── DisplayMenuSection.swift          #   메뉴바 모니터별 슬라이더 카드
├── InputSource/                          # 입력 소스 자동 전환 (Input Source Pro 방식)
│   ├── InputSourceManager.swift          #   TIS 전환·앱별 규칙·활성화 감시
│   ├── InputSourceIndicator.swift        #   한/A 배지 오버레이 (캐럿 근처)
│   └── InputSourceSettingsTab.swift      #   설정 창 "입력 소스" 탭
├── HintMode/                             # 키보드 화면 접근
│   ├── HintModeController.swift          #   모드 오케스트레이터 (힌트→스크롤→그리드→창)
│   ├── ModeOverlayController.swift       #   모드 오버레이 공통 기반 (패널·키 모니터)
│   ├── AXHelpers.swift                   #   AX CF 캐스트·조회 공용 헬퍼
│   ├── HintTargetCollector.swift         #   AX 트리 순회·요소 수집
│   ├── HintOverlayController.swift       #   라벨 오버레이 + 키 입력
│   ├── ScrollModeController.swift        #   HJKL 스크롤 + HUD
│   ├── GridModeController.swift          #   3×3 그리드 (warpd 방식)
│   ├── HintActionPerformer.swift         #   AXPress·클릭·커서 이동 합성
│   └── HintLabeler / ScreenCoords / AccessibilityPermission
├── Window/                               # 창 배치 (Rectangle 방식)
│   ├── WindowManager.swift               #   창 프레임 계산·AX 적용·복원
│   ├── WindowModeController.swift        #   창 모드 HUD
│   └── WindowSettings.swift              #   단축키·순환·간격 설정 모델
└── Providers/                            # SearchProvider 구현들
    ├── AppProvider / FileSearchProvider / CalculatorProvider
    ├── ClipboardProvider / SystemActionProvider / WebSearchProvider
    ├── BookmarkProvider.swift            #   브라우저 북마크 (Chromium 계열 4종)
    ├── MenuItemProvider.swift            #   ">" 메뉴 항목 검색 (Paletro 방식)
    ├── EmojiProvider / EmojiCatalog      #   ":" 이모지 검색
    ├── SystemSettingsProvider.swift      #   시스템 설정 패널 검색
    ├── UIElementProvider.swift           #   ";" UI 요소 검색
    ├── DisplayProvider.swift             #   모니터 밝기·볼륨·대비 명령
    ├── InputSourceProvider.swift         #   입력규칙·한영 전환 명령
    ├── WindowCommandProvider.swift       #   "창 왼쪽" 등 창 배치 명령
    ├── SnippetProvider.swift             #   스니펫 검색·추가·삭제
    ├── TabProvider.swift                 #   "탭" 브라우저 탭 검색 (JXA)
    └── AwakeProvider.swift               #   깨어있기 세션

assets/AppIcon.icns                       # 앱 아이콘 (scripts/make-icon.swift로 생성)
```
