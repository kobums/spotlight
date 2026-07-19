# Spot

개인용 macOS 생산성 앱. 두 개의 축으로 이루어져 있다:

1. **런처 (⌥Space)** — Spotlight/Raycast/Alfred/LaunchBar의 장점만 모은 검색창.
   앱·파일·계산·클립보드·시스템 액션·시스템 설정·웹 검색·UI 요소 클릭·잠자기 방지.
2. **키보드 화면 접근 (⌃Space)** — Homerow/Vimium/warpd 방식.
   마우스 없이 화면의 아무 요소나 클릭·스크롤하는 힌트/스크롤/그리드 모드.

Swift 네이티브(SwiftPM + AppKit + SwiftUI), 외부 의존성 0개, 네트워크 통신·텔레메트리 없음.

## 실행

```bash
# 개발 실행
swift run

# 설치 (빌드 → 서명 → /Applications 복사 → 실행)
./scripts/install.sh
```

첫 실행 시 로그인 항목에 자동 등록된다. 끄려면 메뉴바 아이콘 → "로그인 시 자동 실행" 토글.

## 기능 한눈에

### 런처 — ⌥Space

| 입력 | 동작 |
|---|---|
| (빈 입력) | 자주 쓰는 앱 (frecency 순) |
| `sa`, `음악`, `ㅋㅋㅇ` | 앱 fuzzy 검색 — 한글 이름·초성 검색, 쓸수록 학습 |
| 3글자 이상 | 파일 검색 (Spotlight 인덱스, ⌥⏎ = Finder에서 보기) |
| `1+2*3`, `2^10`, `10km to mi` | 계산기 + 단위 변환 |
| `cb` 또는 `클립` | 클립보드 히스토리 — Enter 붙여넣기, ⌥⏎ 복사만 |
| `잠자기`, `다크모드`, `lock` | 시스템 액션 |
| `디스플레이`, `배터리`, `키보드` | **시스템 설정 패널** 바로 열기 (Spotlight 방식) |
| `깨어있기`, `awake 30분` | 잠자기 방지 세션 (Amphetamine 방식) |
| `;저장`, `;뒤로` | 최전면 앱 **UI 요소 검색·클릭** (Shortcat 방식) |
| `g`/`yt`/`gh`/`nv` + 검색어 | 웹 검색 (구글/유튜브/깃허브/네이버) |

### 키보드 화면 접근 — ⌃Space

| 상황 | 방법 |
|---|---|
| 보이는 요소 클릭 | **⌃Space** → 노란 라벨 타이핑 (힌트 모드) |
| 스크롤 | 힌트 모드에서 **⌃Space** 또는 **Tab** → HJKL |
| 접근성 정보 없는 앱 | 힌트 모드에서 **`/`** → 3×3 그리드 (수집 실패 시 자동 폴백) |
| 창 배치 (Rectangle 방식) | 힌트 모드에서 **`.`** → HJKL 절반·YUBN 코너·M 최대화·R 복원 |
| 창 배치 전역 단축키 | Rectangle 단축키 호환 — ⌥⌘화살표, ⌥⌘F, ⌃⌥⌫ 등 16개 |
| 창 배치 설정 | 메뉴바 → "설정…" — 단축키 변경, 크기 순환 분율, 창 간격 |
| 이름 아는 요소 | ⌥Space → `;이름` → Enter |

### 키 리맵 — Karabiner-Elements 대체

우측⌘→F18(한/영 전환), Caps Lock→좌⌃. macOS 내장 hidutil 리맵이라 권한 불필요.
메뉴바 → "키 리맵"으로 켜고 끈다.

상세 키맵과 각 기능 설명은 [docs/features.md](docs/features.md) 참조.

## 권한

- 기본 기능(런처·계산·클립보드 복사·awake·키 리맵)은 **권한 불필요**
- 힌트/스크롤/그리드 모드, UI 요소 검색, 클립보드 자동 붙여넣기는 **손쉬운 사용(Accessibility)** 권한 필요
  — 첫 사용 시 시스템 프롬프트로 안내된다. 문제가 생기면 [docs/architecture.md의 권한·서명 절](docs/architecture.md#권한과-서명) 참조

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
├── main.swift / AppDelegate.swift        # 부트스트랩, 메뉴바
├── HotKeyManager.swift                   # 글로벌 핫키 (Carbon, ⌥Space·⌃Space)
├── PanelController.swift                 # nonactivating NSPanel
├── ContentView / ResultRow / PanelChrome / SearchField   # 런처 UI
├── SearchViewModel / SearchEngine        # 쿼리 라우팅·랭킹·비동기 병합
├── Models / Ranking / FuzzyMatch         # 결과 모델·점수 상수·fzy 매칭+한글 초성
├── FrecencyStore / ClipboardStore / JSONFileStore   # 학습·히스토리·영속화
├── AwakeSessionManager.swift             # 잠자기 방지 (IOPMAssertion)
├── KeyRemapManager.swift                 # 키 리맵 (hidutil, 카라비너 대체)
├── LoginItemManager.swift                # 로그인 항목 (SMAppService)
├── HintMode/                             # 키보드 화면 접근
│   ├── HintModeController.swift          #   모드 오케스트레이터 (힌트→스크롤→그리드)
│   ├── HintTargetCollector.swift         #   AX 트리 순회·요소 수집
│   ├── HintOverlayController.swift       #   라벨 오버레이 + 키 입력
│   ├── ScrollModeController.swift        #   HJKL 스크롤 + HUD
│   ├── GridModeController.swift          #   3×3 그리드 (warpd 방식)
│   ├── WindowModeController.swift        #   창 모드 HUD (Rectangle 방식)
│   ├── WindowManager.swift               #   창 프레임 계산·AX 적용·복원
│   ├── HintActionPerformer.swift         #   AXPress·클릭·커서 이동 합성
│   └── HintLabeler / ScreenCoords / AccessibilityPermission
└── Providers/                            # SearchProvider 구현들
    ├── AppProvider / FileSearchProvider / CalculatorProvider
    ├── ClipboardProvider / SystemActionProvider / WebSearchProvider
    ├── SystemSettingsProvider.swift      #   시스템 설정 패널 검색
    ├── UIElementProvider.swift           #   ";" UI 요소 검색
    └── AwakeProvider.swift               #   깨어있기 세션

assets/AppIcon.icns                       # 앱 아이콘 (scripts/make-icon.swift로 생성)
```
