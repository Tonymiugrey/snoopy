import AVFoundation
import ScreenSaver
import SpriteKit

@objc(SnoopyScreenSaverView)
class SnoopyScreenSaverView: ScreenSaverView, SKSceneDelegate {

    // Lame-Duck 实例管理：新实例创建时通知旧实例停止工作
    // 这个机制替代对 willstop 通知的依赖，在 macOS Sonoma+ 上通知不再可靠
    private static let newInstanceNotification = Notification.Name(
        "com.snoopy.screensaver.newInstance")
    private var isLameDuck = false

    // 所有管理器
    private var stateManager: StateManager!
    private var sceneManager: SceneManager!
    private var playerManager: PlayerManager!
    private var playbackManager: PlaybackManager!
    private var transitionManager: TransitionManager!
    private var sequenceManager: SequenceManager!
    private var overlayManager: OverlayManager!
    private var weatherManager: WeatherManager!

    private var skView: SKView!
    private var isSetupComplete = false
    private var allClips: [SnoopyClip] = []
    private var hasBroadcastDisplayClaim = false
    private weak var observedWindow: NSWindow?

    // MARK: - 初始化

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = 1.0 / 24.0

        // 注册监听新实例通知，当同屏有更新的实例创建时，本实例进入 lame-duck
        // 注意：通知的发送移到 startAnimation()，届时才能获取屏幕 displayID
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onNewInstance(_:)),
            name: SnoopyScreenSaverView.newInstanceNotification,
            object: nil
        )

        // 在Sonoma+上延迟初始化，避免legacyScreenSaver问题
        if #available(macOS 14.0, *) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.performSetup()
            }
        } else {
            performSetup()
        }

        setNotifications()
    }

    /// 获取 NSScreen 对应的 CGDirectDisplayID。
    private func displayID(for screen: NSScreen?) -> UInt32? {
        guard
            let screenNumber = screen?.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return screenNumber.uint32Value
    }

    private func intersectionArea(between lhs: NSRect, and rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    /// 优先按窗口 frame 与屏幕 frame 的交集来判定所在屏幕。
    /// 在多屏初始化阶段，window.screen 可能短暂指向错误的屏幕。
    private func resolvedScreen() -> NSScreen? {
        guard let window else { return nil }

        let windowFrame = window.frame
        let matchedScreen = NSScreen.screens
            .map { ($0, intersectionArea(between: windowFrame, and: $0.frame)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0

        if
            let matchedScreen,
            let windowScreen = window.screen,
            matchedScreen !== windowScreen,
            let matchedDisplayID = displayID(for: matchedScreen),
            let windowDisplayID = displayID(for: windowScreen)
        {
            debugLog(
                "📺 window.screen 与窗口 frame 命中的屏幕不一致，优先使用 frame 命中结果: window=\(windowDisplayID), frameMatch=\(matchedDisplayID), windowFrame=\(NSStringFromRect(windowFrame))"
            )
        }

        return matchedScreen ?? window.screen
    }

    private var windowFrameDescription: String {
        guard let window else { return "nil" }
        return NSStringFromRect(window.frame)
    }

    /// 获取当前视图所在屏幕的 CGDirectDisplayID。
    /// 在 startAnimation() 之前可能为 nil（视图尚未进入窗口层级）。
    private var currentDisplayID: UInt32? {
        displayID(for: resolvedScreen())
    }

    private func syncSceneLayoutToBounds() {
        guard let skView else { return }

        skView.frame = bounds
        sceneManager?.updateLayout(for: bounds.size)
        overlayManager?.updateLayout(for: bounds.size)
    }

    private func updateWindowObservation() {
        let currentWindow = window

        if let observedWindow, let currentWindow, observedWindow === currentWindow {
            return
        }

        if observedWindow == nil, currentWindow == nil {
            return
        }

        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didChangeScreenNotification,
                object: observedWindow
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didMoveNotification,
                object: observedWindow
            )
        }

        observedWindow = currentWindow

        if let currentWindow {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onWindowDidChangeScreen(_:)),
                name: NSWindow.didChangeScreenNotification,
                object: currentWindow
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onWindowDidMove(_:)),
                name: NSWindow.didMoveNotification,
                object: currentWindow
            )
        }
    }

    private func refreshDisplayBinding(reason: String) {
        updateWindowObservation()
        syncSceneLayoutToBounds()

        guard window != nil else { return }

        hasBroadcastDisplayClaim = false
        debugLog(
            "📺 重新同步显示绑定(\(reason)): displayID=\(String(describing: currentDisplayID)), windowFrame=\(windowFrameDescription)"
        )
        broadcastActiveInstanceIfNeeded(retryCount: 6)
    }

    private func broadcastActiveInstanceIfNeeded(retryCount: Int = 6) {
        guard isAnimating, !isLameDuck, !hasBroadcastDisplayClaim else { return }

        updateWindowObservation()

        guard let displayID = currentDisplayID else {
            guard retryCount > 0 else {
                debugLog(
                    "⚠️ 无法获取当前 displayID，跳过同屏实例淘汰广播。windowFrame=\(windowFrameDescription)"
                )
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.broadcastActiveInstanceIfNeeded(retryCount: retryCount - 1)
            }
            return
        }

        hasBroadcastDisplayClaim = true
        debugLog("📺 广播当前实例 displayID=\(displayID), windowFrame=\(windowFrameDescription)")
        NotificationCenter.default.post(
            name: SnoopyScreenSaverView.newInstanceNotification,
            object: self,
            userInfo: ["displayID": displayID]
        )
    }

    // 收到新实例通知时，将自身标记为 lame-duck 并停止工作
    // 仅当新实例与自己在同一块屏幕上时才让位，避免误杀其他屏幕的合法实例
    @objc private func onNewInstance(_ notification: Notification) {
        // 排除自己发出的通知
        if let sender = notification.object as? SnoopyScreenSaverView, sender === self {
            return
        }

        guard let senderDisplayID = notification.userInfo?["displayID"] as? UInt32 else {
            debugLog("⚠️ 收到缺少 displayID 的实例通知，忽略")
            return
        }

        guard let myDisplayID = currentDisplayID else {
            debugLog("⚠️ 当前实例尚未解析 displayID，忽略实例淘汰通知")
            return
        }

        guard senderDisplayID == myDisplayID else { return }
        guard !isLameDuck else { return }
        isLameDuck = true
        NSLog("SnoopyScreenSaverView: 进入 lame-duck 状态，让位给新实例")
        playerManager?.queuePlayer.pause()
        playerManager?.overlayPlayer.pause()
        playerManager?.asPlayer.pause()
        skView?.presentScene(nil)
    }

    private func performSetup() {
        guard !isSetupComplete, !isLameDuck else { return }

        // 1. 设置 SpriteKit 视图
        skView = SKView(frame: bounds)
        skView.autoresizingMask = [.width, .height]
        addSubview(skView)

        // 2. 初始化基本管理器
        stateManager = StateManager()
        playerManager = PlayerManager()
        weatherManager = WeatherManager()
        sceneManager = SceneManager(bounds: bounds, weatherManager: weatherManager)

        // 3. 异步加载视频片段
        Task {
            do {
                debugLog("Loading clips...")
                self.allClips = try await SnoopyClip.loadClips()
                debugLog("Clips loaded: \(self.allClips.count)")

                guard !self.allClips.isEmpty else {
                    debugLog("No clips loaded, cannot start.")
                    return
                }

                // 现在我们有了视频片段，初始化依赖序列的管理器
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    // 初始化依赖序列的管理器
                    self.sequenceManager = SequenceManager(stateManager: self.stateManager)
                    self.stateManager.allClips = self.allClips

                    // 初始化需要视频片段的管理器
                    self.overlayManager = OverlayManager(
                        allClips: self.allClips,
                        weatherManager: self.weatherManager,
                        stateManager: self.stateManager
                    )

                    self.transitionManager = TransitionManager(
                        stateManager: self.stateManager,
                        playerManager: self.playerManager,
                        sceneManager: self.sceneManager
                    )

                    // 最后创建协调一切的播放管理器
                    self.playbackManager = PlaybackManager(
                        stateManager: self.stateManager,
                        playerManager: self.playerManager,
                        sceneManager: self.sceneManager,
                        transitionManager: self.transitionManager
                    )

                    // 设置各管理器之间的依赖关系
                    self.transitionManager.setDependencies(
                        playbackManager: self.playbackManager,
                        sequenceManager: self.sequenceManager,
                        overlayManager: self.overlayManager
                    )

                    // 设置播放管理器的序列管理器和叠加层管理器
                    self.playbackManager.setSequenceManager(self.sequenceManager)
                    self.playbackManager.setOverlayManager(self.overlayManager)

                    // 4. 配置真实的渲染视图并完成初始化
                    self.sceneManager.configure(skView: self.skView)
                    self.sceneManager.setupScene(
                        mainPlayer: self.playerManager.queuePlayer,
                        overlayPlayer: self.playerManager.overlayPlayer,
                        asPlayer: self.playerManager.asPlayer
                    )

                    if let scene = self.sceneManager.scene {
                        scene.delegate = self
                        self.skView.presentScene(scene)
                    }

                    // 5. 在场景中设置覆盖节点
                    if let scene = self.sceneManager.scene {
                        self.overlayManager.setupOverlayNode(in: scene)
                    }

                    self.syncSceneLayoutToBounds()

                    // 6. 检查天气（如果适用）
                    self.weatherManager.startWeatherUpdate()

                    // 7. 标记设置为完成
                    self.isSetupComplete = true

                    // 8. 如果动画已经开始，现在开始播放
                    if self.isAnimating {
                        self.broadcastActiveInstanceIfNeeded()
                        self.setupInitialStateAndPlay()
                    }
                }
            } catch {
                debugLog("Error loading clips: \(error)")
            }
        }
    }

    deinit {
        NSLog("SnoopyScreenSaverView 正在释放资源")
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        playerManager?.queuePlayer.pause()
        playerManager?.overlayPlayer.pause()
        playerManager?.asPlayer.pause()

        // 清理 SKView 以避免内存泄漏
        skView?.presentScene(nil)
    }

    // MARK: - ScreenSaverView 生命周期

    override func startAnimation() {
        super.startAnimation()

        // lame-duck 实例不响应动画请求
        guard !isLameDuck else { return }

        refreshDisplayBinding(reason: "startAnimation")

        if isSetupComplete && sequenceManager != nil {
            setupInitialStateAndPlay()
        }
        // 否则，完成设置后将处理
    }

    override func stopAnimation() {
        super.stopAnimation()

        hasBroadcastDisplayClaim = false

        // 暂停所有播放器
        playerManager?.queuePlayer.pause()
        playerManager?.overlayPlayer.pause()
        playerManager?.asPlayer.pause()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        refreshDisplayBinding(reason: "viewDidMoveToWindow")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSceneLayoutToBounds()

        if window != nil && !hasBroadcastDisplayClaim {
            broadcastActiveInstanceIfNeeded(retryCount: 6)
        }
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
    }

    // 添加此静态方法以支持现代屏幕保护程序引擎
    @objc static func isCompatibleWithModernScreenSaverEngine() -> Bool {
        return true
    }

    // 设置通知观察者
    private func setNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // 监听屏幕保护程序将要停止的通知
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(willStop(_:)),
            name: Notification.Name("com.apple.screensaver.willstop"),
            object: nil
        )

        // 监听屏幕保护程序将要开始的通知
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(willStart(_:)),
            name: Notification.Name("com.apple.screensaver.willstart"),
            object: nil
        )

        // 监听系统睡眠的通知
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onSleepNote(note:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    // 屏幕保护程序将要停止
    @objc private func willStop(_ notification: Notification) {
        debugLog("屏保将要停止")
        stopAnimation()

        // 在 Sonoma+ 上退出进程清理 legacyScreenSaver
        // 注意：Tahoe 上此通知可能不再可靠，主要防线已改为 lame-duck 机制
        if #available(macOS 14.0, *) {
            debugLog("⏱️ 安排本进程延迟退出清理 legacyScreenSaver")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                exit(0)
            }
        }
    }

    // 屏幕保护程序将要开始
    @objc private func willStart(_ notification: Notification) {
        debugLog("屏保将要开始")
    }

    // 系统将要睡眠
    @objc private func onSleepNote(note: Notification) {
        debugLog("系统将要睡眠")

        // 在 Sonoma+ 上退出进程清理
        if #available(macOS 14.0, *) {
            exit(0)
        }
    }

    @objc private func onWindowDidChangeScreen(_ notification: Notification) {
        refreshDisplayBinding(reason: "windowDidChangeScreen")
    }

    @objc private func onWindowDidMove(_ notification: Notification) {
        if !hasBroadcastDisplayClaim {
            broadcastActiveInstanceIfNeeded(retryCount: 6)
        }
    }

    @objc private func onScreenParametersDidChange(_ notification: Notification) {
        refreshDisplayBinding(reason: "screenParametersDidChange")
    }

    // MARK: - SKSceneDelegate

    func update(_ currentTime: TimeInterval, for scene: SKScene) {
        // 目前暂不实现
    }

    private func setupInitialStateAndPlay() {
        debugLog("Setting up initial state...")
        guard let initialAS = sequenceManager.findRandomClip(ofType: .AS) else {
            debugLog("Error: No AS clips found to start.")
            return
        }
        debugLog("Initial AS: \(initialAS.fileName)")

        // 为初始AS设置随机转场编号，排除006
        let availableTransitionNumbers = allClips.compactMap { clip in
            guard clip.type == .TM_Hide else { return nil }
            return clip.number
        }.filter { $0 != "006" }  // 排除006编号

        if let randomNumber = availableTransitionNumbers.randomElement() {
            stateManager.lastTransitionNumber = randomNumber
            debugLog("🎲 为初始AS设置随机转场编号: \(randomNumber)")
        } else {
            debugLog("⚠️ 警告：无法找到可用的转场编号")
        }

        stateManager.currentStateType = .playingAS
        stateManager.currentClipsQueue = [initialAS]
        stateManager.currentClipIndex = 0
        playbackManager.playNextClipInQueue()
    }

    // MARK: - Manual Weather Control

    func setManualWeather(_ weatherCode: String) {
        weatherManager?.setManualWeatherCode(weatherCode)
    }

    func resetManualWeather() {
        weatherManager?.resetManualWeather()
    }

    func setManualTimeOfDay(_ timeOfDay: String?) {
        weatherManager?.setManualTimeOfDay(timeOfDay)
    }
}
