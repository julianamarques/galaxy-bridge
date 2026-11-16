import AppKit
import SwiftUI

// O ícone do Galaxy Bridge: um Mac e um Galaxy ligados por uma ponte em arco.

private let deck: CGFloat = 530
private let screenGradient = LinearGradient(
    colors: [Color(red: 0.15, green: 0.22, blue: 0.5), Color(red: 0.5, green: 0.45, blue: 0.85)],
    startPoint: .top, endPoint: .bottom
)

struct Laptop: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.white)
                .frame(width: 300, height: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(screenGradient)
                        .padding(14)
                )
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 6)
                .fill(.white)
                .frame(width: 360, height: 28)
        }
    }
}

struct Phone: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 44, style: .continuous)
            .fill(.white)
            .frame(width: 170, height: 340)
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(screenGradient)
                    .padding(12)
            )
            .overlay(alignment: .top) { Circle().fill(.black).frame(width: 16).padding(.top, 26) }
    }
}

/// O arco da ponte, com os tirantes até o tabuleiro.
struct Bridge: View {
    let from: CGFloat
    let to: CGFloat
    let top: CGFloat

    var body: some View {
        let mid = (from + to) / 2
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: from, y: deck))
                path.addQuadCurve(to: CGPoint(x: to, y: deck), control: CGPoint(x: mid, y: 2 * top - deck))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 26, lineCap: .round))
            Path { path in
                for t in [0.25, 0.5, 0.75] {
                    let x = from + (to - from) * t
                    // Altura do arco nesse ponto (curva quadrática).
                    let y = (1 - t) * (1 - t) * deck + 2 * (1 - t) * t * (2 * top - deck) + t * t * deck
                    path.move(to: CGPoint(x: x, y: y + 6))
                    path.addLine(to: CGPoint(x: x, y: deck))
                }
                path.move(to: CGPoint(x: from, y: deck))
                path.addLine(to: CGPoint(x: to, y: deck))
            }
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        }
    }
}

struct Icon: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.8, blue: 0.85), Color(red: 0.1, green: 0.38, blue: 0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .offset(x: 100, y: 100)
            // A ponte passa por trás dos aparelhos, com as pontas escondidas atrás das telas.
            Bridge(from: 400, to: 760, top: 340)
            Laptop()
                .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                .offset(x: 140, y: 440)
            Phone()
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
                .offset(x: 690, y: 370)
        }
        .frame(width: 1024, height: 1024, alignment: .topLeading)
    }
}

let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    var rendered: [Int: Data] = [:]
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = size * scale
            if rendered[pixels] == nil {
                let renderer = ImageRenderer(content: Icon())
                renderer.scale = CGFloat(pixels) / 1024
                guard let image = renderer.cgImage else { fatalError("render failed") }
                rendered[pixels] = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            }
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try! rendered[pixels]!.write(to: iconset.appendingPathComponent(name))
        }
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print("Resources/AppIcon.icns")
