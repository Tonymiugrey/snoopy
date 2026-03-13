import Foundation

class WeatherManager {
    private var currentWeather: WeatherCondition = .cloudy
    private var weatherAPIAvailable: Bool = false
    private var rawWeatherString: String?  // 存储 wttr.in weatherCode 字符串用于调色板匹配

    private var isManualOverride: Bool = false
    private var manualTimeOfDay: String? = nil

    init() {
        updateWeatherFromAPI()
    }

    func setManualWeatherCode(_ weatherCode: String) {
        isManualOverride = true
        DispatchQueue.main.async {
            self.updateWeatherCondition(from: weatherCode)
        }
    }

    func resetManualWeather() {
        isManualOverride = false
        updateWeatherFromAPI()
    }

    func setManualTimeOfDay(_ timeOfDay: String?) {
        manualTimeOfDay = timeOfDay
    }

    func getCurrentTimeOfDay() -> String {
        if let override = manualTimeOfDay { return override }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<18: return "day"
        case 18..<22: return "evening"
        case 22...23, 0..<6: return "latenight"
        default: return "day"
        }
    }

    func updateWeatherFromAPI() {
        if isManualOverride { return }
        debugLog("🌐 开始从 wttr.in 获取天气信息...")

        guard let url = URL(string: "https://wttr.in/?format=j2") else {
            debugLog("❌ wttr.in URL 构建失败")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            guard let data = data, error == nil else {
                let errorMessage = error?.localizedDescription ?? "未知错误"
                debugLog("❌ wttr.in 天气请求失败: \(errorMessage)")
                DispatchQueue.main.async { self.weatherAPIAvailable = false }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let conditions = json["current_condition"] as? [[String: Any]],
                    let first = conditions.first,
                    let weatherCode = first["weatherCode"] as? String
                {
                    DispatchQueue.main.async {
                        debugLog("🌤️ wttr.in weatherCode: \(weatherCode)")
                        self.updateWeatherCondition(from: weatherCode)
                    }
                } else {
                    debugLog("❌ wttr.in 天气数据解析失败")
                    DispatchQueue.main.async { self.weatherAPIAvailable = false }
                }
            } catch {
                debugLog("❌ wttr.in JSON 解析失败: \(error.localizedDescription)")
                DispatchQueue.main.async { self.weatherAPIAvailable = false }
            }
        }

        task.resume()
    }

    private func updateWeatherCondition(from weatherCode: String) {
        // 存储 weatherCode 字符串，供调色板管理器按 code 匹配
        self.rawWeatherString = weatherCode

        let newWeather: WeatherCondition
        let code = Int(weatherCode) ?? 0

        switch code {
        case 113:  // 晴天
            newWeather = .sunny
        case 200, 386, 389,  // 雷阵雨 / 雷暴
            176, 263, 266, 293, 296, 299, 302, 305,  // 小雨 / 阵雨 / 大雨
            308, 353, 356, 359:  // 大暴雨
            newWeather = .rainy
        default:
            newWeather = .cloudy
        }

        if newWeather != currentWeather {
            currentWeather = newWeather
            debugLog("🌤️ 天气状态更新为: \(newWeather) (code: \(weatherCode))")
        }

        weatherAPIAvailable = true
        debugLog("✅ 天气API标记为可用")
    }

    func getCurrentWeather() -> WeatherCondition {
        return currentWeather
    }

    func getCurrentAdcode() -> String? {
        return nil
    }

    func isAPIAvailable() -> Bool {
        return weatherAPIAvailable
    }

    func getRawWeatherString() -> String? {
        return rawWeatherString
    }

    func startWeatherUpdate() {
        updateWeatherFromAPI()
    }
}
