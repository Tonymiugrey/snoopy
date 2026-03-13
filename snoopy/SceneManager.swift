//
//  SceneManager.swift
//  snoopy
//
//  Created by Gemini on 2024/7/25.
//

import AVFoundation
import SpriteKit

class SceneManager {
    // --- Scene and Nodes ---
    private(set) var skView: SKView?
    private(set) var scene: SKScene?
    private(set) var backgroundColorNode: SKSpriteNode?
    private(set) var halftoneNode: SKSpriteNode?
    private(set) var backgroundImageNode: SKSpriteNode?
    private(set) var videoNode: SKVideoNode?
    private(set) var overlayNode: SKVideoNode?
    private(set) var asVideoNode: SKVideoNode?  // For AS/SS content
    private(set) var cropNode: SKCropNode?
    private(set) var tmMaskSpriteNode: SKSpriteNode?
    private(set) var tmOutlineSpriteNode: SKSpriteNode?

    // --- Properties ---
    private let scale: CGFloat = 720.0 / 1080.0
    private let offside: CGFloat = 180.0 / 1080.0
    // 素材原始宽高比（所有视频内容均为 16:9）
    private let nativeAspectRatio: CGFloat = 16.0 / 9.0
    private var backgroundImages: [String] = []

    // --- Color Palette Manager ---
    private var colorPaletteManager: ColorPaletteManager
    private weak var weatherManager: WeatherManager?

    init(bounds: NSRect, weatherManager: WeatherManager) {
        self.colorPaletteManager = ColorPaletteManager()
        self.weatherManager = weatherManager
        self.skView = SKView(frame: bounds)
        self.scene = SKScene(size: bounds.size)
        loadBackgroundImages()
    }

    /// 计算在给定场景尺寸下，以 aspect-fill 方式显示 16:9 内容所需的节点尺寸。
    /// 节点会被居中放置，超出屏幕边缘的部分由 SKView 裁剪。
    func aspectFillSize(for sceneSize: CGSize) -> CGSize {
        let screenAspect = sceneSize.width / sceneSize.height
        if screenAspect > nativeAspectRatio {
            // 屏幕比内容更宽（超宽屏）：以宽度为准，高度按比例撑满并裁剪
            return CGSize(width: sceneSize.width, height: sceneSize.width / nativeAspectRatio)
        } else {
            // 屏幕比内容更高（如 16:10）：以高度为准，宽度按比例撑满并裁剪
            return CGSize(width: sceneSize.height * nativeAspectRatio, height: sceneSize.height)
        }
    }

    func setupScene(mainPlayer: AVQueuePlayer, overlayPlayer: AVQueuePlayer, asPlayer: AVPlayer) {
        guard let skView = self.skView, let scene = self.scene else { return }

        skView.wantsLayer = true
        skView.layer?.backgroundColor = NSColor.clear.cgColor
        skView.ignoresSiblingOrder = true
        skView.allowsTransparency = true

        scene.scaleMode = .aspectFill
        scene.backgroundColor = .clear

        // Layer 0: Solid Background Color
        let solidColorBGNode = SKSpriteNode(color: NSColor.black, size: scene.size)
        solidColorBGNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        solidColorBGNode.zPosition = 0
        solidColorBGNode.name = "backgroundColor"
        solidColorBGNode.alpha = 1
        scene.addChild(solidColorBGNode)
        self.backgroundColorNode = solidColorBGNode

        // Layer 1: Halftone Pattern
        if let bgImagePath = Bundle(for: type(of: self)).path(
            forResource: "halftone_pattern", ofType: "png"),
            let bgImage = NSImage(contentsOfFile: bgImagePath)
        {
            // 在主线程创建纹理（这里已经在主线程，但保持一致性）
            let bgtexture = SKTexture(image: bgImage)
            let halftone = SKSpriteNode(texture: bgtexture)
            halftone.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
            halftone.size = scene.size
            halftone.zPosition = 1
            halftone.alpha = 0  // 初始设置为透明，直到AS开始播放
            halftone.name = "halftonePattern"
            halftone.blendMode = .alpha
            scene.addChild(halftone)
            self.halftoneNode = halftone
        }

        // Layer 2: IS Background Image
        let imageNode = SKSpriteNode()
        imageNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        imageNode.zPosition = 2
        imageNode.name = "backgroundImage"
        imageNode.blendMode = .alpha
        imageNode.alpha = 0  // 初始设置为透明，直到AS开始播放
        scene.addChild(imageNode)
        self.backgroundImageNode = imageNode

        // Layer 3: Main Video Node - Initialize WITH player (用于播放BP、AP、CM、ST、RPH)
        let videoNode = SKVideoNode(avPlayer: mainPlayer)
        videoNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        videoNode.size = aspectFillSize(for: scene.size)
        videoNode.zPosition = 3  // 常规内容在Layer 3
        videoNode.name = "videoNode"
        scene.addChild(videoNode)
        self.videoNode = videoNode

        // Layer 4: Overlay Node (For VI/WE) - Initialize WITH player
        let overlayNode = SKVideoNode(avPlayer: overlayPlayer)
        overlayNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        overlayNode.size = aspectFillSize(for: scene.size)
        overlayNode.zPosition = 4
        overlayNode.name = "overlayNode"
        overlayNode.isHidden = true  // Initially hidden
        scene.addChild(overlayNode)
        self.overlayNode = overlayNode

        // Layer 10: 创建cropNode专门用于AS/SS内容，始终保持在最上层以确保遮罩效果正确
        let cropNode = SKCropNode()
        cropNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        cropNode.zPosition = 10  // AS/SS内容在最上层，便于遮罩处理
        scene.addChild(cropNode)
        self.cropNode = cropNode

        // AS/SS Video Node - Initialize WITH independent AS player
        let asVideoNode = SKVideoNode(avPlayer: asPlayer)
        asVideoNode.position = CGPoint.zero  // Position relative to cropNode
        asVideoNode.size = aspectFillSize(for: scene.size)
        asVideoNode.name = "asVideoNode"
        asVideoNode.isHidden = true  // Initially hidden until AS content plays
        cropNode.addChild(asVideoNode)
        self.asVideoNode = asVideoNode

        // Layer 15: TM Outline Node - 显示在所有内容之上
        let outlineNode = SKSpriteNode(color: .clear, size: aspectFillSize(for: scene.size))
        outlineNode.position = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        outlineNode.zPosition = 15  // 在所有内容之上
        outlineNode.name = "tmOutlineNode"
        outlineNode.isHidden = true  // 初始隐藏
        outlineNode.blendMode = .alpha
        scene.addChild(outlineNode)
        self.tmOutlineSpriteNode = outlineNode

        skView.presentScene(scene)
    }

