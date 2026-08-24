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

**재측정 (2026-08-24) — 결과가 뒤집혔다**:

| 모니터 | DDC 결과 (각 6회) | 제어 방법 |
|---|---|---|
| LG HDR 4K (dcpext0, DisplayPort) | 6/6 **NULL 메시지** — 규격상 "미지원" 응답 | 감마 디밍 |
| DELL U2715H (dcpext1, HDMI) | 6/6 **I²C write 실패** (`0xE0114000`) | 감마 디밍 |

7월엔 LG가 밝기 읽기에 응답했으나 8월엔 밝기·볼륨 모두 NULL이다. 재연결·입력 소스·펌웨어 중
무엇이 바뀌었는지는 확정하지 못했다. 애플 네이티브 경로도 동시에 막혀 있다 —
`DisplayServicesCanChangeBrightness`가 두 디스플레이 모두 false, `GetBrightness`는 rc=1000.

MonitorControl 설정(`app.monitorcontrol.MonitorControl`)에도 전 디스플레이가 `SwBrightness=1`로
남아 있었다 — **MonitorControl 역시 DDC를 포기하고 감마 디밍으로 폴백해 쓰고 있었다.**
즉 이 구성에서 DDC로 얻을 수 있는 건 현재 없고, 실제로 동작하는 경로는 감마뿐이다.

**볼륨은 이 구성에서 소프트웨어로 불가능하다.** 기본 출력이 LG 모니터(DisplayPort)이고
macOS는 DP/HDMI 오디오의 볼륨을 제어하지 못한다(`osascript -e 'get volume settings'` →
`output volume: missing value`). 남은 통로인 DDC 볼륨 VCP(0x62)마저 NULL을 돌려주므로
Spot도 MonitorControl도 쓸 수단이 없다. 해결은 하드웨어 쪽(모니터 버튼·USB DAC·헤드폰 단자).

### 볼륨을 살리려고 시도한 것들 — 전부 실패 (2026-08-24)

같은 걸 다시 파지 않도록 기록해 둔다. **아래는 모두 막다른 길로 확인됐다.**

