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
        static let volume: UInt8 = 0x62
        static let mute: UInt8 = 0x8D
    }
    /// 음소거 VCP(0x8D) 값 (VESA MCCS)
    static let muteOn = 1
    static let muteOff = 2

    // I²C 파라미터 (m1ddc 기준)
    private static let chipAddress: UInt32 = 0x37
    private static let sourceAddress: UInt32 = 0x51
    private static let ddcWait: UInt32 = 10_000

    /// 요청을 몇 번 보낼지. **1이면 안 된다** — 이 값이 이 파일에서 가장 중요한 상수다.
    ///
    /// DDC 요청을 1회만 보내면 LG HDR 4K는 대기 시간을 10·50·80ms 어느 것으로 늘려도
    /// 0/5로 NULL 메시지(거부)를 돌려준다. 2회 보내면 5/5로 성공한다 (2026-08-24 실측).
    /// m1ddc의 DDC_ITERATIONS=2 와 "Depending on display this must be set higher"
    /// 주석이 같은 이유다. 초기 구현이 1회만 보내서 모든 DDC 읽기가 실패했고,
    /// 그 결과 멀쩡한 모니터까지 전부 감마 디밍으로 강등됐다.
    private static let ddcIterations = 2

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

    /// VCP 값 읽기. 요청을 ddcIterations 회 보낸 뒤 응답을 읽는다.
    ///
    /// 실패는 두 가지로 갈린다. I²C write 자체가 실패하면 그 링크는 DDC를 못 쓰는
    /// 경로다(HDMI 직결·독 경유 등). 응답 헤더가 NULL 메시지(길이 바이트 0x80)면
    /// 모니터가 그 기능을 지원하지 않는다는 뜻이다. 둘 다 재시도해도 달라지지 않는다.
    static func read(_ avService: CFTypeRef, vcp: UInt8) -> (current: Int, max: Int)? {
        guard let symbols else { return nil }
        // 체크섬은 m1ddc와 동일하게 소스 주소를 넣지 않는다 (쓰기는 넣는다 — 아래 참조).
        // 이 모니터에서는 넣든 빼든 동작하지만, 여러 기종에서 검증된 쪽에 맞춘다.
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = 0x6E ^ request[0] ^ request[1] ^ request[2]
        let length = UInt32(request.count)

        for _ in 0..<ddcIterations {
            usleep(ddcWait)
            let wrote = request.withUnsafeMutableBytes {
                symbols.write(avService, chipAddress, sourceAddress, $0.baseAddress, length)
            }
            guard wrote == KERN_SUCCESS else { return nil }
        }

        usleep(ddcWait)
        var reply = [UInt8](repeating: 0, count: 12)
        let readOK = reply.withUnsafeMutableBytes {
            symbols.read(avService, chipAddress, sourceAddress, $0.baseAddress, 12)
        }
        guard readOK == KERN_SUCCESS, reply[1] != 0x80, reply[2] == 0x02 else { return nil }
        return (current: Int(reply[8]) << 8 | Int(reply[9]),
                max: Int(reply[6]) << 8 | Int(reply[7]))
    }

    /// VCP 값 쓰기. 읽기와 같은 이유로 ddcIterations 회 보낸다 (같은 값을 두 번
    /// 세팅하는 것이라 멱등하다). 쓰기 체크섬에는 소스 주소가 들어간다 — m1ddc와 동일.
    @discardableResult
    static func write(_ avService: CFTypeRef, vcp: UInt8, value: Int) -> Bool {
        guard let symbols else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ UInt8(sourceAddress) ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        let length = UInt32(packet.count)

        for _ in 0..<ddcIterations {
            usleep(ddcWait)
            let result = packet.withUnsafeMutableBytes {
                symbols.write(avService, chipAddress, sourceAddress, $0.baseAddress, length)
            }
            guard result == KERN_SUCCESS else { return false }
        }
        return true
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

            result[token] = Identity(
                productName: product["ProductName"] as? String,
                vendor: UInt32(product["LegacyManufacturerID"] as? Int ?? 0),
                model: UInt32(product["ProductID"] as? Int ?? 0),
                serial: UInt32(truncatingIfNeeded: product["SerialNumber"] as? Int ?? 0))
        }
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
