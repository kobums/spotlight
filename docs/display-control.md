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

**진짜 원인 규명 (2026-08-24)**:

| 모니터 | 상태 | 제어 방법 |
|---|---|---|
| LG HDR 4K (dcpext0, DisplayPort) | DDC 정상 — 밝기·볼륨·음소거 전부 읽고 쓴다 | **DDC 하드웨어** |
| DELL U2715H (dcpext1, HDMI) | I²C write 자체가 실패 (`0xE0114000`) | 감마 디밍 |

**원인은 하드웨어가 아니라 이 저장소의 버그였다. `read`가 요청을 1회만 보냈다.**

이 LG는 DDC 요청을 1회만 받으면 규격상 "거부"를 뜻하는 NULL 메시지를 돌려준다.
대기 시간을 10·50·80ms 어느 쪽으로 늘려도 소용없다 — 오직 전송 횟수만이 변수다:

```
1회 전송, 10ms 대기 : 볼륨 읽기 0/5
1회 전송, 50ms 대기 : 0/5
1회 전송, 80ms 대기 : 0/5
2회 전송            : 5/5
3회 전송            : 5/5
```

m1ddc의 `DDC_ITERATIONS = 2`와 *"Depending on display this must be set higher"* 주석이
정확히 이 때문이다. 그리고 `rescan()`이 **밝기 읽기에 성공한 모니터만 DDC로 채택**하는 구조라,
읽기 실패 하나가 멀쩡한 모니터까지 전부 감마 디밍으로 강등시켰다. 쓰기 경로는 처음부터
정상이었는데 시도조차 되지 않았다.

교차 검증: 고친 뒤 읽은 LG 볼륨 값 `12`가 MonitorControl 프리퍼런스에 남아 있던
`value98(LGHDR4K...@4) = 0.125`(12.5%)와 일치한다. 거짓 양성이 아니다.

**7월 기록의 "밝기 100/100 읽기 성공"은 거짓 양성이었을 가능성이 높다.** 당시 코드도 1회
전송이었으므로 성공할 수 없었고, 응답 검사가 헤더의 NULL 메시지를 걸러내지 않아 I²C 버스에
남은 잔여 데이터가 `reply[2] == 0x02` 조건을 우연히 통과할 수 있었다.

DELL의 실패는 성격이 다르다. NULL 응답이 아니라 I²C write 자체가 실패하므로 그 링크가
DDC를 통과시키지 못하는 것이다(HDMI 직결 또는 독 경유). 전송 횟수를 늘려도 달라지지 않았다.

애플 네이티브 밝기 경로는 별개로 막혀 있다 — `DisplayServicesCanChangeBrightness`가
두 디스플레이 모두 false, `GetBrightness`는 rc=1000. DDC가 유일한 하드웨어 경로다.

### 볼륨을 살리려다 판 막다른 길 (2026-08-24)

위의 진짜 원인을 찾기 전에 시도했던 것들. **전부 헛다리였으니 다시 파지 말 것.**

