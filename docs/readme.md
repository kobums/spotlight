# Spot 문서

Spot은 개인용 macOS 런처(⌥Space) + 키보드 화면 접근 도구(⌃Space)다.
빠른 시작은 [루트 README](../README.md), 그 이상은 아래 문서를 본다.

## 문서 목록

| 문서 | 대상 | 내용 |
|---|---|---|
| [features.md](features.md) | 사용자 | 전체 기능 상세 — 런처의 12개 검색 모드, 키보드 화면 접근 4개 모드의 키맵과 동작 |
| [architecture.md](architecture.md) | 개발자 | 코드 구조와 구현 방식 — 검색 파이프라인, 접근성 API 활용, 좌표계, 한글 IME 대응, 권한·서명, 트러블슈팅 |
| [research.md](research.md) | 설계 배경 | 개발 전 조사 — 기존 런처(Raycast/Alfred/LaunchBar…)와 키보드 접근 앱(Homerow/Shortcat/warpd…) 분석 |
| [window-management.md](window-management.md) | 설계 배경 | 창 관리(Rectangle 대체) 조사·설계 — 채택 범위, 창 모드 키맵, AX 창 이동 함정 |
| [display-control.md](display-control.md) | 설계 배경 | 모니터 제어(MonitorControl 대체) 조사·설계 — DDC/CI, 비공개 API, 감마 폴백 |
| [input-source.md](input-source.md) | 설계 배경 | 입력 소스 자동 전환(Input Source Pro 대체) 조사·설계 — TIS, 앱별 규칙, 인디케이터 |

## 구현 연혁 요약

| 날짜 | 내용 |
|---|---|
| 2026-07-18 | 런처 기반 (앱/파일/계산/클립보드/시스템 액션/웹 검색, frecency 랭킹) |
| 2026-07-18 | 힌트 모드 (⌃Space, Homerow 방식 키보드 화면 클릭) |
| 2026-07-18 | Apple Development 서명 도입 — 재설치 시 손쉬운 사용 권한 유지 |
| 2026-07-18 | 한글 입력 상태 힌트 라벨 입력 (keyCode 기반 매핑) |
| 2026-07-19 | 전체 리팩토링 (SearchProvider 프로토콜, 점수 중앙화, 저장 로직 통합) |
| 2026-07-19 | 앱 한글 이름 검색 (loctable/lproj 직접 읽기) |
| 2026-07-19 | 잠자기 방지 세션 (awake, IOPMAssertion) |
| 2026-07-19 | UI 요소 검색 모드 (";" 접두사, Shortcat 방식) |
| 2026-07-19 | 스크롤 모드 (HJKL, ⌃Space 순환) |
| 2026-07-19 | 그리드 모드 (3×3 재귀 분할, warpd 방식, 접근성 트리 없는 앱 폴백) |
| 2026-07-19 | 앱 아이콘 (CoreGraphics 생성 스크립트) |
| 2026-07-19 | 키 리맵 — Karabiner-Elements 대체 (hidutil, 우측⌘ 한/영·Caps→⌃) |
| 2026-07-19 | 창 모드 1단계 — Rectangle 대체 (힌트에서 ".", 절반 사이클·코너·최대화·복원) |
| 2026-07-19 | 창 배치 전역 단축키 — Rectangle 단축키 호환 16개, 디스플레이 이동·작게/크게·높이 최대화 |
| 2026-07-19 | 설정 창 — 단축키 레코더, 순환 분율(½·⅔·¾·¼·⅓), 창 간격, JSON 영속 |
| 2026-07-19 | 시스템 설정 패널 검색 — Spotlight 방식, 한글·초성·별칭, x-apple.systempreferences |
| 2026-07-20 | 모니터 제어 — MonitorControl 대체 (DDC/CI 밝기·볼륨·음소거, 감마 폴백, 핫플러그 재스캔) |
| 2026-07-20 | 입력 소스 자동 전환 — Input Source Pro 대체 (앱별 규칙, 한/A 인디케이터, TIS) |
| 2026-07-20 | 설정 창 "입력 소스" 탭 — 규칙 관리 UI, 인디케이터 옵션, 구식 포맷 마이그레이션 |
| 2026-07-20 | 리팩토링 — 오버레이 공통 기반(ModeOverlayController), AX 헬퍼, 명령 키워드 점수 통합, Window/ 분리 |
