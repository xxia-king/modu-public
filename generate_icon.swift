import SwiftUI
import AppKit

@main
struct IconMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = IconDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class IconDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        generateAppIcon()
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
struct IconGenerator: View {
    var body: some View {
        ZStack {
            // 深墨底座
            RoundedRectangle(cornerRadius: 224)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.13, blue: 0.15),
                            Color(red: 0.10, green: 0.09, blue: 0.13),
                            Color(red: 0.03, green: 0.04, blue: 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 224)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color(red: 0.89, green: 0.24, blue: 0.16).opacity(0.22),
                                    Color.black.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 5
                        )
                )
            
            // 背景墨痕
            Text("墨")
                .font(.system(size: 520, weight: .black, design: .serif))
                .foregroundStyle(Color.white.opacity(0.08))
                .rotationEffect(.degrees(-9))
                .offset(x: 30, y: -45)
            
            ZStack {
                RoundedRectangle(cornerRadius: 46)
                    .fill(Color(red: 0.62, green: 0.69, blue: 0.66).opacity(0.34))
                    .frame(width: 500, height: 620)
                    .rotationEffect(.degrees(8))
                    .offset(x: 48, y: 30)
                
                RoundedRectangle(cornerRadius: 48)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.94, blue: 0.84),
                                Color(red: 0.91, green: 0.84, blue: 0.70)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 500, height: 620)
                    .shadow(color: .black.opacity(0.42), radius: 30, x: 0, y: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 48)
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    )
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.81, green: 0.18, blue: 0.12))
                    .frame(width: 46, height: 650)
                    .offset(x: -195, y: -5)
                
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text("#")
                            .font(.system(size: 84, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.81, green: 0.18, blue: 0.12))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.72))
                                .frame(width: 260, height: 18)
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.36))
                                .frame(width: 185, height: 14)
                        }
                    }
                    
                    Text("读")
                        .font(.system(size: 210, weight: .heavy, design: .serif))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.10, blue: 0.11),
                                    Color(red: 0.17, green: 0.23, blue: 0.21)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: -12)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach([300.0, 250.0, 285.0], id: \.self) { width in
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.26))
                                .frame(width: width, height: 13)
                        }
                    }
                    
                    HStack(spacing: 18) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(red: 0.81, green: 0.18, blue: 0.12))
                            .frame(width: 10, height: 64)
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.24))
                                .frame(width: 240, height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.18, green: 0.23, blue: 0.22).opacity(0.18))
                                .frame(width: 180, height: 12)
                        }
                    }
                }
                .padding(.leading, 92)
                .padding(.trailing, 58)
                .padding(.vertical, 70)
            }
            .rotationEffect(.degrees(-5))
            .offset(x: 10, y: 28)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func generateAppIcon() {
    let view = IconGenerator()
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0
    
    guard let nsImage = renderer.nsImage else {
        print("❌ 无法生成图片")
        return
    }
    
    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ 无法转换 PNG")
        return
    }
    
    let outputPath = FileManager.default.currentDirectoryPath + "/icon.png"
    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("✅ 图标已保存到: \(outputPath)")
        print("   尺寸: 2048x2048")
    } catch {
        print("❌ 写入失败: \(error)")
    }
}
