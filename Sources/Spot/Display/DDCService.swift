import Foundation
import IOKit

/// Apple Silicon DDC/CI — 외장 모니터와 I²C 통신 (m1ddc/MonitorControl 방식).
///
/// IOAVService*는 비공개 API라 dlsym으로 바인딩한다. macOS 업데이트로 심볼이
/// 사라지면 available이 false가 될 뿐 앱은 정상 동작한다 (감마 폴백).
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

    /// DDC로 접근 가능한 외장 모니터 서비스
    struct ExternalDisplay {
        let avService: CFTypeRef
        let productName: String?
        let edidUUID: String?
    }

    /// External DCPAVServiceProxy를 열거하고, 같은 DCP 아래 디스플레이 노드에서
    /// 모니터 이름·EDID를 찾아 붙인다. 모니터 연결이 바뀌면 다시 불러야 한다.
    static func externalDisplays() -> [ExternalDisplay] {
        guard let symbols else { return [] }
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

            let identity = displayIdentity(near: service)
            found.append(ExternalDisplay(avService: avService,
                                         productName: identity.productName,
                                         edidUUID: identity.edidUUID))
        }
        return found
    }

    // MARK: - VCP 읽기/쓰기

    /// VCP 값 읽기. DDC는 타이밍에 민감해 3회 재시도한다.
    static func read(_ avService: CFTypeRef, vcp: UInt8) -> (current: Int, max: Int)? {
        guard let symbols else { return nil }
        for _ in 0..<3 {
            var request: [UInt8] = [0x82, 0x01, vcp, 0]
            request[3] = 0x6E ^ 0x51 ^ request[0] ^ request[1] ^ request[2]
            let wrote = request.withUnsafeMutableBytes {
                symbols.write(avService, 0x37, 0x51, $0.baseAddress, 4)
            }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 12)
            let readOK = reply.withUnsafeMutableBytes {
                symbols.read(avService, 0x37, 0x51, $0.baseAddress, 12)
            }
            if wrote == KERN_SUCCESS, readOK == KERN_SUCCESS, reply[2] == 0x02 {
                return (current: Int(reply[8]) << 8 | Int(reply[9]),
                        max: Int(reply[6]) << 8 | Int(reply[7]))
            }
            usleep(50_000)
        }
        return nil
    }

    /// VCP 값 쓰기. 성공 여부는 재읽기로 검증한다 (일부 모니터는 조용히 무시).
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

    /// DCPAVServiceProxy와 같은 DCP 서브트리의 디스플레이 노드(AppleCLCD2 등)에서
    /// ProductName("LG HDR 4K")·EDID UUID를 찾는다. 감마 폴백 매칭과 이름 표시에 쓴다.
    private static func displayIdentity(near service: io_service_t) -> (productName: String?, edidUUID: String?) {
        // 부모로 올라가며 DCP 루트를 찾는다 (이름이 dcp로 시작)
        var current = service
        IOObjectRetain(current)
        for _ in 0..<8 {
            var parent = io_registry_entry_t()
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { break }
            IOObjectRelease(current)
            current = parent
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(current, &nameBuf)
            if String(cString: nameBuf).lowercased().hasPrefix("dcp") { break }
        }
        defer { IOObjectRelease(current) }

        // DCP 서브트리에서 DisplayHints/DisplayAttributes를 가진 노드 탐색
        var identity: (String?, String?) = (nil, nil)
        walkChildren(current, depth: 0) { node in
            if let hints = property(node, "DisplayHints") as? [String: Any] {
                identity = (hints["ProductName"] as? String, hints["EDID UUID"] as? String)
                return true
            }
            if let attrs = property(node, "DisplayAttributes") as? [String: Any] {
                let product = (attrs["ProductAttributes"] as? [String: Any])?["ProductName"] as? String
                identity = (product ?? attrs["ProductName"] as? String, attrs["EDID UUID"] as? String)
                return true
            }
            return false
        }
        return identity
    }

    /// 서브트리 DFS. handler가 true를 돌려주면 중단.
    @discardableResult
    private static func walkChildren(_ entry: io_registry_entry_t, depth: Int,
                                     handler: (io_registry_entry_t) -> Bool) -> Bool {
        guard depth < 10 else { return false }
        var children = io_iterator_t()
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &children) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(children) }
        while true {
            let child = IOIteratorNext(children)
            if child == 0 { break }
            defer { IOObjectRelease(child) }
            if handler(child) { return true }
            if walkChildren(child, depth: depth + 1, handler: handler) { return true }
        }
        return false
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