1. **LG 대체 I²C 소스 주소 0x50**. 최근 LG는 표준 0x51 대신 0x50을 쓴다고 알려져 있다
   (ddcutil `--i2c-source-addr`, BetterDisplay #4246). chip/src/checksum 4개 조합을
   각 3회씩 시험 — LG는 전부 NULL, DELL은 전부 write 실패. **가설 기각.**

2. **`LG Monitor Controls` USB HID (0x043E/0x9A39)**. 이 모니터는 USB로 붙은 벤더 HID
   인터페이스를 노출하며, 그 이름이 `HID I2C`다(CDC 시리얼 `/dev/cu.usbmodem<시리얼>`도 함께).
   DP AUX가 막혔어도 USB로 DDC를 터널링할 수 있으리라 기대했다.
   - 장치 열기·feature 리포트 읽기는 **성공**. 다만 돌아오는 64바이트는 PID·시리얼
     문자열이 박힌 **정적 장치 식별 리포트**다.
   - 모니터 OSD로 볼륨을 직접 조작하며 90초간 폴링해도 **한 바이트도 변하지 않았다** —
     이 리포트는 볼륨 상태를 반영하지 않는다.
   - 같은 VID/PID를 다룬 공개 구현체([gist](https://gist.github.com/shinyquagsire23/f6b2adef253c6c3ab557a4852bf3abad))의
     프레이밍(64바이트, 프리픽스 `08 01 55 03 xx 00 03 37`, 페이로드 `51 82 01 <vcp> <cksum>`)을
     재현해 VCP Get을 보냈으나, 프리픽스 4종 × output/feature 2종 × VCP 2종 = **16조합 전부 무응답**.
     feature 리포트도 변화 없음(= 모니터가 아무 영향도 받지 않음).
   - **다음에 이어서 하려면** 동작하는 구현체(Windows LG OnScreen Control 등)의 USB 트래픽을
     캡처해 프레임을 역산해야 한다. 조합을 더 추측하는 건 무의미하다.

3. **LG OnScreen Control**. 이 모델+Apple Silicon 조합에 설정이 표시되지 않는
   [공개 버그](https://lgcommunity.us.com/discussion/16672/bug-32un880-apple-m1-onscreen-control-doesnt-display-settings)가 있어 기대값이 낮다. 미시도.

**결론**: 이 장비에서 모니터 볼륨을 소프트웨어로 제어할 방법을 찾지 못했다. 현실적인 대안은
가상 오디오 장치(BackgroundMusic 등으로 소프트웨어 감쇠 계층 삽입), 제어 가능한 출력 장치로
전환(USB DAC·헤드폰), 또는 모니터 자체 버튼이다. Spot이 CoreAudio Audio Server Plug-In을
직접 구현하는 건 관리자 권한·별도 프로세스·오디오 안정성 책임이 따라와 범위 밖으로 판단했다.

## 채택 범위

- **밝기 제어** (주 사용): DDC 우선, 무응답 모니터는 감마 디밍 자동 폴백
- **볼륨·음소거 제어**: DDC 모니터만. 현재 이 머신에는 대상이 없어 사실상 비활성
- **미디어 키 가로채기** (2026-08-24 채택): 아래 참조. 당초 "HHKB에 밝기 키 없음"을 이유로
  미채택했으나, hidutil로 F1/F2를 Consumer 밝기 키로 만들 수 있다는 게 확인되며 뒤집혔다
- 미채택: 메뉴바 슬라이더·네이티브 OSD(런처 명령으로 충분), 명암/색온도,
  LG 벤더 HID(`LG Monitor Controls`, 0x43E:0x9A39) 리버스 엔지니어링

## 미디어 키 경로

macOS는 제어 가능한 디스플레이가 없으면 밝기 키를 그냥 버리고, DP/HDMI 오디오에는
볼륨 키를 아예 전달하지 않는다. `MediaKeyManager`가 그 키를 이벤트 탭으로 잡아
`DisplayControlManager`로 넘긴다.

```
HHKB fn+F1/F2 ──hidutil 리맵──> Consumer 0x70/0x6F ──> NX_KEYTYPE_BRIGHTNESS_DOWN/UP
                                                            │
                                          MediaKeyManager 이벤트 탭 (손쉬운 사용 권한)
                                                            │
                                       DisplayControlManager (DDC 또는 감마) + DisplayHUD
```

**실측 검증 (2026-08-24)**: 관찰 전용 탭으로 `fn+F1/F2` → `BRIGHTNESS_DOWN/UP`,
`fn+F11/F12` → `SOUND_DOWN/UP` 도착을 확인했다. 일반 F1/F2 키코드는 섞이지 않는다
(리맵이 완전히 변환). `fn+F10`(MUTE)은 두 차례 테스트에서 이벤트가 잡히지 않아 미확인 —
받아줄 DDC 음소거 대상이 없어 실질 영향은 없다.

설계 원칙: **처리한 키만 삼킨다.** 제어 대상이 없으면(`adjust*`가 nil) 이벤트를 그대로
흘려보내 내장 디스플레이·일반 오디오 장치의 기본 동작을 해치지 않는다.
조절 대상은 마우스 포인터가 올라간 화면. 기본 6%(macOS 16단계), `⇧⌥` 동시 입력 시 2%.

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
├── MediaKeyManager.swift     밝기·볼륨 미디어 키 이벤트 탭 → 위 계층으로 라우팅
├── DisplayHUD.swift          조절 표시기 (macOS 기본 HUD가 안 뜨는 경우를 대신)
└── (Providers/)DisplayProvider.swift  런처 명령 파싱 (AwakeProvider 패턴)
```

### 설계 결정

1. **모니터 식별**: IORegistry 경로에 박힌 디스플레이 토큰(`dispext0`)으로 DCPAVServiceProxy와
   프레임버퍼 노드를 짝짓는다. 두 경로가 같은 토큰을 담고 있어 확정적이다.
   CGDisplayID 매칭은 EDID 3-튜플 — `LegacyManufacturerID`/`ProductID`/`SerialNumber`가
   각각 `CGDisplayVendorNumber`/`ModelNumber`/`SerialNumber`와 정확히 일치한다.

   > 초기 구현은 부모를 타고 올라가며 이름이 "dcp"로 시작하는 노드를 찾았는데,
   > 중간의 `DCPEXT0Endpoint11`에서 멈춰 버려(이 이름도 "dcp"로 시작한다) 서브트리에
   > 디스플레이 노드가 없었다. 그래서 이름이 **항상 nil**이었고 모든 모니터가
   > "외장 모니터"로 표시됐다. EDID UUID도 못 얻어 감마 폴백 중복 제거가
   > 이름 충돌 휴리스틱에 의존했다. 2026-08-24 수정.

2. **상태 캐시**: DDC 읽기는 수십 ms + 재시도라 검색 키스트로크마다 못 한다.
   시작 시·쓰기 후에만 읽고, `밝기` 조회는 캐시를 보여준다.
   캐시는 **메인 스레드 전용** — 값 계산·캐시 갱신을 메인에서 즉시 끝내고 하드웨어 쓰기만
   큐로 넘긴다. 밝기 키를 꾹 눌러 반복 입력이 쏟아져도 단계가 누락되지 않게 하기 위함
   (초기 구현은 캐시 갱신이 비동기라 연타 시 값이 어긋났다).
3. **비공개 API 방어**: dlsym 실패(OS 업데이트로 심볼 제거)나 DDC 무응답이면
   해당 모니터는 감마 디밍으로 강등 — 기능이 조용히 축소될 뿐 앱은 정상
4. **DDC 미지원 즉시 판정**: I²C write 실패나 NULL 메시지(응답 길이 바이트 0x80)는
   재시도해도 달라지지 않으므로 바로 실패로 확정한다. 초기 구현은 미지원 모니터에도
   매번 3회씩 재시도하며 300ms를 버렸다

### 감마 디밍의 한계 (명시)

- 백라이트가 아니라 렌더링을 어둡게 하는 것 — 검은색이 더 검어지진 않는다
- **Spot이 종료되면 시스템이 감마를 원복**한다 (상시 실행이라 실용상 무관)
- 볼륨은 불가 (하드웨어 채널이 없음)

## 로드맵

- [x] 1단계: DDC 엔진 + 감마 폴백 + 밝기·볼륨·음소거 런처 명령 전체 (2026-07-20)
  — 감마·명령 파싱·미연결 상태는 검증 완료, **DDC 실기기 검증은 모니터 재연결 시** (구현 당시 독 분리 상태)
- [x] 2단계: 미디어 키 제어 + HUD + 모니터 식별 버그 수정 (2026-08-24)
  — 키 도착·모니터 열거·감마 조절은 실측 검증 완료.
  **HUD 렌더링과 키 삼킴은 서명된 배포판 설치 후에만 확인 가능** (로컬 빌드는 TCC 무효)
- [ ] 후보: 밝기 전역 단축키(설정 창 연동), 모니터 간 밝기 동기화,
  DELL DP 직결 시 DDC 재프로브, 조절 대상 범위(커서 화면 ↔ 전체) 설정 노출
