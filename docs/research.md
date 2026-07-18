# Spotlight 런처 리서치 (2026-07-18)

새 런처("spotlight") 설계를 위해 기존 런처들을 조사하고 장점을 정리한 문서.

---

## 1. 조사 대상 지형도

| 앱 | 플랫폼 | 스택 | 핵심 정체성 |
|---|---|---|---|
| macOS Spotlight | macOS 내장 | 네이티브 (mds/mdworker) | OS 통합, macOS 26 Tahoe에서 대개편 |
| Raycast | macOS/Win(베타)/iOS | 네이티브 셸 + Node + Rust 코어 | 확장 플랫폼 + AI, 중앙 스토어 |
| Alfred | macOS | 순수 네이티브 | 최속 런처 + 워크플로우 자동화 |
| LaunchBar | macOS | 네이티브 | 약어(abbreviation) 적응 학습의 원조 |
| Quicksilver | macOS | 네이티브 (오픈소스) | Object→Verb→Target 문법 |
| PowerToys Run / CmdPal | Windows | WPF / WinRT | MS 공식, out-of-process 확장 |
| Flow Launcher | Windows | C#/WPF | 다국어 플러그인 + 내장 스토어, Win 종합 1위 평 |
| Listary | Windows | 네이티브 | 파일 검색 특화, 파일 대화상자 통합 |
| Everything | Windows | 네이티브 | NTFS MFT+USN 기반 즉시 파일 검색 (백엔드 표준) |
| Vicinae | Linux/macOS | C++/Qt + TS 확장 | **Raycast 확장 API 호환** 오픈소스, 10개월 8.5k★ |
| Sol | macOS | Swift + RN | 오픈소스, 콜드스타트 ~100ms, 내장 기능 위주 |
| Albert / Ulauncher / KRunner | Linux | C++/Qt, Python/GTK, KDE | C++/Python 이중 플러그인, D-Bus 러너 |
| Wox 2 | 크로스 | Go 코어 + Flutter UI | 코어/UI 분리 아키텍처 |

---

## 2. 각 런처에서 가져올 장점 (Best-of 모음)

### 속도 & 체감 성능
- **Alfred**: 원프롬프트 1단계 구조 — 대부분 작업이 프롬프트 하나로 끝남 (Raycast는 커맨드 진입→입력 2단계가 많아 마찰 누적). 전 영역 체감 속도 우위가 15년 충성도의 근원.
- **PowerToys Run vs CmdPal 교훈**: 기능이 더 많아도 첫 키입력~결과 표시가 느리면 진다. CmdPal은 확장 병렬 기동·타임아웃까지 도입했지만 여전히 성능이 최대 비판점.
- **Sol**: 콜드 스타트 ~100ms가 오픈소스로도 달성 가능함을 증명.

### 검색 & 랭킹
- **LaunchBar**: 약어 적응 학습 — 문자 위치·밀도 레이팅 + 사용 이력 가중치. "tm"→Time Machine처럼 이름에 없는 약어도 학습. 2주 후엔 검색이 아니라 '호출'이 됨.
- **Alfred Knowledge**: 사용 패턴 학습 랭킹 — 조용하지만 강력한 락인 요소.
- **표준 공식**: `최종점수 = fuzzy_score(fzy/nucleo 계열) × frecency_boost(Firefox식 시간감쇠)`. Raycast는 `useFrecencySorting`을 API로 공식 제공.
- **Everything**: 파일 검색은 NTFS MFT 직독 + USN Journal 증분 갱신 + 인메모리 인덱스. 런처들은 자체 인덱서 대신 Everything IPC 연동이 표준.
- **macOS**: Raycast·Alfred 모두 자체 인덱스 대신 Spotlight 인덱스(NSMetadataQuery)를 쿼리. Raycast 2.0은 Rust 자체 인덱서로 보완 시작.

### 인터랙션 문법
- **Quicksilver**: Subject–Verb–Object 3-pane — 항목 선택 → Tab → 액션 → Tab → 대상. N객체 × M액션 조합을 UI 복잡도 없이 확보. 지금도 그리워하는 사용자 다수.
- **LaunchBar Instant Send**: 현재 선택된 파일/텍스트를 핫키로 런처에 '던지기'.
- **Alfred 수식키**: Cmd/Alt/Ctrl/Shift 홀드 시 항목별 동작 재정의.
- **Raycast ⌘K 액션 패널**: 결과마다 컨텍스트 액션, 키보드만으로 전 기능.
- **macOS 26 Quick Keys**: 사용 패턴 기반 자동 약어 생성 (LaunchBar 방식의 Apple화).

