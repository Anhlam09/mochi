import SwiftUI
import AppKit
import MochiUI

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "poses", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

@MainActor func render<V: View>(_ view: V, name: String, dark: Bool, padding: CGFloat = 0) {
    let bg = dark ? Color(red: 0x1E / 255, green: 0x1A / 255, blue: 0x24 / 255) : Color(red: 0xF7 / 255, green: 0xF3 / 255, blue: 0xEE / 255)
    let framed = view
        .padding(padding)
        .background(bg)
        .environment(\.colorScheme, dark ? .dark : .light)
    let r = ImageRenderer(content: framed)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("FAILED \(name)"); return
    }
    try? png.write(to: outDir.appendingPathComponent(name + ".png"))
}

@MainActor func run() {
    let times: [Double] = [0, 0.5, 1.3, 2.0, 3.0]
    for dark in [false, true] {
        let mode = dark ? "dark" : "light"
        for pose in MascotPose.allCases {
            for t in times {
                render(MascotFigure(pose: pose, t: t), name: "\(pose.rawValue)_t\(t)_\(mode)", dark: dark, padding: 8)
            }
            render(MascotFigure(pose: pose, t: 0.5, hover: true), name: "\(pose.rawValue)_hover_\(mode)", dark: dark, padding: 8)
            render(MascotFigure(pose: pose, t: 0.5, squish: 1), name: "\(pose.rawValue)_squish_\(mode)", dark: dark, padding: 8)
        }
        render(MascotScene(pose: .breakDue, progress: 0.7, bubbleText: "Time to stretch! 🌱", t: 0.3), name: "scene_breakDue_\(mode)", dark: dark)
        render(MascotScene(pose: .working, progress: 0.4, bubbleText: nil, t: 0.3), name: "scene_working_\(mode)", dark: dark)

        // Contact sheet: one row per pose, columns = 4 time samples.
        let sheet = VStack(spacing: 0) {
            ForEach(MascotPose.allCases, id: \.self) { pose in
                HStack(spacing: 0) {
                    ForEach(Array(times.enumerated()), id: \.offset) { _, t in
                        MascotFigure(pose: pose, t: t)
                    }
                    MascotFigure(pose: pose, t: 0.5, hover: true)
                    MascotFigure(pose: pose, t: 0.5, squish: 1)
                    Text(pose.rawValue).font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.text).frame(width: 110)
                }
            }
        }.padding(12)
        render(sheet, name: "contact_sheet_\(mode)", dark: dark)

        if !dark {
            let sizes = HStack(alignment: .bottom, spacing: 24) {
                ForEach(MascotSize.allCases, id: \.self) { sz in
                    MascotScene(pose: .breakDue, progress: 0.7, bubbleText: "Time to stretch! 🌱", t: 0.3, size: sz)
                        .border(Color.gray.opacity(0.35))
                }
            }.padding(16)
            render(sizes, name: "sizes_light", dark: false)
        }

        if !dark {
            let tips = ["Look out the window for 20 seconds — let your eyes wander far away 🌤️",
                        "3 slow breaths: in through the nose, out through the mouth."]
            for (i, tip) in tips.enumerated() {
                let longSizes = HStack(alignment: .bottom, spacing: 24) {
                    ForEach(MascotSize.allCases, id: \.self) { sz in
                        MascotScene(pose: .breakDue, progress: 0.7, bubbleText: tip, t: 0.3, size: sz)
                            .border(Color.gray.opacity(0.35))
                    }
                }.padding(16)
                render(longSizes, name: i == 0 ? "sizes_long" : "sizes_long2", dark: false)
            }
        }

        // Scenes sheet: full compositions for every pose.
        let scenes = HStack(spacing: 0) {
            ForEach(MascotPose.allCases, id: \.self) { pose in
                MascotScene(pose: pose, progress: 0.6, bubbleText: pose == .breakDue ? "Time to stretch! 🌱" : nil, t: 0.6)
            }
        }
        render(scenes, name: "scenes_\(mode)", dark: dark)
    }
    print("Wrote PNGs to \(outDir.path)")
}

MainActor.assumeIsolated { run() }