    private func loadBackgroundImages() {
        guard let resourcePath = Bundle(for: type(of: self)).resourcePath else { return }
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(atPath: resourcePath)
            // Filter for IS background images only, excluding TM animation files
            let heicFiles = files.filter { file in
                file.hasSuffix(".heic") && file.contains("_IS")
            }
            self.backgroundImages = heicFiles
            debugLog("🖼️ Loaded \(heicFiles.count) IS background images")
        } catch {
            debugLog("Error reading Resources directory: \(error.localizedDescription)")
        }
    }

    func updateBackgrounds() {
        debugLog("🔄 更新背景...")
        updateBackgroundColorAndHalftone()
        updateBackgroundImage()
    }

    private func updateBackgroundColorAndHalftone() {
        guard let bgNode = self.backgroundColorNode,
            let halftoneNode = self.halftoneNode,
            let weatherManager = self.weatherManager
        else { return }

        // 获取天气字符串
        let weatherString = colorPaletteManager.getWeatherString(from: weatherManager)

        // 获取匹配的调色板
        guard let palette = colorPaletteManager.getColorPalette(for: weatherString) else {
            debugLog("❌ 无法获取调色板，使用默认黑色背景")
            bgNode.color = .black
            bgNode.alpha = 1
            halftoneNode.alpha = 1
            return
        }

        // 设置背景色（忽略透明度，始终为1）
        bgNode.color = NSColor(
            red: palette.backgroundColor.redComponent,
            green: palette.backgroundColor.greenComponent,
            blue: palette.backgroundColor.blueComponent,
            alpha: 1.0
        )
        bgNode.alpha = 1

        // 设置halftone层的颜色和透明度
        halftoneNode.color = palette.overlayColor
        halftoneNode.colorBlendFactor = 1.0  // 完全应用颜色混合
        halftoneNode.alpha = 1

        debugLog(
            "🎨 背景颜色更新 - 天气: \(weatherString ?? "无"), 背景色: \(palette.backgroundColor), 叠加色: \(palette.overlayColor)"
        )
    }

    private func updateBackgroundImage() {
        guard let imageNode = self.backgroundImageNode, !backgroundImages.isEmpty,
            let scene = self.scene
        else { return }

        let randomImageName = backgroundImages.randomElement()!

        // 使用 .utility QoS 来避免优先级反转
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            guard
                let imagePath = Bundle(for: type(of: self)).path(
                    forResource: randomImageName, ofType: nil),
                let image = NSImage(contentsOfFile: imagePath)
            else {
                DispatchQueue.main.async {
                    debugLog("❌ 无法加载背景图片: \(randomImageName)")
                }
                return
            }

            // 在后台线程创建纹理，避免主线程阻塞
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear

            // 计算尺寸参数
            let imageAspect = image.size.height / scene.size.height
            guard imageAspect > 0 else {
                DispatchQueue.main.async {
                    debugLog("❌ 错误: IS 图片高度或场景高度为零，无法计算 imageAspect。")
                }
                return
            }

            let newSize = CGSize(
                width: image.size.width / imageAspect * self.scale,
                height: scene.size.height * self.scale
            )
            let newPosition = CGPoint(
                x: scene.size.width / 2,
                y: scene.size.height / 2 - scene.size.height * self.offside
            )

            // 回到主线程更新UI
            DispatchQueue.main.async {
                imageNode.texture = texture
                imageNode.size = newSize
                imageNode.position = newPosition
                imageNode.alpha = 1

                debugLog("🖼️ 背景图片更新为: \(randomImageName)")
            }
        }
    }

    func createTMMaskNode(size: CGSize) {
        let fillSize = aspectFillSize(for: size)
        let maskNode = SKSpriteNode(color: .clear, size: fillSize)
        maskNode.position = .zero  // 相对于cropNode的位置
        self.tmMaskSpriteNode = maskNode
        debugLog("🎭 创建TM遮罩节点，尺寸: \(fillSize)（aspect-fill 自 \(size)）")
    }

    func addToParentView(_ parentView: NSView) {
        guard let skView = self.skView else {
            debugLog("Error: SKView is nil when trying to add to parent view.")
            return
        }
        parentView.addSubview(skView)
    }
}
