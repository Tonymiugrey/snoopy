import Foundation

class WeatherManager {
    static let weatherDidUpdateNotification = Notification.Name("com.snoopy.weather.didUpdate")
    static let apiWeatherCodeUserInfoKey = "apiWeatherCode"
    static let apiWeatherDescriptionUserInfoKey = "apiWeatherDescription"
    static let apiAvailableUserInfoKey = "apiAvailable"
    static let effectiveWeatherCodeUserInfoKey = "effectiveWeatherCode"
    static let manualOverrideUserInfoKey = "manualOverride"

    private var currentWeather: WeatherCondition = .cloudy
    private var weatherAPIAvailable: Bool = false
    private var rawWeatherString: String?  // 存储 wttr.in weatherCode 字符串用于调色板匹配
    private var apiWeatherCode: String?
    private var apiWeatherDescription: String?

    private var isManualOverride: Bool = false
    private var manualTimeOfDay: String? = nil

    init() {
        updateWeatherFromAPI()
    }

    func setManualWeatherCode(_ weatherCode: String) {
        isManualOverride = true
        DispatchQueue.main.async {
            self.updateWeatherCondition(from: weatherCode, marksAPIAvailable: false)
        }
    }

    func resetManualWeather() {
        isManualOverride = false

        if let apiWeatherCode {
            updateWeatherCondition(from: apiWeatherCode, marksAPIAvailable: weatherAPIAvailable)
        } else {
            postWeatherUpdate()
        }

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
                DispatchQueue.main.async {
                    self.weatherAPIAvailable = false
                    self.postWeatherUpdate()
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let payload = (json["data"] as? [String: Any]) ?? json

                    if let conditions = payload["current_condition"] as? [[String: Any]],
                        let first = conditions.first,
                        let weatherCodeValue = first["weatherCode"]
                    {
                        let weatherCode: String?
                        if let value = weatherCodeValue as? String {
                            weatherCode = value
                        } else if let value = weatherCodeValue as? NSNumber {
                            weatherCode = value.stringValue
                        } else {
                            weatherCode = nil
                        }

                        let weatherDescription =
                            (first["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String

                        if let weatherCode {
                            DispatchQueue.main.async {
                                self.apiWeatherCode = weatherCode
                                self.apiWeatherDescription = weatherDescription
                                self.weatherAPIAvailable = true

                                debugLog("🌤️ wttr.in weatherCode: \(weatherCode)")
                                if self.isManualOverride {
                                    self.postWeatherUpdate()
                                } else {
                                    self.updateWeatherCondition(
                                        from: weatherCode,
                                        marksAPIAvailable: true
                                    )
                                }
                            }
                            return
                        }
                    }

                    let topLevelKeys = json.keys.sorted().joined(separator: ", ")
                    let payloadKeys = payload.keys.sorted().joined(separator: ", ")
                    debugLog(
                        "❌ wttr.in 天气数据解析失败，top-level keys: [\(topLevelKeys)]，payload keys: [\(payloadKeys)]"
                    )
                    DispatchQueue.main.async {
                        self.weatherAPIAvailable = false
                        self.postWeatherUpdate()
                    }
                }
            } catch {
                debugLog("❌ wttr.in JSON 解析失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.weatherAPIAvailable = false
                    self.postWeatherUpdate()
                }
            }
        }

        task.resume()
    }

    private func updateWeatherCondition(from weatherCode: String, marksAPIAvailable: Bool) {
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

        if marksAPIAvailable {
            weatherAPIAvailable = true
            debugLog("✅ 天气API标记为可用")
        }

        postWeatherUpdate()
    }

    private func postWeatherUpdate() {
        NotificationCenter.default.post(
            name: Self.weatherDidUpdateNotification,
            object: self,
            userInfo: [
                Self.apiWeatherCodeUserInfoKey: apiWeatherCode as Any,
                Self.apiWeatherDescriptionUserInfoKey: apiWeatherDescription as Any,
                Self.apiAvailableUserInfoKey: weatherAPIAvailable,
                Self.effectiveWeatherCodeUserInfoKey: rawWeatherString as Any,
                Self.manualOverrideUserInfoKey: isManualOverride,
            ]
        )
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

    func getAPIWeatherCode() -> String? {
        return apiWeatherCode
    }

    func getAPIWeatherDescription() -> String? {
        return apiWeatherDescription
    }

    func startWeatherUpdate() {
        updateWeatherFromAPI()
    }
}
