// Render the README's looping canopy motion from the original app artwork.
// Usage: swift scripts/render-readme-tree.swift docs/assets/GoldenGinkgo.png work/readme-tree
// Encode the frames at 16 fps using ffmpeg's palettegen/paletteuse GIF filters.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Provide an artwork PNG and a frame output directory.")
}
let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let edge = 320, frameCount = 192, columns = 12, rows = 18
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func bitmap() -> CGContext {
    CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8,
              bytesPerRow: edge * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
let bounds = CGRect(x: 0, y: 0, width: edge, height: edge)
let reduced = bitmap()
reduced.interpolationQuality = .high
// Match the original logo's breathing room using the transparent tree cutout.
reduced.draw(original, in: bounds.insetBy(dx: CGFloat(edge) * 0.15, dy: CGFloat(edge) * 0.15))
let artwork = reduced.makeImage()!

func vertex(_ column: Int, _ row: Int, phase: Double) -> CGPoint {
    let x = Double(column) / Double(columns), y = Double(row) / Double(rows)
    let canopy = min(1, max(0, (y - 0.31) / 0.69)), bend = canopy * canopy
    // The same root-anchored bend and canopy ripple as TreeWindDynamics,
    // with harmonics chosen to meet seamlessly at the end of the GIF.
    let edgeFade = min(1, min(x, 1 - x) * 8) * min(1, (1 - y) * 8)
    let dx = (sin(phase) * 0.014 * bend
              + sin(phase * 2 + x * 7 + y * 4) * 0.0035 * canopy) * edgeFade
    let dy = sin(phase + x * 6) * 0.0025 * bend * edgeFade
    return CGPoint(x: (x + dx) * Double(edge), y: (y + dy) * Double(edge))
}

func paintTriangle(_ context: CGContext, source: [CGPoint], destination: [CGPoint]) {
    let ux = source[1].x - source[0].x, uy = source[1].y - source[0].y
    let vx = source[2].x - source[0].x, vy = source[2].y - source[0].y
    let determinant = ux * vy - uy * vx
    let du = CGPoint(x: destination[1].x - destination[0].x, y: destination[1].y - destination[0].y)
    let dv = CGPoint(x: destination[2].x - destination[0].x, y: destination[2].y - destination[0].y)
    let a = (du.x * vy - dv.x * uy) / determinant
    let b = (du.y * vy - dv.y * uy) / determinant
    let c = (dv.x * ux - du.x * vx) / determinant
    let d = (dv.y * ux - du.y * vx) / determinant
    let path = CGMutablePath()
    path.addLines(between: destination); path.closeSubpath()
    context.saveGState()
    context.setShouldAntialias(false)
    context.addPath(path); context.clip()
    context.concatenate(CGAffineTransform(a: a, b: b, c: c, d: d,
        tx: destination[0].x - a * source[0].x - c * source[0].y,
        ty: destination[0].y - b * source[0].x - d * source[0].y))
    context.draw(artwork, in: bounds)
    context.restoreGState()
}

for frame in 0..<frameCount {
    autoreleasepool {
        let phase = Double(frame) / Double(frameCount) * 2 * .pi
        let context = bitmap()
        context.interpolationQuality = .high
        for row in 0..<rows {
            for column in 0..<columns {
                let grid = [(column, row), (column + 1, row), (column + 1, row + 1), (column, row + 1)]
                let source = grid.map { CGPoint(x: Double($0.0) / Double(columns) * Double(edge),
                                               y: Double($0.1) / Double(rows) * Double(edge)) }
                let destination = grid.map { vertex($0.0, $0.1, phase: phase) }
                for indices in [[0, 1, 2], [0, 2, 3]] {
                    paintTriangle(context, source: indices.map {source[$0]}, destination: indices.map {destination[$0]})
                }
            }
        }
        // Small ginkgo fans drift around the canopy, like the app's ambient leaves.
        for leaf in 0..<4 {
            let offset = Double(leaf) * 2.399963
            let angle = phase + offset
            let x = (0.5 + cos(angle) * (0.27 + Double(leaf % 2) * 0.035)) * Double(edge)
            let y = (0.59 + sin(angle) * 0.22) * Double(edge)
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.rotate(by: angle * 2 + offset)
            context.scaleBy(x: 0.65 + abs(cos(phase * 2 + offset)) * 0.35, y: 1)
            context.setFillColor(CGColor(srgbRed: 0.90, green: 0.62, blue: 0.08, alpha: 0.65))
            let fan = CGMutablePath()
            fan.move(to: CGPoint(x: 0, y: -2))
            fan.addCurve(to: CGPoint(x: -2.6, y: 1.7), control1: CGPoint(x: -1.2, y: -1), control2: CGPoint(x: -3.4, y: 0.5))
            fan.addQuadCurve(to: CGPoint(x: -0.3, y: 2.8), control: CGPoint(x: -2.1, y: 3.3))
            fan.addLine(to: CGPoint(x: 0, y: 1.7))
            fan.addLine(to: CGPoint(x: 0.3, y: 2.8))
            fan.addQuadCurve(to: CGPoint(x: 2.6, y: 1.7), control: CGPoint(x: 2.1, y: 3.3))
            fan.addCurve(to: CGPoint(x: 0, y: -2), control1: CGPoint(x: 3.4, y: 0.5), control2: CGPoint(x: 1.2, y: -1))
            context.addPath(fan); context.fillPath()
            context.restoreGState()
        }
        let url = directory.appendingPathComponent(String(format: "%04d.png", frame))
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(output), "Failed to save frame")
    }
}
print("Rendered \(frameCount) frames at \(edge) × \(edge). Encode at 16 fps for a 12-second loop.")
