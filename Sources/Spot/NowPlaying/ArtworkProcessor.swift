import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 음악 앱에서 받은 앨범 아트 원본을 위젯에 맞게 다듬는다.
enum ArtworkProcessor {
    struct Output: Sendable {
        /// 위젯에 그릴 크기로 줄인 앨범 아트 (JPEG).
        let artwork: Data
        /// 위젯 배경: 아트를 흐리고, 흰 글자가 읽히도록 어둡게 한 그림 (JPEG).
        let backdrop: Data
    }

    /// 큰 위젯의 아트가 약 210pt라 2배 화면 기준으로 넉넉한 크기. 원본(보통 수천 픽셀)을 그대로 넘기면 위젯이 그리지 못한다.
    private static let artworkPixels = 600
    private static let backdropPixels = 240
    /// 흰 글자 대비 4.5:1을 넘기려면 배경의 상대 휘도가 0.18 아래여야 한다. 여유를 둔 목표값.
    private static let targetLuminance = 0.13
    private static let brightSpotLuminance = 0.22

    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func process(_ data: Data) -> Output? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: artworkPixels,
              ] as CFDictionary),
              let artwork = jpeg(image, quality: 0.86),
              let backdropImage = makeBackdrop(from: image),
              let backdrop = jpeg(backdropImage, quality: 0.8) else { return nil }
        return Output(artwork: artwork, backdrop: backdrop)
    }

    static func makeBackdrop(from image: CGImage) -> CGImage? {
        let side = CGFloat(backdropPixels)
        let scale = side / CGFloat(max(image.width, image.height))
        let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.integral
        // 큰 색 덩어리만 남도록 세게 흐리고, 흐리면서 빠진 채도를 조금 올린다.
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: side * 0.18)
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.3])
        guard let rendered = context.createCGImage(blurred, from: extent, format: .RGBA8, colorSpace: sRGB) else { return nil }

        let (width, height) = (rendered.width, rendered.height)
        guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        canvas.draw(rendered, in: rect)
        canvas.setFillColor(CGColor(gray: 0, alpha: dimming(for: rendered)))
        canvas.fill(rect)
        return canvas.makeImage()
    }

    /// 흰 글자가 읽히려면 검정을 얼마나 덮어야 하는지 (0...1).
    private static func dimming(for image: CGImage) -> CGFloat {
        // 4×4로 줄여 전체 평균과 가장 밝은 구역을 본다. 반은 희고 반은 검은 표지처럼 평균만으로는 모자란 경우가 있다.
        let grid = 4
        var pixels = [UInt8](repeating: 0, count: grid * grid * 4)
        guard let sampler = CGContext(data: &pixels, width: grid, height: grid, bitsPerComponent: 8, bytesPerRow: grid * 4,
                                      space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return 0.4 }
        sampler.interpolationQuality = .medium
        sampler.draw(image, in: CGRect(x: 0, y: 0, width: grid, height: grid))

        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let cells = (0..<grid * grid).map { index -> Double in
            let i = index * 4
            return 0.2126 * linear(pixels[i]) + 0.7152 * linear(pixels[i + 1]) + 0.0722 * linear(pixels[i + 2])
        }
        let mean = cells.reduce(0, +) / Double(cells.count)
        let brightest = cells.max() ?? mean

        // 검정을 a만큼 덮으면 색값이 (1-a)배, 휘도는 대략 (1-a)^2.2배가 된다.
        let factor = min(targetLuminance / max(mean, 0.0001), brightSpotLuminance / max(brightest, 0.0001))
        let needed = factor < 1 ? 1 - pow(factor, 1 / 2.2) : 0
        return CGFloat(min(max(needed, 0.12), 0.8))
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
