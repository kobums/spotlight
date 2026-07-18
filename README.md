# Spot

개인용 macOS 런처. Spotlight/Raycast/Alfred/LaunchBar의 장점만 모아 Swift 네이티브로 만들었다.
(설계 배경 조사는 [docs/research.md](docs/research.md) 참조)

## 실행

```bash
# 개발 실행
swift run

# 설치 (빌드 → /Applications 복사 → 실행)
./scripts/install.sh
```

첫 실행 시 로그인 항목에 자동 등록되어 재시동 후에도 실행된다.
끄고 싶으면 메뉴바 아이콘 → "로그인 시 자동 실행" 토글.

## 사용법

**⌥Space** 로 열고 닫는다. 포커스를 뺏지 않는 오버레이(nonactivating NSPanel)라 닫으면 쓰던 앱으로 그대로 복귀.

| 입력 | 동작 |
|---|---|
| (빈 입력) | 자주 쓰는 앱 (frecency 순) |
| `sa`, `ㅋㅋㅇ` 등 | 앱 fuzzy 검색 — 한글 초성 검색 지원, 쓸수록 학습됨 |
| 3글자 이상 | 파일 검색 (Spotlight 인덱스 재사용, ⌥⏎으로 Finder에서 보기) |
| `1+2*3`, `2^10` | 계산기 — Enter로 결과 복사 |
| `10km to mi`, `30c to f` | 단위 변환 (길이/무게/온도/부피/데이터) |
| `cb` 또는 `클립` | 클립보드 히스토리 — Enter로 붙여넣기 (⌥⏎은 복사만) |
| `잠자기`, `다크모드`, `lock` … | 시스템 액션 |
| `깨어있기`, `awake 30분`, `카페인 2시간` | 잠자기 방지 세션 (Amphetamine 방식, 권한 불필요) — 세션 중 메뉴바 아이콘이 ☕️로 바뀜 |
| `g 검색어` / `yt` / `gh` / `nv` | 구글/유튜브/깃허브/네이버 검색 |
| Esc | 입력 지우기 → 닫기 (Alfred 방식) |

## 힌트 모드 (⌃Space)

마우스 없이 화면을 클릭한다. Homerow/Vimium 방식.

1. **⌃Space** — 최전면 앱의 클릭 가능한 요소(버튼·링크·메뉴·입력란 등)마다 노란 라벨이 뜬다
2. 라벨 글자를 타이핑하면 후보가 좁혀지고, 완성되면 해당 요소를 클릭
3. **Esc** 취소, **Delete** 한 글자 지우기

- 요소 실행은 `AXPress` 액션 우선, 안 되면 실제 클릭 이벤트 합성 (텍스트 입력란은 캐럿 위치를 위해 항상 실제 클릭)
- 메뉴 막대 항목도 라벨이 붙는다 — 선택하면 메뉴가 열리고 방향키로 탐색
- Electron 앱(VSCode·Slack 등)은 접근성 트리를 지연 생성하므로 첫 호출이 한 박자 늦거나 재시도가 필요할 수 있다 (`AXManualAccessibility` 플래그 자동 설정)

## 랭킹

`fuzzy 점수(fzy 알고리즘) + frecency 부스트(반감기 7일 지수 감쇠)`.
자주 선택한 항목이 위로 올라온다. 데이터는 `~/Library/Application Support/Spot/`에 로컬 저장 — 네트워크 통신, 텔레메트리 없음.

## 권한

- 기본 기능은 권한 불필요 (핫키는 Carbon RegisterEventHotKey 사용)
- 클립보드 **자동 붙여넣기**와 **힌트 모드**는 손쉬운 사용(Accessibility) 권한 필요
  - 힌트 모드 첫 실행 시 시스템 프롬프트가 뜬다 → 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 Spot 허용
  - `swift run` 개발 실행 중에는 터미널 앱에 권한을 줘야 한다
  - 앱은 Apple Development 인증서로 서명되어 재설치해도 권한이 유지된다.
    ad-hoc 서명으로 설치한 경우 재설치마다 권한이 풀리며, 프롬프트가 다시 안 뜨면
    `tccutil reset Accessibility com.gowoobro.spot` 후 재시도

## 구조

```
Sources/Spot/
├── main.swift / AppDelegate.swift     # 부트스트랩, 메뉴바 아이템
├── HotKeyManager.swift                # 글로벌 핫키 (Carbon, ⌥Space·⌃Space)
├── HintMode/                          # 키보드 화면 클릭 (Homerow 방식)
│   ├── HintModeController.swift       #   오케스트레이터
│   ├── HintTargetCollector.swift      #   AX 트리 순회·요소 수집
│   ├── HintOverlayController.swift    #   라벨 오버레이 + 키 입력
│   ├── HintActionPerformer.swift      #   AXPress / 클릭 합성
│   └── HintLabeler.swift              #   Vimium식 라벨 생성
├── PanelController.swift              # nonactivating NSPanel
├── SearchField.swift / ContentView.swift  # UI (SwiftUI + NSTextField 래핑)
├── SearchViewModel.swift / SearchEngine.swift  # 쿼리 라우팅·랭킹·병합
├── FuzzyMatch.swift                   # fzy 스타일 매칭 + 한글 초성
├── FrecencyStore.swift                # 선택 이력 학습
├── ClipboardStore.swift               # 클립보드 폴링·영속화
└── Providers/                         # 앱·파일·계산·클립보드·시스템·웹
```