1. **LG 대체 I²C 소스 주소 0x50**. 최근 LG는 표준 0x51 대신 0x50을 쓴다고 알려져 있다
   (ddcutil `--i2c-source-addr`, BetterDisplay #4246). chip/src/checksum 4개 조합을
   각 3회씩 시험 — 전부 실패. **주소는 원인이 아니었다** (1회 전송이 원인이라 무엇을 바꿔도
   실패할 수밖에 없었다).

2. **읽기 체크섬의 `0x51`**. m1ddc는 읽기 체크섬에 소스 주소를 넣지 않고 쓰기에는 넣는다.
   이 저장소는 양쪽 다 넣고 있었다. 불일치는 맞지만 **이 모니터에서는 넣든 빼든 동작한다** —
   원인이 아니었다. 지금은 여러 기종에서 검증된 m1ddc 쪽에 맞춰 두었다.

3. **`LG Monitor Controls` USB HID (0x043E/0x9A39)**. 이 모니터는 `HID I2C`라는 이름의
   벤더 HID 인터페이스와 CDC 시리얼(`/dev/cu.usbmodem<시리얼>`)을 노출한다. DP AUX가
   막힌 줄 알고 USB로 DDC를 터널링하려 했다.
   - 장치 열기·feature 리포트 읽기는 성공하나, 돌아오는 64바이트는 PID·시리얼 문자열이
     박힌 **정적 장치 식별 리포트**다. 모니터 OSD로 볼륨을 조작하며 90초간 폴링해도
     한 바이트도 변하지 않는다.
   - 같은 VID/PID를 다룬 공개 구현체([gist](https://gist.github.com/shinyquagsire23/f6b2adef253c6c3ab557a4852bf3abad))의
     프레이밍을 재현해 VCP Get을 보냈으나 프리픽스 4종 × output/feature × VCP 2종 = 16조합 전부 무응답.
   - **애초에 필요 없는 우회로였다.** DP 쪽 DDC가 멀쩡했다.

**교훈**: 외부 요인(하드웨어·모니터·OS)을 탓하기 전에 참조 구현(m1ddc)과 바이트 단위로
대조할 것. "MonitorControl에서는 됐었다"는 사용자 증언이 결정적 단서였다 — 같은 하드웨어에서
다른 소프트웨어가 되면 원인은 하드웨어가 아니다.

## 채택 범위

- **밝기 제어** (주 사용): DDC 우선, 무응답 모니터는 감마 디밍 자동 폴백
- **볼륨·음소거 제어**: DDC 모니터만. 대상은 오디오 장치 매칭 (아래)
- **대비 제어** (2026-08-26 채택): VCP 0x12, 런처 명령만. LG 실측 70/100 읽기 확인
- **결합 디밍** (2026-08-26 채택): DDC 밝기 0 밑으로 계속 내리면 감마로 이어서
  어두워진다 (MonitorControl의 hardware+software dimming). 올릴 때는 감마부터 원복
- **미디어 키 가로채기** (2026-08-24 채택): 아래 참조. 당초 "HHKB에 밝기 키 없음"을 이유로
  미채택했으나, hidutil로 F1/F2를 Consumer 밝기 키로 만들 수 있다는 게 확인되며 뒤집혔다
- 미채택: 메뉴바 슬라이더·네이티브 OSD(비공개 OSDManager 프레임워크 — 자체 HUD로 충분),
  밝기 동기화·부드러운 전환, 색온도,
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
(리맵이 완전히 변환). `fn+F10`(MUTE)은 두 차례 테스트에서 이벤트가 잡히지 않아 미확인이다 —
DDC 수정 이후에는 음소거 대상(LG)이 생겼으므로 다시 확인할 것.

설계 원칙: **처리한 키만 삼킨다.** 제어 대상이 없으면(`adjust*`가 nil) 이벤트를 그대로
흘려보내 내장 디스플레이·일반 오디오 장치의 기본 동작을 해치지 않는다.
기본 6%(macOS 16단계), `⇧⌥` 동시 입력 시 2%.

**조절 대상은 키마다 다르다** (2026-08-26, MonitorControl 라우팅 이식):

- **밝기**: 마우스 포인터가 올라간 화면 — 밝기는 화면별 속성
- **볼륨·음소거**: **기본 오디오 출력 장치와 이름이 일치하는 DDC 모니터**
  (`AudioOutputMonitor` — CoreAudio 기본 출력 장치 리스너 + 공백·숫자 제거 정규화 비교,
  MonitorControl의 `MultiKeyboardVolume.audioDeviceNameMatching`과 동일).
  소리는 커서와 무관하게 한 곳으로 나가므로 커서 라우팅을 쓰면 안 된다 —
  초기 구현이 커서 화면 기준이라 커서가 DELL(볼륨 미지원)에 있으면 fn+F11/F12가
  죽는 버그가 있었다. 매칭 모니터가 없으면(내장 스피커·에어팟 등) 이벤트를
  시스템에 흘려보내 기본 동작에 양보한다.

## 런처 명령

| 입력 | 동작 |
|---|---|
| `밝기` | 모니터별 현재 밝기 표시 (방법 표기: DDC/감마) |
| `밝기 50` | 모든 모니터 50% |
| `밝기 +10` / `밝기 -10` | 상대 조절 |
| `밝기 lg 30` / `밝기 dell 70` | 개별 모니터 (이름 fuzzy) |
| `볼륨` / `볼륨 30` / `볼륨 +5` | 모니터 스피커 볼륨 (DDC 모니터만) |
| `대비` / `대비 70` / `대비 +5` | 모니터 대비 (DDC 모니터만) |
| `음소거` | 음소거 토글 |

키워드: 밝기/brightness, 볼륨/volume/모니터볼륨, 대비/contrast/명암, 음소거/mute.

## 컴포넌트

```
Sources/Spot/Display/
├── DDCService.swift          IOAVService dlsym 바인딩(실패 시 DDC 전체 비활성),
│                             DCPAVServiceProxy 열거, VCP 읽기/쓰기(요청 2회 전송)
├── GammaDimmer.swift         CGSetDisplayTransferByFormula 감마 스케일,
│                             디스플레이 재구성 콜백에서 재적용
├── DisplayControlManager.swift  통합 계층 — 모니터 목록·식별, 방법(ddc|gamma) 자동 판정,
│                             밝기/볼륨/대비 get/set(0~100), 결합 디밍, 상태 캐시
├── AudioOutputMonitor.swift  CoreAudio 기본 출력 장치 감시 — 볼륨 키 대상 매칭 근거
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
  — 키 도착·모니터 열거·감마 조절은 실측 검증 완료. 밝기 키는 배포 후 실사용 확인됨
- [x] 3단계: DDC 읽기 1회 전송 버그 수정 (2026-08-24)
  — LG가 DDC로 승격되어 밝기가 감마가 아닌 **하드웨어 백라이트**로 바뀌었고,
  **모니터 볼륨·음소거 제어가 처음으로 동작**한다
- [x] 4단계: 볼륨 키 오디오 장치 매칭 + 대비 명령 + 결합 디밍 (2026-08-26)
  — 볼륨 키가 커서 화면이 아니라 소리 나는 모니터로 가도록 수정 (커서가 DELL에
  있으면 fn+F11/F12가 죽던 버그). 오디오 매칭은 실기기 검증(LG 매칭·DELL 비매칭),
  fn+F10 음소거와 결합 디밍은 배포 후 실사용 확인 필요
- [ ] 후보: 밝기 전역 단축키(설정 창 연동), 모니터 간 밝기 동기화,
  DELL DP 직결 시 DDC 재프로브, 모니터별 오디오 장치 이름 수동 지정
  (MonitorControl의 audioDeviceNameOverride — 화면 이름과 오디오 이름이 다른 기종용)
