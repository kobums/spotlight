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

    /// VCP 값 읽기. DDC는 타이밍에 민감해 3회 재시도한다.
    /// 응답 헤더가 NULL 메시지(길이 바이트 0x80)면 모니터가 해당 기능을
    /// 지원하지 않는다는 뜻이라 재시도 없이 실패로 확정한다.
    static func read(_ avService: CFTypeRef, vcp: UInt8) -> (current: Int, max: Int)? {
        guard let symbols else { return nil }
        for _ in 0..<3 {
            var request: [UInt8] = [0x82, 0x01, vcp, 0]
            request[3] = 0x6E ^ 0x51 ^ request[0] ^ request[1] ^ request[2]
            let wrote = request.withUnsafeMutableBytes {
                symbols.write(avService, 0x37, 0x51, $0.baseAddress, 4)
            }
            guard wrote == KERN_SUCCESS else { return nil }  // I²C 자체가 안 되는 링크
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let readOK = reply.withUnsafeMutableBytes {
                symbols.read(avService, 0x37, 0x51, $0.baseAddress, 12)
            }
            if readOK == KERN_SUCCESS {
                if reply[1] == 0x80 { return nil }           // NULL 메시지 = 미지원
                if reply[2] == 0x02 {
                    return (current: Int(reply[8]) << 8 | Int(reply[9]),
                            max: Int(reply[6]) << 8 | Int(reply[7]))
                }
            }
            usleep(50_000)
        }
        return nil
    }

    /// VCP 값 쓰기
    @discardableResult
    static func write(_ avService: CFTypeRef, vcp: UInt8, value: Int) -> Bool {
        guard let symbols else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF), 0]
        packet[5] = 0x6E ^ 0x51 ^ packet[0] ^ packet[1] ^ packet[2] ^ packet[3] ^ packet[4]
        for _ in 0..<3 {
            let result = packet.withUnsafeMutableBytes {
                symbols.write(avService, 0x37, 0x51, $0.baseAddress, 6)
            }
            usleep(20_000)
            if result == KERN_SUCCESS { return true }
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