### 확장 생태계
- **Raycast (승리 공식)**: React/TS 확장 + 커스텀 reconciler로 네이티브 렌더링 → 모든 확장의 룩앤필 통일 + 낮은 진입장벽 + 중앙 스토어 리뷰제. 생태계 승부처는 API 성능이 아니라 **배포/발견 UX**.
- **Alfred Workflows**: 임의 언어 스크립트가 JSON을 stdout으로 반환(Script Filter) + 비주얼 캔버스 에디터. 자동화 깊이는 최강이나 스토어 부재로 생태계 성장에서 밀림.
- **Flow Launcher**: JSON-RPC로 Python/JS/TS/실행파일 플러그인 + **앱 내장 플러그인 스토어**. PowerToys Run을 이긴 결정적 차별점.
- **Vicinae 전략**: Raycast 확장 API를 호환 구현해 기존 생태계를 그대로 흡수 — 신규 런처의 강력한 성장 레버.
- **Raycast 딥링크**: `raycast://` URL 스킴으로 모든 커맨드 외부 호출 가능 — 초기부터 설계에 포함할 가치.

### 내장 기능 (2026년 기준 기본기로 간주되는 것)
클립보드 히스토리(서식 보존), 스니펫/텍스트 확장, 계산기(단위/환율/자연어), 윈도우 관리, 이모지 피커, 파일 검색+파일 액션.
- macOS 26 Tahoe가 클립보드·액션·Quick Keys를 흡수했으므로 이것만으로는 차별화 불가.
- **Listary**: 파일 열기/저장 대화상자 통합(Quick Switch) — 타 런처에 없는 독보적 기능.
- **Raycast 캘린더 연동**: 다가오는 회의의 Zoom 링크를 Enter 한 번에 참여 — 가장 자주 인용되는 킬러 기능.

### 비즈니스 모델 & 신뢰 (커뮤니티 정서)
- 로컬 기능(클립보드 등)에 구독 과금 → 강한 반발 (Raycast 최대 비판점).
- AI 강제 노출 → 이탈 사유. **BYOK**(자기 API 키)가 검증된 절충안.
- Alfred식 **일시불 + 평생 라이선스**, 텔레메트리 없음이 그 자체로 포지셔닝.

---

## 3. 기술 아키텍처 결론

