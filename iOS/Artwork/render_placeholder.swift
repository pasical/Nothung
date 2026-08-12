import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let arguments = Array(CommandLine.arguments.dropFirst())
let monochrome = arguments.contains("--monochrome")
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: monochrome
        ? CGImageAlphaInfo.premultipliedLast.rawValue
        : CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Could not create icon context")
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xff) / 255,
            CGFloat((hex >> 8) & 0xff) / 255,
            CGFloat(hex & 0xff) / 255,
            1,
        ]
    )!
}

func polygon(_ points: [CGPoint], fill: CGColor) {
    guard let first = points.first else { return }
    context.beginPath()
    context.move(to: first)
    for point in points.dropFirst() {
        context.addLine(to: point)
    }
    context.closePath()
    context.setFillColor(fill)
    context.fillPath()
}

// Work in the SVG's top-left coordinate system.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)
context.translateBy(x: CGFloat(size), y: CGFloat(size))
context.rotate(by: .pi)

let forgeInk = color(0x141923)
let steel = color(monochrome ? 0x000000 : 0xF4F5FA)
let temperBlue = color(monochrome ? 0x000000 : 0x5267D8)

if monochrome {
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
} else {
    context.setFillColor(forgeInk)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
}

polygon(
    [
        CGPoint(x: 512, y: 104),
        CGPoint(x: 632, y: 214),
        CGPoint(x: 584, y: 454),
        CGPoint(x: 440, y: 454),
        CGPoint(x: 392, y: 214),
    ],
    fill: steel
)

polygon(
    [
        CGPoint(x: 440, y: 570),
        CGPoint(x: 584, y: 570),
        CGPoint(x: 608, y: 692),
        CGPoint(x: 416, y: 692),
    ],
    fill: steel
)

context.setFillColor(steel)
context.addPath(CGPath(roundedRect: CGRect(x: 236, y: 680, width: 552, height: 74), cornerWidth: 37, cornerHeight: 37, transform: nil))
context.fillPath()
context.addPath(CGPath(roundedRect: CGRect(x: 480, y: 728, width: 64, height: 180), cornerWidth: 32, cornerHeight: 32, transform: nil))
context.fillPath()
context.fillEllipse(in: CGRect(x: 440, y: 834, width: 144, height: 144))

context.saveGState()
context.translateBy(x: 512, y: 512)
context.rotate(by: .pi / 4)
context.setFillColor(temperBlue)
context.addPath(CGPath(roundedRect: CGRect(x: -67, y: -67, width: 134, height: 134), cornerWidth: 20, cornerHeight: 20, transform: nil))
context.fillPath()
context.restoreGState()

guard let image = context.makeImage() else {
    fatalError("Could not create icon image")
}

let destinationPath = arguments.first(where: { !$0.hasPrefix("--") })
    ?? "../NothungApp/Assets.xcassets/AppIcon.appiconset/NothungPlaceholder.png"
let destinationURL = URL(fileURLWithPath: destinationPath)
guard let destination = CGImageDestinationCreateWithURL(
    destinationURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fatalError("Could not create PNG destination")
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not write placeholder icon")
}
