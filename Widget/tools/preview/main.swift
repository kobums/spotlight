// 위젯 화면을 PNG로 뽑아 보는 도구. 위젯을 바탕화면에 올리지 않고도 배치·글자·배경 밝기를 확인한다.
// 실제 위젯과 같은 뷰(NowPlayingCard, CardBackdrop)와 같은 아트 처리(ArtworkProcessor)를 쓴다.
// 실행은 tools/render_previews.sh 참고.
import AppKit
import SwiftUI

// MARK: - 시험용 앨범 아트

func makeArtwork(_ draw: (CGContext, CGFloat) -> Void) -> Data {
    let side = 1200
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    draw(context, CGFloat(side))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func gradient(_ context: CGContext, _ side: CGFloat, _ colors: [UInt32]) {
    let gradient = CGGradient(colorsSpace: nil, colors: colors.map(color) as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
}

let vivid = makeArtwork { context, side in
    gradient(context, side, [0xFF3D77, 0xFF9A3D, 0xFFD23D])
    context.setFillColor(color(0x5B2BE0))
    context.fillEllipse(in: CGRect(x: side * 0.45, y: side * 0.4, width: side * 0.7, height: side * 0.7))
    context.setFillColor(color(0x13C4A3))
    context.fillEllipse(in: CGRect(x: -side * 0.15, y: -side * 0.2, width: side * 0.6, height: side * 0.6))
}
let bright = makeArtwork { context, side in
    context.setFillColor(color(0xF7F4EC))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.setFillColor(color(0xF2C6D0))
    context.fillEllipse(in: CGRect(x: side * 0.2, y: side * 0.25, width: side * 0.6, height: side * 0.6))
    context.setFillColor(color(0x2B2B2B))
    context.fill(CGRect(x: side * 0.1, y: side * 0.08, width: side * 0.35, height: side * 0.03))
}
let split = makeArtwork { context, side in
    context.setFillColor(color(0xFFFFFF))
    context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
    context.setFillColor(color(0x000000))
    context.fill(CGRect(x: side / 2, y: 0, width: side / 2, height: side))
    context.setFillColor(color(0xE0261B))
    context.fillEllipse(in: CGRect(x: side * 0.3, y: side * 0.3, width: side * 0.4, height: side * 0.4))
}
let dark = makeArtwork { context, side in
    gradient(context, side, [0x05070D, 0x0E1B36])
    context.setStrokeColor(color(0x3E6FD9))
    context.setLineWidth(side * 0.012)
    for i in 0..<6 {
        let inset = side * (0.12 + 0.06 * CGFloat(i))
        context.strokeEllipse(in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
    }
}

// MARK: - 그릴 장면

struct Scene {
    let name: String
    var snapshot: NowPlayingSnapshot?
    var artworkData: Data?
    var palette = CardPalette.onBackdrop
    var colorScheme: ColorScheme?
    /// 시스템이 배경을 걷어 낸 모드를 흉내 낼 때의 바탕색.
    var plainBackground: Color?
}

func track(_ title: String, _ artist: String, _ album: String, state: NowPlayingSnapshot.PlaybackState = .playing,
           duration: TimeInterval = 214, position: TimeInterval = 72) -> NowPlayingSnapshot {
    var snapshot = NowPlayingSnapshot()
    snapshot.state = state
    snapshot.title = title
    snapshot.artist = artist
    snapshot.album = album
    snapshot.duration = duration
    snapshot.position = position
    snapshot.positionDate = Date()
    return snapshot
}

var scenes: [Scene] = [
    Scene(name: "1-vivid-playing", snapshot: track("Atlantis", "찬민", "호흡 I - EP"), artworkData: vivid),
    Scene(name: "2-bright-paused", snapshot: track("run", "오왼", "Smile", state: .paused, duration: 161, position: 20), artworkData: bright),
    Scene(name: "3-split-long-text",
          snapshot: track("WOAHx7 (feat. 아주 길고 긴 피처링 아티스트 이름이 붙은 제목)", "스윙스, hyeminsong, 율음, shinjihang & 그냥노창",
                          "The Ship Of Theseus (Deluxe Anniversary Edition)", duration: 3725, position: 3000),
          artworkData: split),
    Scene(name: "4-dark-playing", snapshot: track("Midnight", "Night Tempo", "Neo Standard"), artworkData: dark),
    Scene(name: "5-no-artwork", snapshot: track("아트 없는 곡", "아티스트", "앨범", duration: 0)),
    Scene(name: "6-empty", snapshot: nil),
    Scene(name: "7-plain-light", snapshot: track("Atlantis", "찬민", "호흡 I - EP"), artworkData: vivid,
          palette: .system, colorScheme: .light, plainBackground: Color(white: 0.93)),
    Scene(name: "8-plain-dark", snapshot: track("Atlantis", "찬민", "호흡 I - EP"), artworkData: vivid,
          palette: .system, colorScheme: .dark, plainBackground: Color(white: 0.16)),
    // 바탕화면 위젯이 창 뒤에서 흐려질 때(단색 모드): 시스템이 배경을 어두운 판으로 바꾸고 색을 뺀다. 아트만 제 색.
    Scene(name: "9-desktop-dimmed", snapshot: track("Atlantis", "찬민", "호흡 I - EP"), artworkData: vivid,
          plainBackground: Color(white: 0.07)),
]

// 실제 앨범 아트 파일을 인자로 주면 그 그림으로도 그린다.
let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first else {
    print("사용법: render_previews <출력 폴더> [앨범 아트 파일…]")
    exit(1)
}
for (index, path) in arguments.dropFirst().enumerated() {
    guard let data = FileManager.default.contents(atPath: path) else { continue }
    scenes.append(Scene(name: "file-\(index + 1)", snapshot: track("Atlantis", "찬민", "호흡 I - EP"), artworkData: data))
}

// MARK: - 그리기

struct WidgetFrame: View {
    let scene: Scene
    let size: CardSize
    let artwork: NSImage?
    let backdrop: NSImage?

    // macOS 26에서 잰 위젯 크기(pt). 안쪽 여백 18, 모서리 28. (위젯 로그의 "타임라인 systemMedium 344×164" 참고)
    private var dimensions: CGSize {
        switch size {
        case .small: CGSize(width: 164, height: 164)
        case .medium: CGSize(width: 344, height: 164)
        case .large: CGSize(width: 344, height: 344)
        }
    }

    var body: some View {
        NowPlayingCard(snapshot: scene.snapshot, artwork: artwork, size: size, palette: scene.palette)
            // 위젯 밖에서는 시간에 따라 흐르는 막대를 그릴 수 없어, 지금 위치에서 멈춘 모습으로 그린다.
            .environment(\.freezesProgress, true)
            .padding(18)
            .frame(width: dimensions.width, height: dimensions.height)
            .background {
                if let plain = scene.plainBackground {
                    plain
                } else {
                    CardBackdrop(image: scene.snapshot?.hasTrack == true ? backdrop : nil)
                }
            }
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
    }
}

struct Sheet: View {
    let scene: Scene
    let artwork: NSImage?
    let backdrop: NSImage?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            WidgetFrame(scene: scene, size: .small, artwork: artwork, backdrop: backdrop)
            WidgetFrame(scene: scene, size: .medium, artwork: artwork, backdrop: backdrop)
            WidgetFrame(scene: scene, size: .large, artwork: artwork, backdrop: backdrop)
        }
        .padding(24)
        .background(LinearGradient(colors: [Color(red: 0.36, green: 0.45, blue: 0.62), Color(red: 0.62, green: 0.52, blue: 0.60)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .environment(\.colorScheme, scene.colorScheme ?? .dark)
    }
}

@MainActor
func render(_ view: some View) -> Data? {
    // ImageRenderer는 AppKit으로 그려지는 시스템 컨트롤을 빼먹는다. 화면 밖 창에 올려서 찍으면 무엇이 섞여도 그려진다.
    let hosting = NSHostingView(rootView: view)
    let size = hosting.fittingSize
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = hosting
    window.orderBack(nil)
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    window.orderOut(nil)
    return rep.representation(using: .png, properties: [:])
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let output = URL(fileURLWithPath: outputPath, isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// 최상위 코드는 메인 스레드에서 돈다.
try MainActor.assumeIsolated {
    for scene in scenes {
        var artwork: NSImage?
        var backdrop: NSImage?
        if let data = scene.artworkData, let processed = ArtworkProcessor.process(data) {
            artwork = NSImage(data: processed.artwork)
            backdrop = NSImage(data: processed.backdrop)
            try processed.backdrop.write(to: output.appendingPathComponent("\(scene.name)-backdrop.jpg"))
        }
        guard let png = render(Sheet(scene: scene, artwork: artwork, backdrop: backdrop)) else {
            print("그리기 실패:", scene.name)
            continue
        }
        let url = output.appendingPathComponent("\(scene.name).png")
        try png.write(to: url)
        print(url.path)
    }
}
