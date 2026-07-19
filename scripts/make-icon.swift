#!/usr/bin/env swift
// 앱 아이콘 생성기 — 1024×1024 PNG를 그린다.
// 사용: swift scripts/make-icon.swift <출력.png>
// 디자인: 어두운 squircle 배경 + 스포트라이트 빔 + 힌트 모드 노란 라벨 "S"
import AppKit

let size: CGFloat = 1024
// macOS 아이콘 그리드: 1024 캔버스에 여백 100, squircle 824×824
let inset: CGFloat = 100
let iconRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let cornerRadius: CGFloat = 185

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

let squircle = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

// 배경: 남색 → 흑색 수직 그라데이션
squircle.addClip()
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.09, alpha: 1),
])!
bg.draw(in: squircle, angle: -90)

// 스포트라이트 빔: 상단 중앙에서 아래로 퍼지는 사다리꼴 + 방사형 광원
let beam = NSBezierPath()
beam.move(to: NSPoint(x: size * 0.5 - 70, y: iconRect.maxY))
beam.line(to: NSPoint(x: size * 0.5 + 70, y: iconRect.maxY))
beam.line(to: NSPoint(x: size * 0.5 + 300, y: iconRect.minY + 120))
beam.line(to: NSPoint(x: size * 0.5 - 300, y: iconRect.minY + 120))
beam.close()
let beamGradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.45, alpha: 0.26),
    NSColor(calibratedRed: 1.0, green: 0.88, blue: 0.45, alpha: 0.02),
])!
beamGradient.draw(in: beam, angle: -90)

// 중앙 라벨 뒤 은은한 광원
let glowCenter = CGPoint(x: size * 0.5, y: size * 0.47)
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
    CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.35),
    CGColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 0.0),
] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0,
                       endCenter: glowCenter, endRadius: 330, options: [])

// 힌트 라벨 그리기 헬퍼 — 노란 라운드 사각형 + 검은 굵은 글자
func drawHintLabel(_ text: String, center: CGPoint, width: CGFloat, height: CGFloat,
                   radius: CGFloat, fontSize: CGFloat, alpha: CGFloat, rotation: CGFloat = 0) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation * .pi / 180)

    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // 그림자
    ctx.setShadow(offset: CGSize(width: 0, height: -height * 0.06),
                  blur: height * 0.16,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55 * alpha))
    NSColor(calibratedRed: 1.0, green: 0.83, blue: 0.25, alpha: alpha).setFill()
    path.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // 상단 하이라이트 (라벨 입체감)
    let highlight = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.35 * alpha),
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
    ])!
    highlight.draw(in: path, angle: -90)

    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.1, green: 0.08, blue: 0.02, alpha: alpha),
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let strSize = str.size()
    // 시각적 수직 중앙: baseline을 -capHeight/2에 맞춘다
    // (draw(at:)의 y는 라인 하단 = baseline + descender)
    str.draw(at: NSPoint(x: -strSize.width / 2, y: -font.capHeight / 2 + font.descender))
    ctx.restoreGState()
}

// 배경의 작은 힌트 라벨들 (힌트 모드 분위기)
drawHintLabel("A", center: CGPoint(x: size * 0.255, y: size * 0.66), width: 150, height: 150,
              radius: 34, fontSize: 96, alpha: 0.34, rotation: -8)
drawHintLabel("K", center: CGPoint(x: size * 0.75, y: size * 0.30), width: 150, height: 150,
              radius: 34, fontSize: 96, alpha: 0.34, rotation: 7)

// 중앙 메인 라벨
drawHintLabel("S", center: CGPoint(x: size * 0.5, y: size * 0.47), width: 380, height: 380,
              radius: 86, fontSize: 252, alpha: 1.0)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode 실패") }

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("생성: \(out) (\(Int(size))×\(Int(size)))")
