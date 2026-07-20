# 입력 소스 자동 전환 (Input Source Pro 대체) — 설계

2026-07-20 조사·설계. 사용 방법은 [features.md](features.md) 참조.

## 조사 요약

[Input Source Pro](https://github.com/runjuu/InputSourcePro)(GPLv3)의 핵심은 두 가지:
**앱별 입력 소스 자동 전환**(터미널→영문, 메신저→한글)과 **인디케이터**(전환 시 현재 입력기 표시).

구현 재료는 전부 표준적이다:

| 재료 | API | 권한 |
|---|---|---|
| 입력 소스 목록·전환 | TIS (`TISSelectInputSource`) | 불필요 — 이 머신에서 ABC↔2벌식 전환 실검증 완료 |
| 앱 전환 감지 | `NSWorkspace.didActivateApplication` | 불필요 |
| 입력 소스 변경 감지 | `kTISNotifySelectedKeyboardInputSourceChanged` 분산 알림 | 불필요 |
| 캐럿 위치 (인디케이터) | AX `AXSelectedTextRange` → bounds | 손쉬운 사용 (보유) |

## 채택 범위

- 앱별 자동 전환 + 인디케이터 + 런처 명령 (1단계)
- 미채택: **웹사이트별 규칙**(불필요 확인), 수식키 탭 전환(우측⌘ 한/영이 이미 있음 + 입력 모니터링 권한 필요),
  영문 문장부호 강제

## 동작 설계

### 규칙 등록 — 런처의 포커스 비탈취 특성 활용

Spot 패널은 포커스를 뺏지 않으므로, **대상 앱을 쓰던 중 그대로** ⌥Space → `입력규칙`:

| 입력 | 결과 행 |
|---|---|
| `입력규칙` | "iTerm2를 ABC로 고정" / "iTerm2를 2-Set Korean으로 고정" / (규칙 있으면) "규칙 제거" |
| `입력규칙 목록` | 등록된 규칙 전체 — Enter로 개별 제거 |
| `입력소스` 또는 `한영` | 수동 전환 행 (현재 소스 표시) |

규칙은 `input-rules.json`(bundleID → sourceID)로 영속.

### 자동 전환

- 앱 활성화 알림 → 규칙 있으면 0.15초 지연 후 `TISSelectInputSource`
  (앱이 포커스를 완전히 잡기 전에 전환하면 씹히는 알려진 타이밍 이슈 대응 — 적용 후 검증, 1회 재시도)
- 규칙 없는 앱은 건드리지 않는다 (마지막 상태 유지)

### 인디케이터

- 트리거: 입력 소스 변경(수동 우측⌘ 포함), 규칙에 의한 자동 전환
- 표시: "한"(노랑)/"A"(회색) 배지를 캐럿 근처에 1초 — 캐럿은 AX 포커스 요소의
  선택 범위 bounds, 못 읽으면(보안 입력 등) 마우스 포인터 옆으로 폴백
- 오버레이: 키 입력을 받지 않는 순수 표시용 패널 (`orderFrontRegardless`, 클릭 통과)

## 컴포넌트

```
Sources/Spot/InputSource/
├── InputSourceManager.swift    TIS 목록/전환/현재, 규칙 저장·적용, 앱 활성화·변경 감시
└── InputSourceIndicator.swift  캐럿/포인터 근처 배지 표시
Providers/InputSourceProvider.swift  런처 명령 (입력규칙·입력소스·한영)
```

## 로드맵

- [ ] 1단계: 자동 전환 + 인디케이터 + 런처 명령
- [ ] 후보: 설정 창 "입력 소스" 탭 (규칙 목록 UI, 인디케이터 옵션)