### 스택 선택
- **승리 공식: 네이티브 셸(창/핫키/인덱싱) + TS/JS 확장 런타임** — Raycast, Vicinae 공통.
- Electron 단독은 구조적으로 불리: 유휴 메모리 200–300MB, 콜드스타트 1–3초, **macOS nonactivating NSPanel 미지원**(포커스를 뺏음, electron#35815).
- Tauri v2: 메모리 30–40MB, `tauri-nspanel` 플러그인으로 우회 가능하나 제약 존재.
- 참고 사례: Raycast(AppKit+Node+Rust), Vicinae(C++/Qt+QML), Sol(Swift+RN), Loungy(Rust+GPUI), Wox 2(Go 코어+Flutter UI, 코어/UI 분리).

### 플랫폼별 핵심 제약
- **macOS**: `NSPanel` + `.nonactivatingPanel` styleMask — 앱 활성화 없이 키 입력 수신, 닫으면 이전 앱 포커스 복원 (Spotlight/Raycast 동작의 본질). 핫키는 Carbon `RegisterEventHotKey`(권한 불필요).
- **Windows**: `RegisterHotKey` + 핫키 경로에서만 `SetForegroundWindow` 허용됨(포커스 탈취 방지 정책).
- **Linux/Wayland**: 글로벌 키 그랩 금지 — XDG GlobalShortcuts 포털 시도 → 실패 시 "컴포지터 단축키에 `launcher toggle` CLI 바인딩" 폴백이 커뮤니티 표준.

### 파일 인덱싱
- macOS: NSMetadataQuery(Spotlight 인덱스 재사용)부터 시작, 자체 인덱스(FSEvents 증분)는 2단계 과제.
- Windows: Everything SDK(IPC) 연동, 또는 MFT+USN 자체 구현.
- Linux: 표준 인덱스 부재 → 자체 인덱스 + inotify/fanotify 필요.

### 플러그인 아키텍처 4계보
1. **JSON-RPC 프로세스 분리** (Flow): 언어 무관, 크래시 격리 / 왕복 지연.
2. **D-Bus 서비스** (KRunner): 최소 의존성.
3. **임베디드 JS + 커스텀 reconciler → 네이티브 렌더링** (Raycast): JS 생태계 + 네이티브 성능 + UI 통일 + XPC 프로세스 격리. 가장 정교.
4. **인프로세스 스크립팅** (Albert C++/Python): 빠름 / 불안정 전파.
- CmdPal(out-of-process COM/WinRT) 교훈: 격리는 좋지만 지연 관리가 설계 핵심 난제.

---

## 4. 설계 원칙 도출 (조사 종합)

1. **첫 키입력→결과 100ms는 협상 불가.** 속도는 기능보다 우선하는 계약 (CmdPal·Raycast의 고전, Alfred 잔류의 이유).
2. **원프롬프트 우선**: 최대한 1단계 프롬프트에서 해결, 커맨드 진입은 예외로. 잔 마찰의 누적이 이탈 사유.
3. **랭킹 = fuzzy × frecency + 약어 학습** (LaunchBar/Alfred Knowledge의 현대적 재해석).
4. **확장은 배포/발견 UX가 승부처**: 통일 UI 강제 + 내장 스토어. Raycast 확장 API 호환도 검토 가치(Vicinae 사례).
5. **Object→Verb 문법**(Quicksilver)과 **파일 워크플로우**는 현세대 런처의 공백 — 차별화 기회.
6. **네이티브 셸 + TS 확장 런타임** 스택. macOS라면 nonactivating NSPanel 필수.
7. **신뢰가 기능**: 텔레메트리 없음, 로컬 기능 무료, AI는 BYOK 선택형.
8. macOS 26 Tahoe가 흡수한 기능(클립보드, 액션, Quick Keys)만으로는 차별화 불가 — 속도·확장성·프라이버시·파일 워크플로우로 승부.

---

## 5. 상세 출처

각 조사 에이전트가 수집한 출처 (주요만 발췌):

- Raycast: [The New Raycast](https://www.raycast.com/blog/the-new-raycast) · [기술 딥다이브](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast) · [API 문서](https://developers.raycast.com/) · [확장 동작 원리](https://www.raycast.com/blog/how-raycast-api-extensions-work)
- Alfred: [Powerpack](https://www.alfredapp.com/powerpack/) · [Script Filter JSON](https://www.alfredapp.com/help/workflows/inputs/script-filter/json/) · [Alfred vs Raycast (Collinsworth)](https://joshcollinsworth.com/blog/alfred-raycast)
- Spotlight: [Eclectic Light — How Spotlight works](https://eclecticlight.co/2021/01/28/spotlight-on-search-how-spotlight-works/) · [9to5Mac — macOS 26 Spotlight](https://9to5mac.com/2025/06/10/macos-26-spotlight-gets-actions-clipboard-manager-custom-shortcuts/) · [MPU — Tahoe vs Raycast/Alfred](https://talk.macpowerusers.com/t/so-spotlight-in-macos-tahoe-is-almost-raycast-alfred/40947)
- LaunchBar/Quicksilver: [Abbreviation Search](https://www.obdev.at/resources/launchbar/help/AbbreviationSearch.html) · [Quicksilver Primer](https://blog.scottlowe.org/2011/05/21/a-quicksilver-primer/)
- Windows: [CmdPal Overview](https://learn.microsoft.com/en-us/windows/powertoys/command-palette/overview) · [Flow JSON-RPC](https://github.com/Flow-Launcher/docs/blob/main/json-rpc.md) · [Everything — why so fast](https://www.voidtools.com/forum/viewtopic.php?t=9407)
- 오픈소스: [Vicinae](https://github.com/vicinaehq/vicinae) · [Sol](https://github.com/ospfranco/sol) · [Loungy](https://github.com/MatthiasGrandl/Loungy) · [Wox 2](https://github.com/Wox-launcher/Wox)
- 아키텍처: [fzy ALGORITHM.md](https://github.com/jhawthorn/fzy/blob/master/ALGORITHM.md) · [nucleo](https://github.com/helix-editor/nucleo) · [Mozilla Frecency](https://firefox-source-docs.mozilla.org/browser/urlbar/ranking.html) · [NSMetadataQuery](https://developer.apple.com/documentation/foundation/nsmetadataquery) · [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) · [Electron nonactivating 이슈](https://github.com/electron/electron/issues/35815) · [Tauri vs Electron 실측](https://www.gethopp.app/blog/tauri-vs-electron)
