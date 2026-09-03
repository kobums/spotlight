import Foundation
import IOKit

/// Apple Silicon DDC/CI — 외장 모니터와 I²C 통신 (m1ddc/MonitorControl 방식).
///
/// IOAVService*는 비공개 API라 dlsym으로 바인딩한다. macOS 업데이트로 심볼이
/// 사라지면 available이 false가 될 뿐 앱은 정상 동작한다 (감마 폴백).
///
/// 모니터가 DDC/CI를 아예 지원하지 않는 경우도 흔하다 (I²C write 실패, 또는
/// 규격상 "지원 안 함"을 뜻하는 NULL 메시지 응답). 그때는 read가 nil을 돌려주고
/// DisplayControlManager가 감마 디밍으로 넘어간다.
enum DDCService {
    struct VCP {
        static let brightness: UInt8 = 0x10
        static let contrast: UInt8 = 0x12
        static let volume: UInt8 = 0x62
        static let mute: UInt8 = 0x8D
    }
    /// 음소거 VCP(0x8D) 값 (VESA MCCS)
    static let muteOn = 1
    static let muteOff = 2

    // I²C 파라미터 (m1ddc·MonitorControl Arm64DDC 기준)
    private static let chipAddress: UInt32 = 0x37
    private static let sourceAddress: UInt32 = 0x51
    private static let writeWait: UInt32 = 10_000
    private static let readWait: UInt32 = 50_000   // MonitorControl 기본값 — 10ms보다 안정적
    private static let retryWait: UInt32 = 20_000

    /// 요청을 몇 번 보낼지. **1이면 안 된다** — 이 값이 이 파일에서 가장 중요한 상수다.
    ///
    /// DDC 요청을 1회만 보내면 LG HDR 4K는 대기 시간을 10·50·80ms 어느 것으로 늘려도
    /// 0/5로 NULL 메시지(거부)를 돌려준다. 2회 보내면 5/5로 성공한다 (2026-08-24 실측).
    /// m1ddc의 DDC_ITERATIONS=2 와 "Depending on display this must be set higher"
    /// 주석이 같은 이유다. 초기 구현이 1회만 보내서 모든 DDC 읽기가 실패했고,
    /// 그 결과 멀쩡한 모니터까지 전부 감마 디밍으로 강등됐다.
    private static let writeCycles = 2

    /// 트랜잭션 전체(전송×2 + 응답)를 몇 번까지 시도할지 — MonitorControl과 동일.
    ///
    /// 초기 구현은 1회 실패를 "미지원 즉시 판정"으로 확정했는데, 이 머신의 모니터
    /// 2대에서만 검증한 성급한 일반화였다. HDMI 링크 등은 첫 트랜잭션이 실패하고
    /// 재시도에서 성공하는 경우가 있어, 같은 모니터가 MonitorControl(5회 재시도)로는
    /// 되는데 Spot으로는 감마로 강등되는 사례가 나왔다 (2026-08-26).
    private static let attempts = 5

    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias TransferFn = @convention(c) (CFTypeRef?, UInt32, UInt32, UnsafeMutableRawPointer?, UInt32) -> IOReturn

