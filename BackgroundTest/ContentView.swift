//
//  ContentView.swift
//  BackgroundTest
//
//  Created by miuGrey on 2025/6/22.
//

import AVFoundation
import SpriteKit
import SwiftUI

struct ContentView: View {
    // MARK: - State Properties
    @State private var isAutoMode = true
    @State private var manualWeatherInput = ""
    @State private var selectedTimeOfDay = "day"
    @State private var currentPalette: ColorPalette?
    @State private var statusMessage = "准备就绪"

    // MARK: - Managers
    @State private var colorPaletteManager = ColorPaletteManager()
    @State private var weatherManager = WeatherManager()
    @State private var sceneManager: SceneManager?

    // MARK: - Constants
    private let timeOptions = [
        "day": "白天",
        "evening": "傍晚",
        "latenight": "深夜",
    ]

    var body: some View {
        ZStack {
            // SpriteKit场景 - 与主程序一致
            if let skView = sceneManager?.skView {
                SpriteKitViewRepresentable(skView: skView)
                    .ignoresSafeArea()
            }

            // 控制面板
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 16) {
                    // 标题
                    Text("背景配色测试")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(radius: 2)

                    // 状态显示
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前状态")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(statusMessage)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(8)

                        if let palette = currentPalette {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    "背景色: RGB(\(Int(palette.backgroundColor.redComponent * 255)), \(Int(palette.backgroundColor.greenComponent * 255)), \(Int(palette.backgroundColor.blueComponent * 255)))"
                                )
                                Text(
                                    "叠加色: RGB(\(Int(palette.overlayColor.redComponent * 255)), \(Int(palette.overlayColor.greenComponent * 255)), \(Int(palette.overlayColor.blueComponent * 255)))"
                                )
                                Text(
                                    "透明度: \(String(format: "%.1f", palette.overlayColor.alphaComponent))"
                                )
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(6)
                        }
                    }

