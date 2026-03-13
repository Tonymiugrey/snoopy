//
//  ColorPaletteManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import AppKit
import Foundation

struct ColorPalette {
    let weather: [String]
    let timeOfDay: String
    let backgroundColor: NSColor
    let overlayColor: NSColor
}

class ColorPaletteManager {
    private var weatherColorPalettes: [String: ColorPalette] = [:]
    private var genericColorPalettes: [String: ColorPalette] = [:]

    init() {
        loadColorPalettes()
    }

    private func loadColorPalettes() {
        guard
            let plistPath = Bundle(for: type(of: self)).path(
                forResource: "ColorPaletteConfig", ofType: "plist"),
            let plistData = NSDictionary(contentsOfFile: plistPath)
        else {
            debugLog("❌ 无法加载 ColorPaletteConfig.plist")
            return
        }

        if let palettesDict = plistData["weatherColorPalettes"] as? [String: [String: Any]] {
            for (key, paletteInfo) in palettesDict {
                guard
                    let timeOfDay = paletteInfo["timeOfDay"] as? String,
                    let backgroundColorDict = paletteInfo["backgroundColor"] as? [String: Any],
                    let overlayColorDict = paletteInfo["overlayColor"] as? [String: Any]
                else {
                    debugLog("⚠️ 跳过格式错误的天气调色板配置: \(key)")
                    continue
                }
                let weather = paletteInfo["weather"] as? [String] ?? []
                weatherColorPalettes[key] = ColorPalette(
                    weather: weather,
                    timeOfDay: timeOfDay,
                    backgroundColor: createColor(from: backgroundColorDict),
                    overlayColor: createColor(from: overlayColorDict)
                )
            }
        }

        if let palettesDict = plistData["genericColorPalettes"] as? [String: [String: Any]] {
            for (key, paletteInfo) in palettesDict {
                guard
                    let timeOfDay = paletteInfo["timeOfDay"] as? String,
                    let backgroundColorDict = paletteInfo["backgroundColor"] as? [String: Any],
                    let overlayColorDict = paletteInfo["overlayColor"] as? [String: Any]
                else {
                    debugLog("⚠️ 跳过格式错误的常规调色板配置: \(key)")
                    continue
                }
                genericColorPalettes[key] = ColorPalette(
                    weather: [],
                    timeOfDay: timeOfDay,
                    backgroundColor: createColor(from: backgroundColorDict),
                    overlayColor: createColor(from: overlayColorDict)
                )
            }
        }

        debugLog("🎨 加载调色板: 天气 \(weatherColorPalettes.count) 个, 常规 \(genericColorPalettes.count) 个")
    }

    private func createColor(from dict: [String: Any]) -> NSColor {
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

    private func getCurrentTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 6..<18:
            return "day"
        case 18..<22:
            return "evening"
        case 22...23, 0..<6:
            return "latenight"
        default:
            return "day"
        }
    }

    private var weatherPickCount = 0
    private var genericPickCount = 0

    func getColorPalette(for weatherString: String?, timeOfDay: String? = nil) -> ColorPalette? {
        let currentTimeOfDay = timeOfDay ?? getCurrentTimeOfDay()
        let roll = Double.random(in: 0..<1)
        let useWeather = roll < 0.6

        if useWeather {
            weatherPickCount += 1
            debugLog(
                "🎲 随机选择天气调色板 (roll=\(String(format: "%.2f", roll))) [天气:\(weatherPickCount) 常规:\(genericPickCount)]"
            )
            return getWeatherPalette(for: weatherString, timeOfDay: currentTimeOfDay)
        } else {
            genericPickCount += 1
            debugLog(
                "🎲 随机选择常规调色板 (roll=\(String(format: "%.2f", roll))) [天气:\(weatherPickCount) 常规:\(genericPickCount)]"
            )
            return getGenericPalette(timeOfDay: currentTimeOfDay)
        }
    }

    private func getWeatherPalette(for weatherString: String?, timeOfDay: String) -> ColorPalette? {
        // 有天气 code → 精确匹配
        if let weather = weatherString, !weather.isEmpty {
            for (_, palette) in weatherColorPalettes {
                if palette.timeOfDay == timeOfDay {
                    if palette.weather.contains(weather) {
                        debugLog("🎨 天气调色板匹配 - code: \(weather), 时间: \(timeOfDay)")
                        return palette
                    }
                }
            }
            // 忽略时间再试一次
            for (_, palette) in weatherColorPalettes {
                if palette.weather.contains(weather) {
                    debugLog("🎨 天气调色板匹配 (忽略时间) - code: \(weather)")
                    return palette
                }
            }
            debugLog("⚠️ 未找到匹配天气 code: \(weather)，回退到时间随机")
        }

        // 天气获取失败 或 未匹配 → 按时间随机 (现有缺省逻辑)
        let matching = weatherColorPalettes.values.filter { $0.timeOfDay == timeOfDay }
        if let palette = matching.randomElement() {
            debugLog("🎨 天气调色板时间随机 - 时间: \(timeOfDay)")
            return palette
        }
        return weatherColorPalettes.values.randomElement()
    }

    private func getGenericPalette(timeOfDay: String) -> ColorPalette? {
        let matching = genericColorPalettes.values.filter { $0.timeOfDay == timeOfDay }
        if let palette = matching.randomElement() {
            debugLog("🎨 常规调色板时间随机 - 时间: \(timeOfDay)")
            return palette
        }
        return genericColorPalettes.values.randomElement()
    }

    // 获取原始天气信息进行模糊匹配
    func getWeatherString(from weatherManager: WeatherManager) -> String? {
        return weatherManager.getRawWeatherString()
    }
}