    private static let symbols: (create: CreateFn, write: TransferFn, read: TransferFn)? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let create = dlsym(handle, "IOAVServiceCreateWithService"),
              let write = dlsym(handle, "IOAVServiceWriteI2C"),
              let read = dlsym(handle, "IOAVServiceReadI2C") else { return nil }
        return (unsafeBitCast(create, to: CreateFn.self),
                unsafeBitCast(write, to: TransferFn.self),
                unsafeBitCast(read, to: TransferFn.self))
    }()

    static var available: Bool { symbols != nil }

    /// EDID에서 온 모니터 신원. 세 숫자는 각각 CGDisplayVendorNumber /
    /// CGDisplayModelNumber / CGDisplaySerialNumber 와 정확히 일치하므로
    /// CGDirectDisplayID를 확정적으로 찾는 열쇠가 된다.
    struct Identity {
        let productName: String?
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
    }

    /// DDC로 접근 가능한 외장 모니터 서비스
    struct ExternalDisplay {
        let avService: CFTypeRef
        let identity: Identity?
    }

    /// External DCPAVServiceProxy를 열거하고 각각의 모니터 신원을 붙인다.
    /// 모니터 연결이 바뀌면 다시 불러야 한다.
    static func externalDisplays() -> [ExternalDisplay] {
        guard let symbols else { return [] }
        let identities = displayIdentities()
        var found: [ExternalDisplay] = []

        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("DCPAVServiceProxy"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard property(service, "Location") as? String == "External",
                  let avService = symbols.create(kCFAllocatorDefault, service)?.takeRetainedValue()
            else { continue }

            let identity = displayToken(of: service).flatMap { identities[$0] }
            found.append(ExternalDisplay(avService: avService, identity: identity))
        }
        return found
    }

    // MARK: - VCP 읽기/쓰기

    /// VCP 값 읽기. 트랜잭션(요청 writeCycles회 전송 → 응답)을 attempts회까지 시도.
    static func read(_ avService: CFTypeRef, vcp: UInt8) -> (current: Int, max: Int)? {
        guard let symbols else { return nil }
        // 체크섬은 m1ddc와 동일하게 소스 주소를 넣지 않는다 (쓰기는 넣는다 — 아래 참조).
        // 이 모니터에서는 넣든 빼든 동작하지만, 여러 기종에서 검증된 쪽에 맞춘다.
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2]
        let length = UInt32(request.count)

        for attempt in 1...attempts {
            var wrote = true
            for _ in 0..<writeCycles {
                usleep(writeWait)
                wrote = request.withUnsafeMutableBytes {
                    symbols.write(avService, chipAddress, sourceAddress, $0.baseAddress, length)
                } == KERN_SUCCESS
            }
            if wrote {
                usleep(readWait)
                var reply = [UInt8](repeating: 0, count: 11)
                let readOK = reply.withUnsafeMutableBytes {
                    symbols.read(avService, chipAddress, sourceAddress, $0.baseAddress, 11)
                }
                if readOK == KERN_SUCCESS, reply[2] == 0x02, checksumValid(reply) {
                    return (current: Int(reply[8]) << 8 | Int(reply[9]),
                            max: Int(reply[6]) << 8 | Int(reply[7]))
                }
            }
            if attempt < attempts { usleep(retryWait) }
        }
        return nil
    }

    /// VCP 읽기 응답 검증 — MonitorControl과 같은 체크섬 대조.
    ///
    /// 주의: IOAVServiceReadI2C가 reply[1](길이 바이트)을 읽기 오프셋 값으로
    /// 덮어쓴다 (2026-08-26 실측: 오프셋 0x51이면 0x51, 0이면 0x00이 온다).
    /// 모니터는 원래 프레임(길이 0x88)으로 체크섬을 계산했으므로 그 값을
    /// 복원해서 검증한다. VCP get 응답의 길이 바이트는 항상 0x88이다.
    private static func checksumValid(_ reply: [UInt8]) -> Bool {
        var chk: UInt8 = 0x50 ^ reply[0] ^ 0x88
        for i in 2...9 { chk ^= reply[i] }
        return chk == reply[10]
    }

    /// VCP 값 쓰기. 읽기와 같은 이유로 writeCycles회 전송하고(같은 값을 두 번
    /// 세팅하는 것이라 멱등하다) 실패하면 attempts회까지 재시도한다.
    /// 쓰기 체크섬에는 소스 주소가 들어간다 — m1ddc와 동일.
    @discardableResult
    static func write(_ avService: CFTypeRef, vcp: UInt8, value: Int) -> Bool {
        guard let symbols else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ UInt8(sourceAddress) ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        let length = UInt32(packet.count)

        for attempt in 1...attempts {
            var wrote = true
            for _ in 0..<writeCycles {
                usleep(writeWait)
                wrote = packet.withUnsafeMutableBytes {
                    symbols.write(avService, chipAddress, sourceAddress, $0.baseAddress, length)
                } == KERN_SUCCESS
            }
            if wrote { return true }
            if attempt < attempts { usleep(retryWait) }
        }
        return false
    }

    // MARK: - 모니터 식별

    /// IORegistry 경로에 박힌 디스플레이 토큰("dispext0") 추출.
    ///
    /// DCPAVServiceProxy 경로:  .../dcpext0@.../dispext0:dcpav-service-epic:0/DCPAVServiceProxy
    /// 프레임버퍼 경로:          .../dispext0@B0000000/IOMobileFramebufferShim
    /// 둘 다 같은 토큰을 담고 있어 이걸로 짝을 짓는다. 부모를 타고 올라가 찾는
    /// 방식은 중간의 DCPEXT0Endpoint11 노드에서 멈춰 버려 쓸 수 없다.
    private static func displayToken(of entry: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard IORegistryEntryGetPath(entry, kIOServicePlane, &buffer) == KERN_SUCCESS else { return nil }
        let path = String(cString: buffer)
        guard let range = path.range(of: "disp(ext)?[0-9]+", options: .regularExpression) else { return nil }
        return String(path[range])
    }

    /// 디스플레이 토큰 → EDID 신원 맵
    private static func displayIdentities() -> [String: Identity] {
        var result: [String: Identity] = [:]
        var iterator = io_iterator_t()
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively),
                                       &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }

            guard let attributes = property(entry, "DisplayAttributes") as? [String: Any],
                  let product = attributes["ProductAttributes"] as? [String: Any],
                  let token = displayToken(of: entry) else { continue }

            // 세 값 모두 UInt32(_:) 대신 truncatingIfNeeded 를 써야 한다.
            // 내장 디스플레이의 ProductID는 UInt32 범위를 넘는 값(예: 56303534814273)이라
            // UInt32(_:) 변환이 트랩을 일으켜 앱이 통째로 죽는다. 클램셸이 아닌
            // 맥북 단독 사용 시 내장 디스플레이가 항상 열거되므로 매 실행마다 크래시했다
            // (2026-09-03). 내장 디스플레이는 DDC 대상이 아니라 잘린 값이어도 무해하다.
            result[token] = Identity(
                productName: product["ProductName"] as? String,
                vendor: UInt32(truncatingIfNeeded: product["LegacyManufacturerID"] as? Int ?? 0),
                model: UInt32(truncatingIfNeeded: product["ProductID"] as? Int ?? 0),
                serial: UInt32(truncatingIfNeeded: product["SerialNumber"] as? Int ?? 0))
        }
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