                    // 模式切换
                    VStack(spacing: 12) {
                        Text("模式选择")
                            .font(.headline)
                            .foregroundColor(.white)

                        Picker("模式", selection: $isAutoMode) {
                            Text("自动模式").tag(true)
                            Text("手动模式").tag(false)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // 手动模式控件
                    if !isAutoMode {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("天气输入")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                TextField("输入天气描述 (如: 晴天、雨、雪等)", text: $manualWeatherInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("时间段")
                                    .font(.subheadline)
                                    .foregroundColor(.white)

                                Picker("时间段", selection: $selectedTimeOfDay) {
                                    ForEach(Array(timeOptions.keys), id: \.self) { key in
                                        Text(timeOptions[key] ?? key).tag(key)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(12)
                    }

                    // 确认按钮
                    Button(action: generateBackground) {
                        Text(isAutoMode ? "自动生成背景" : "应用设置")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color.black.opacity(0.4))
                .cornerRadius(16)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .onAppear {
            setupScene()
            initializeBackground()
            // 启动天气更新
            weatherManager.startWeatherUpdate()
        }
    }

    // MARK: - Helper Methods
    private func setupScene() {
        // 获取屏幕尺寸
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
        let bounds = NSRect(origin: .zero, size: screenSize)

        // 创建SceneManager实例，直接使用主程序的SceneManager
        sceneManager = SceneManager(bounds: bounds, weatherManager: weatherManager)

        // 创建虚拟的播放器（因为我们只需要背景层）
        let dummyPlayer = AVQueuePlayer()
        let dummyOverlayPlayer = AVQueuePlayer()
        let dummyAsPlayer = AVPlayer()

        // 设置场景（只使用背景相关的层）
        sceneManager?.setupScene(
            mainPlayer: dummyPlayer, overlayPlayer: dummyOverlayPlayer, asPlayer: dummyAsPlayer)

        debugLog("✅ SpriteKit场景设置完成")
    }

    private func initializeBackground() {
        statusMessage = "初始化背景..."
        generateBackground()
    }

    private func generateBackground() {
        statusMessage = "生成背景中..."

        let weatherString: String?

        if isAutoMode {
            // 自动模式：从WeatherManager获取天气
            weatherString = colorPaletteManager.getWeatherString(from: weatherManager)
            statusMessage = "自动模式 - 天气: \(weatherString ?? "无法获取")"
        } else {
            // 手动模式：使用用户输入
            weatherString = manualWeatherInput.isEmpty ? nil : manualWeatherInput
            statusMessage =
                "手动模式 - 天气: \(weatherString ?? "未输入"), 时间: \(timeOptions[selectedTimeOfDay] ?? selectedTimeOfDay)"
        }

        // 获取调色板
        let palette: ColorPalette?

        if isAutoMode {
            palette = colorPaletteManager.getColorPalette(for: weatherString)
        } else {
            // 手动模式：创建临时管理器来处理手动时间设置
            palette = getManualColorPalette(
                weatherString: weatherString, timeOfDay: selectedTimeOfDay)
        }

        guard let selectedPalette = palette else {
            statusMessage = "❌ 无法获取调色板"
            return
        }

        // 应用颜色到SpriteKit场景
        applyPaletteToScene(selectedPalette)

        // 更新状态
        withAnimation(.easeInOut(duration: 0.5)) {
            self.currentPalette = selectedPalette
            statusMessage = "✅ 背景已更新"
            debugLog(
                "🎨 背景已更新 - 天气: \(weatherString ?? "无"), 背景色: \(selectedPalette.backgroundColor), 叠加色: \(selectedPalette.overlayColor)"
            )
        }
    }

    private func applyPaletteToScene(_ palette: ColorPalette) {
        guard let sceneManager = sceneManager else { return }

        // 直接设置背景色节点
        if let bgNode = sceneManager.backgroundColorNode {
            bgNode.color = NSColor(
                red: palette.backgroundColor.redComponent,
                green: palette.backgroundColor.greenComponent,
                blue: palette.backgroundColor.blueComponent,
                alpha: 1.0
            )
            bgNode.alpha = 1
        }

        // 直接设置halftone节点的颜色和透明度
        if let halftoneNode = sceneManager.halftoneNode {
            halftoneNode.color = palette.overlayColor
            halftoneNode.colorBlendFactor = 1  // 完全应用颜色混合
            halftoneNode.blendMode = .alpha
            halftoneNode.alpha = 1
        }

        debugLog("🎨 已应用调色板到SpriteKit场景")
    }

    private func getManualColorPalette(weatherString: String?, timeOfDay: String) -> ColorPalette? {
        // 直接使用主程序的ColorPaletteManager，但需要手动设置时间
        return ManualColorPaletteHelper.getColorPalette(
            for: weatherString,
            timeOfDay: timeOfDay,
            using: colorPaletteManager
        )
    }
}

// MARK: - SpriteKit View Representable
struct SpriteKitViewRepresentable: NSViewRepresentable {
    let skView: SKView

    func makeNSView(context: Context) -> SKView {
        return skView
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        // 不需要更新
    }
}

// MARK: - Manual Color Palette Helper
struct ManualColorPaletteHelper {
    static func getColorPalette(
        for weatherString: String?, timeOfDay: String, using manager: ColorPaletteManager
    ) -> ColorPalette? {
        // 简化的匹配逻辑，直接加载和匹配调色板
        guard
            let plistPath = Bundle.main.path(forResource: "ColorPaletteConfig", ofType: "plist")
                ?? ("/Users/miugrey/Projects/snoopy/snoopy/ColorPaletteConfig.plist" as String?),
            let plistData = NSDictionary(contentsOfFile: plistPath),
            let palettesDict = plistData["colorPalettes"] as? [String: [String: Any]]
        else {
            debugLog("❌ ManualHelper: 无法加载 ColorPaletteConfig.plist")
            return nil
        }

        var colorPalettes: [ColorPalette] = []

        for (_, paletteInfo) in palettesDict {
            guard let weather = paletteInfo["weather"] as? [String],
                let paletteTimeOfDay = paletteInfo["timeOfDay"] as? String,
                let backgroundColorDict = paletteInfo["backgroundColor"] as? [String: Any],
                let overlayColorDict = paletteInfo["overlayColor"] as? [String: Any]
            else {
                continue
            }

            let backgroundColor = createColor(from: backgroundColorDict)
            let overlayColor = createColor(from: overlayColorDict)

            let palette = ColorPalette(
                weather: weather,
                timeOfDay: paletteTimeOfDay,
                backgroundColor: backgroundColor,
                overlayColor: overlayColor
            )

            colorPalettes.append(palette)
        }

        // 模糊匹配逻辑
        if let weather = weatherString, !weather.isEmpty {
            // 查找匹配天气和时间的调色板
            for palette in colorPalettes {
                if palette.timeOfDay == timeOfDay {
                    for weatherKeyword in palette.weather {
                        if weather.contains(weatherKeyword) {
                            debugLog(
                                "🎨 手动匹配到调色板 - 天气: \(weather) -> 关键词: \(weatherKeyword), 时间: \(timeOfDay)"
                            )
                            return palette
                        }
                    }
                }
            }

            // 尝试只匹配天气（任意时间）
            for palette in colorPalettes {
                for weatherKeyword in palette.weather {
                    if weather.contains(weatherKeyword) {
                        debugLog("🎨 手动部分匹配到调色板 - 天气: \(weather) -> 关键词: \(weatherKeyword)")
                        return palette
                    }
                }
            }
        }

        // 根据时间随机选择
        let matchingPalettes = colorPalettes.filter { $0.timeOfDay == timeOfDay }
        if let randomPalette = matchingPalettes.randomElement() {
            debugLog("🎨 手动随机选择调色板 - 时间: \(timeOfDay)")
            return randomPalette
        }

        return colorPalettes.randomElement()
    }

    private static func createColor(from dict: [String: Any]) -> NSColor {
        let red = (dict["red"] as? Int) ?? 0
        let green = (dict["green"] as? Int) ?? 0
        let blue = (dict["blue"] as? Int) ?? 0
        let alpha = (dict["alpha"] as? Double) ?? 1.0

        return NSColor(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: CGFloat(alpha)
        )
    }
}

#Preview {
    ContentView()
}
