# 모니터 제어 (MonitorControl 대체) — 설계

2026-07-19 조사, 2026-07-20 설계. 사용 방법은 [features.md](features.md) 참조.

## 조사 요약

[MonitorControl](https://github.com/MonitorControl/MonitorControl)의 본질은 **DDC/CI** — 모니터와
I²C로 대화해 VCP 코드(밝기 0x10, 볼륨 0x62, 음소거 0x8D)를 읽고 쓰는 표준 프로토콜이다.
모니터 하드웨어(백라이트·스피커)를 실제로 조절하며 권한이 필요 없다.

Apple Silicon에서는 공개 I²C API가 없어 MonitorControl·[m1ddc](https://github.com/waydabber/m1ddc)·Lunar
모두 **비공개 API**를 쓴다: `DCPAVServiceProxy`(IOKit, Location=External) 노드에
`IOAVServiceCreateWithService`로 접근해 `IOAVServiceWriteI2C`/`ReadI2C`로 DDC 패킷을 주고받는다.

**이 머신 라이브 확인 (2026-07-19)**:

| 모니터 | 결과 | 제어 방법 |
|---|---|---|
| LG HDR 4K (32UN88, 5K 메인) | DDC 응답 — 밝기 100/100 읽기 성공 | **DDC 하드웨어** (밝기·볼륨·음소거) |
| DELL U2715H (세로) | DDC 무응답 (두 번째 스트림 경로) | **감마 소프트웨어 디밍** (밝기만) |

## 채택 범위

- **밝기 제어** (주 사용): DDC 우선, 무응답 모니터는 감마 디밍 자동 폴백
- **볼륨·음소거 제어** (주 사용): DDC 모니터만 (LG 스피커)
- 미채택: 미디어 키 가로채기(HHKB에 밝기 키 없음 + 이벤트 탭 권한 필요),
  메뉴바 슬라이더·네이티브 OSD(런처 명령으로 충분), 명암/색온도

## 런처 명령

| 입력 | 동작 |
|---|---|
| `밝기` | 모니터별 현재 밝기 표시 (방법 표기: DDC/감마) |
| `밝기 50` | 모든 모니터 50% |
| `밝기 +10` / `밝기 -10` | 상대 조절 |
| `밝기 lg 30` / `밝기 dell 70` | 개별 모니터 (이름 fuzzy) |
| `볼륨` / `볼륨 30` / `볼륨 +5` | 모니터 스피커 볼륨 (DDC 모니터만) |
| `음소거` | 음소거 토글 |

키워드: 밝기/brightness, 볼륨/volume/모니터볼륨, 음소거/mute.

## 컴포넌트

```
Sources/Spot/Display/
├── DDCService.swift          IOAVService dlsym 바인딩(실패 시 DDC 전체 비활성),
│                             DCPAVServiceProxy 열거, VCP 읽기/쓰기(재시도 3회)
├── GammaDimmer.swift         CGSetDisplayTransferByFormula 감마 스케일,
│                             디스플레이 재구성 콜백에서 재적용
├── DisplayControlManager.swift  통합 계층 — 모니터 목록·식별, 방법(ddc|gamma) 자동 판정,
│                             밝기/볼륨 get/set(0~100), 상태 캐시
└── (Providers/)DisplayProvider.swift  런처 명령 파싱 (AwakeProvider 패턴)
```

### 설계 결정

1. **모니터 식별**: DCPAVServiceProxy의 IORegistry 경로와 AppleCLCD2의 DisplayAttributes
   (ProductName·EDID UUID)를 대조해 "LG HDR 4K"/"DELL U2715H" 이름을 얻는다.
   감마 폴백은 EDID UUID ↔ `CGDisplayCreateUUIDFromDisplayID`로 CGDisplayID와 매칭
2. **상태 캐시**: DDC 읽기는 수십 ms + 재시도라 검색 키스트로크마다 못 한다.
   시작 시·쓰기 후에만 읽고, `밝기` 조회는 캐시를 보여준다 (쓰기는 액션 시점에 비동기)
3. **비공개 API 방어**: dlsym 실패(OS 업데이트로 심볼 제거)나 DDC 무응답이면
   해당 모니터는 감마 디밍으로 강등 — 기능이 조용히 축소될 뿐 앱은 정상
4. **쓰기 검증**: DDC 쓰기 후 읽어서 확인 (일부 모니터는 조용히 무시)

### 감마 디밍의 한계 (명시)

- 백라이트가 아니라 렌더링을 어둡게 하는 것 — 검은색이 더 검어지진 않는다
- **Spot이 종료되면 시스템이 감마를 원복**한다 (상시 실행이라 실용상 무관)
- 볼륨은 불가 (하드웨어 채널이 없음)

## 로드맵

- [x] 1단계: DDC 엔진 + 감마 폴백 + 밝기·볼륨·음소거 런처 명령 전체 (2026-07-20)
  — 감마·명령 파싱·미연결 상태는 검증 완료, **DDC 실기기 검증은 모니터 재연결 시** (구현 당시 독 분리 상태)
- [ ] 후보: 밝기 전역 단축키(설정 창 연동), 모니터 간 밝기 동기화, DELL DP 직결 시 DDC 재프로브
