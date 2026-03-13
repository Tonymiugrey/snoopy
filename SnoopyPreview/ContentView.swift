//
//  ContentView.swift
//  SnoopyPreview
//
//  Created by miuGrey on 2025/5/5.
//

import SwiftUI
import AppKit

// MARK: - Data Models

struct WeatherOption: Identifiable {
    let id: String            // palette family
    let label: String
    let icon: String
    let code: String          // representative WWO code

    /// WeatherManager 枚举路由结果
    var condition: String {
        let c = Int(code) ?? 0
        switch c {
        case 113: return "sunny"
        case 200, 386, 389,
             176, 263, 266, 293, 296, 299, 302, 305, 308, 353, 356, 359: return "rainy"
        default: return "cloudy"
        }
    }
}

struct TimeOption: Identifiable {
    let id: String            // "day" / "evening" / "latenight"
    let label: String
    let icon: String
}

// MARK: - NSViewRepresentable Wrapper

struct SnoopyScreenSaverViewWrapper: NSViewRepresentable {
    @Binding var manualWeatherCode: String?
    @Binding var manualTimeOfDay: String?

    func makeNSView(context: Context) -> SnoopyScreenSaverView {
        let frame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let screensaverView = SnoopyScreenSaverView(frame: frame, isPreview: false)
        screensaverView?.startAnimation()
        return screensaverView ?? SnoopyScreenSaverView()
    }

    func updateNSView(_ nsView: SnoopyScreenSaverView, context: Context) {
        if let code = manualWeatherCode {
            nsView.setManualWeather(code)
        } else {
            nsView.resetManualWeather()
        }
        nsView.setManualTimeOfDay(manualTimeOfDay)
    }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var manualWeatherCode: String?
    @State private var manualTimeOfDay: String?

    // 所有调色板天气族，每族取一个代表 code
    private let weatherOptions: [WeatherOption] = [
        WeatherOption(id: "sunny",   label: "晴",    icon: "☀️",  code: "113"),  // → .sunny
        WeatherOption(id: "cloudy",  label: "多云",   icon: "⛅",  code: "116"),  // → .cloudy
        WeatherOption(id: "windy",   label: "有风",   icon: "🌬️", code: "119"),  // → .cloudy
        WeatherOption(id: "foggy",   label: "雾/霾",  icon: "🌫️", code: "143"),  // → .cloudy
        WeatherOption(id: "rainy",   label: "雨",    icon: "🌧️", code: "308"),  // → .rainy
        WeatherOption(id: "stormy",  label: "雷暴",   icon: "⛈️", code: "200"),  // → .rainy
        WeatherOption(id: "snowy",   label: "雪",    icon: "❄️",  code: "227"),  // → .cloudy
        WeatherOption(id: "icy",     label: "冻雨/冰", icon: "🧊", code: "179"),  // → .cloudy
    ]

    private let timeOptions: [TimeOption] = [
        TimeOption(id: "day",       label: "白天",  icon: "🌤️"),   // 06:00–18:00
        TimeOption(id: "evening",   label: "傍晚",  icon: "🌆"),   // 18:00–22:00
        TimeOption(id: "latenight", label: "深夜",  icon: "🌃"),   // 22:00–06:00
    ]

    // 当前 WeatherManager 路由状态
    private var currentCondition: String {
        guard let code = manualWeatherCode else { return "auto" }
        return weatherOptions.first(where: { $0.code == code })?.condition ?? "cloudy"
    }

    private var conditionLabel: String {
        switch currentCondition {
        case "sunny":  return ".sunny"
        case "rainy":  return ".rainy"
        case "cloudy": return ".cloudy"
        default:       return "auto (API)"
        }
    }

    private var conditionColor: Color {
        switch currentCondition {
        case "sunny":  return .yellow
        case "rainy":  return .blue
        case "cloudy": return Color(red: 0.6, green: 0.8, blue: 1.0)
        default:       return .white.opacity(0.5)
        }
    }

    private var timeLabel: String {
        switch manualTimeOfDay {
        case "day":       return "day  (06–18)"
        case "evening":   return "evening  (18–22)"
        case "latenight": return "latenight  (22–06)"
        default:          return "auto (系统时间)"
        }
    }

    var body: some View {
        ZStack {
            SnoopyScreenSaverViewWrapper(
                manualWeatherCode: $manualWeatherCode,
                manualTimeOfDay:   $manualTimeOfDay
            )
            .edgesIgnoringSafeArea(.all)

            VStack {
                Spacer()
                VStack(spacing: 10) {

                    // ── 状态栏 ──────────────────────────────────
                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Text("天气状态")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                            Text(conditionLabel)
                                .foregroundColor(conditionColor)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                            if let code = manualWeatherCode {
                                Text("code \(code)")
                                    .foregroundColor(.white.opacity(0.45))
                                    .font(.system(size: 10, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.25))
                            .frame(width: 1, height: 14)
                        HStack(spacing: 5) {
                            Text("时段")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.system(size: 11))
                            Text(timeLabel)
                                .foregroundColor(.white)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                    }

                    Divider().background(Color.white.opacity(0.2))

                    // ── 时段控制 ────────────────────────────────
                    HStack(spacing: 8) {
                        controlButton(label: "自动", icon: "🕐",
                                      isSelected: manualTimeOfDay == nil, color: .gray) {
                            manualTimeOfDay = nil
                        }
                        ForEach(timeOptions) { opt in
                            controlButton(label: opt.label, icon: opt.icon,
                                          isSelected: manualTimeOfDay == opt.id, color: .purple) {
                                manualTimeOfDay = opt.id
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.2))

                    // ── 天气控制 ────────────────────────────────
                    HStack(spacing: 6) {
                        controlButton(label: "自动", icon: "🌐",
                                      isSelected: manualWeatherCode == nil, color: .gray) {
                            manualWeatherCode = nil
                        }
                        ForEach(weatherOptions) { opt in
                            controlButton(label: opt.label, icon: opt.icon,
                                          isSelected: manualWeatherCode == opt.code,
                                          color: colorForCondition(opt.condition)) {
                                manualWeatherCode = opt.code
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .padding(.bottom, 24)
            }
        }
    }

    private func colorForCondition(_ condition: String) -> Color {
        switch condition {
        case "sunny": return .orange
        case "rainy": return .blue
        default:      return .teal
        }
    }

    @ViewBuilder
    private func controlButton(
        label: String, icon: String,
        isSelected: Bool, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .frame(minWidth: 44)
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .background(isSelected ? color.opacity(0.85) : Color.white.opacity(0.08))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ContentView()
}

