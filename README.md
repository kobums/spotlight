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
| `g 검색어` / `yt` / `gh` / `nv` | 구글/유튜브/깃허브/네이버 검색 |
| Esc | 입력 지우기 → 닫기 (Alfred 방식) |

## 랭킹

`fuzzy 점수(fzy 알고리즘) + frecency 부스트(반감기 7일 지수 감쇠)`.
자주 선택한 항목이 위로 올라온다. 데이터는 `~/Library/Application Support/Spot/`에 로컬 저장 — 네트워크 통신, 텔레메트리 없음.

## 권한

- 기본 기능은 권한 불필요 (핫키는 Carbon RegisterEventHotKey 사용)
- 클립보드 **자동 붙여넣기**만 손쉬운 사용(Accessibility) 권한 필요 — 없으면 복사까지만 동작

## 구조

```
Sources/Spot/
├── main.swift / AppDelegate.swift     # 부트스트랩, 메뉴바 아이템
├── HotKeyManager.swift                # ⌥Space 글로벌 핫키 (Carbon)
├── PanelController.swift              # nonactivating NSPanel
├── SearchField.swift / ContentView.swift  # UI (SwiftUI + NSTextField 래핑)
├── SearchViewModel.swift / SearchEngine.swift  # 쿼리 라우팅·랭킹·병합
├── FuzzyMatch.swift                   # fzy 스타일 매칭 + 한글 초성
├── FrecencyStore.swift                # 선택 이력 학습
├── ClipboardStore.swift               # 클립보드 폴링·영속화
└── Providers/                         # 앱·파일·계산·클립보드·시스템·웹
```
