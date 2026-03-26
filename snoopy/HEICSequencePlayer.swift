//
//  HEICSequencePlayer.swift
//  snoopy
//
//  Created by miuGrey on 2025/01/07.
//

import AVFoundation
import AppKit
import Foundation
import SpriteKit

class HEICSequencePlayer {
    private var maskTextures: [SKTexture] = []
    private var outlineTextures: [SKTexture] = []
    private var currentIndex: Int = 0
    private var animationAction: SKAction?
    private let frameRate: Double = 24.0  // 24 fps
    private var isPlaying: Bool = false
    private var completion: (() -> Void)?

    weak var targetMaskNode: SKSpriteNode?
    weak var targetOutlineNode: SKSpriteNode?

    init() {}

    deinit {
        stop()
    }

    // 加载HEIC序列 - 异步版本
    func loadSequence(basePattern: String, completion: @escaping (Bool) -> Void) {
        debugLog("🎬 HEICSequencePlayer: 正在异步加载序列 \(basePattern)")

        maskTextures.removeAll()
        outlineTextures.removeAll()

        // 清理 basePattern，移除可能的 _Mask 或 _Outline 后缀
        let cleanBasePattern = cleanBasePattern(basePattern)
        debugLog("🔧 清理后的基础模式: \(cleanBasePattern)")

        // 使用 .utility QoS 级别来避免优先级反转
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(false)
                }
                return
            }

            // 加载 mask 序列的图像数据并创建纹理
            let maskTextures = self.loadMaskTexturesAsync(basePattern: cleanBasePattern)

            // 加载 outline 序列的图像数据并创建纹理
            let outlineTextures = self.loadOutlineTexturesAsync(basePattern: cleanBasePattern)

            // 回到主线程更新状态
            DispatchQueue.main.async {
                self.maskTextures = maskTextures
                self.outlineTextures = outlineTextures

                let maskLoaded = !maskTextures.isEmpty
                let outlineLoaded = !outlineTextures.isEmpty

                if maskLoaded {
                    debugLog("✅ HEICSequencePlayer: Mask 序列加载成功，\(maskTextures.count) 帧")
                    if outlineLoaded {
                        debugLog("✅ HEICSequencePlayer: Outline 序列加载成功，\(outlineTextures.count) 帧")
                    } else {
                        debugLog("ℹ️ HEICSequencePlayer: 未找到 Outline 序列，将仅播放 Mask")
                    }
                    completion(true)
                } else {
                    debugLog("❌ HEICSequencePlayer: Mask 序列加载失败")
                    completion(false)
                }
            }
        }
    }

    // 同步版本保持兼容性（内部使用异步实现）
    func loadSequence(basePattern: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false

        loadSequence(basePattern: basePattern) { success in
            result = success
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // 清理基础模式，移除可能的 _Mask 或 _Outline 后缀
    private func cleanBasePattern(_ pattern: String) -> String {
        if pattern.hasSuffix("_Mask") {
            return String(pattern.dropLast(5))  // 移除 "_Mask"
        } else if pattern.hasSuffix("_Outline") {
            return String(pattern.dropLast(8))  // 移除 "_Outline"
        }
        return pattern
    }

    // 加载 mask 序列纹理 - 异步版本（在后台线程执行，包含纹理创建）
    private func loadMaskTexturesAsync(basePattern: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // 构造 mask 的完整名称
        let maskBasePattern = basePattern + "_Mask"
        var frameIndex = 0

        // 首先尝试加载带帧号的格式
        while true {
            let fileName = String(format: "%@_%06d", maskBasePattern, frameIndex)

            if let url = Bundle(for: type(of: self)).url(
                forResource: fileName, withExtension: "heic")
            {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = .linear
                        textures.append(texture)
                        debugLog("📸 后台加载 mask 纹理: \(fileName).heic")
                    } else {
                        debugLog("❌ 无法从 \(fileName).heic 创建 mask 图像")
                        break
                    }
                } catch {
                    debugLog("❌ 无法从 \(fileName).heic 加载 mask 数据: \(error.localizedDescription)")
                    break
                }
            } else {
                if frameIndex == 0 {
                    debugLog("⚠️ 未找到 mask 帧序列，尝试加载单个文件 \(maskBasePattern).heic")
                    // 尝试加载单个文件
                    if let url = Bundle(for: type(of: self)).url(
                        forResource: maskBasePattern, withExtension: "heic")
                    {
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = NSImage(data: imageData) {
                                let texture = SKTexture(image: image)
                                texture.filteringMode = .linear
                                textures.append(texture)
                                debugLog("📸 后台加载单个 mask HEIC文件: \(maskBasePattern).heic")
                            }
                        } catch {
                            debugLog(
                                "❌ 无法加载单个 mask 文件 \(maskBasePattern).heic: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        debugLog("❌ 找不到任何匹配 \(maskBasePattern) 的 mask HEIC文件")
                    }
                } else {
                    debugLog("✅ Mask 纹理后台加载完成，共 \(frameIndex) 帧")
                }
                break
            }

            frameIndex += 1
        }

        return textures
    }

    // 加载 outline 序列纹理 - 异步版本（在后台线程执行，包含纹理创建）
    private func loadOutlineTexturesAsync(basePattern: String) -> [SKTexture] {
        var textures: [SKTexture] = []

        // 构造 outline 的 basePattern
        let outlineBasePattern = basePattern + "_Outline"
        var frameIndex = 0

        // 尝试加载带帧号的格式
        while true {
            let fileName = String(format: "%@_%06d", outlineBasePattern, frameIndex)

            if let url = Bundle(for: type(of: self)).url(
                forResource: fileName, withExtension: "heic")
            {
                do {
                    let imageData = try Data(contentsOf: url)
                    if let image = NSImage(data: imageData) {
                        let texture = SKTexture(image: image)
                        texture.filteringMode = .linear
                        textures.append(texture)
                        debugLog("📸 后台加载 outline 纹理: \(fileName).heic")
                    } else {
                        debugLog("❌ 无法从 \(fileName).heic 创建 outline 图像")
                        break
                    }
                } catch {
                    debugLog("❌ 无法从 \(fileName).heic 加载 outline 数据: \(error.localizedDescription)")
                    break
                }
            } else {
                if frameIndex == 0 {
                    debugLog("⚠️ 未找到 outline 帧序列，尝试加载单个文件 \(outlineBasePattern).heic")
                    // 尝试加载单个文件
                    if let url = Bundle(for: type(of: self)).url(
                        forResource: outlineBasePattern, withExtension: "heic")
                    {
                        do {
                            let imageData = try Data(contentsOf: url)
                            if let image = NSImage(data: imageData) {
                                let texture = SKTexture(image: image)
                                texture.filteringMode = .linear
                                textures.append(texture)
                                debugLog("📸 后台加载单个 outline HEIC文件: \(outlineBasePattern).heic")
                            }
                        } catch {
                            debugLog(
                                "❌ 无法加载单个 outline 文件 \(outlineBasePattern).heic: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        debugLog("ℹ️ 找不到任何匹配 \(outlineBasePattern) 的 outline HEIC文件")
                    }
                } else {
                    debugLog("✅ Outline 纹理后台加载完成，共 \(frameIndex) 帧")
                }
                break
            }

            frameIndex += 1
        }

        return textures
    }

    // 开始播放序列（双层播放：mask + outline）
    func playDual(
        maskNode: SKSpriteNode, outlineNode: SKSpriteNode, completion: (() -> Void)? = nil
    ) {
        guard !maskTextures.isEmpty else {
            debugLog("❌ HEICSequencePlayer: 无法播放，mask 序列为空")
            completion?()
            return
        }

        self.targetMaskNode = maskNode
        self.targetOutlineNode = outlineNode
        self.completion = completion

        stop()  // 停止任何现有播放

        currentIndex = 0
        isPlaying = true

        // 设置第一帧
        maskNode.texture = maskTextures[0]

        // 设置 outline 第一帧
        if !outlineTextures.isEmpty {
            outlineNode.texture = outlineTextures[0]
            outlineNode.isHidden = false
            debugLog("✅ Outline 节点显示并设置第一帧")
        } else {
            outlineNode.isHidden = true
            debugLog("ℹ️ 没有 outline 纹理，隐藏 outline 节点")
        }

        debugLog("🎬 HEICSequencePlayer: 开始双层播放")
        debugLog("  - Mask: \(maskTextures.count) 帧")
        debugLog("  - Outline: \(outlineTextures.count) 帧")
        debugLog("  - 帧率: \(frameRate) fps")

        // 使用 SKAction 驱动帧动画，替代 Timer。
        // SKAction 内嵌于 SpriteKit 渲染管线，在不同刷新率的多屏环境下
        // 不会出现 Timer 回调与 SpriteKit display-link 不同步导致的冻结。
        startSKActionAnimation()
    }

    // 停止播放
    func stop() {
        targetMaskNode?.removeAction(forKey: "heicMaskAnimation")
        targetOutlineNode?.removeAction(forKey: "heicOutlineAnimation")
        animationAction = nil
        isPlaying = false

        debugLog("⏹️ HEICSequencePlayer: 停止播放")
    }

    // 暂停播放
    func pause() {
        targetMaskNode?.isPaused = true
        targetOutlineNode?.isPaused = true
        isPlaying = false

        debugLog("⏸️ HEICSequencePlayer: 暂停播放")
    }

    // 恢复播放
    func resume() {
        guard !maskTextures.isEmpty && !isPlaying else { return }

        isPlaying = true
        targetMaskNode?.isPaused = false
        targetOutlineNode?.isPaused = false

        // 如果 SKAction 已被移除（如 stop 后再 resume），重新启动
        if targetMaskNode?.action(forKey: "heicMaskAnimation") == nil {
            startSKActionAnimation()
        }

        debugLog("▶️ HEICSequencePlayer: 恢复播放")
    }

    // 跳转到指定时间
    func seek(to time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        let frameIndex = Int(seconds * frameRate)

        guard frameIndex >= 0 && frameIndex < maskTextures.count else { return }

        currentIndex = frameIndex

        // 更新当前帧
        if let maskNode = targetMaskNode {
            maskNode.texture = maskTextures[currentIndex]
        }

        // 更新 outline 节点
        if let outlineNode = targetOutlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }

        debugLog("⏭️ HEICSequencePlayer: 跳转到帧 \(frameIndex) (时间: \(seconds)s)")
    }

    // 获取当前播放状态
    var rate: Float {
        return isPlaying ? 1.0 : 0.0
    }

    // 获取总时长
    var duration: CMTime {
        guard !maskTextures.isEmpty else { return .zero }
        let totalSeconds = Double(maskTextures.count) / frameRate
        return CMTime(seconds: totalSeconds, preferredTimescale: CMTimeScale(frameRate))
    }

    // 获取当前时间
    var currentTime: CMTime {
        let currentSeconds = Double(currentIndex) / frameRate
        return CMTime(seconds: currentSeconds, preferredTimescale: CMTimeScale(frameRate))
    }

    // 使用 SKAction 驱动帧动画
    private func startSKActionAnimation() {
        guard let maskNode = targetMaskNode, !maskTextures.isEmpty else { return }

        let timePerFrame = 1.0 / frameRate

        // Mask 动画
        let maskAnimate = SKAction.animate(with: maskTextures, timePerFrame: timePerFrame)
        let maskSequence = SKAction.sequence([
            maskAnimate,
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.currentIndex = self.maskTextures.count
                self.isPlaying = false
                self.completion?()
            }
        ])
        maskNode.run(maskSequence, withKey: "heicMaskAnimation")

        // Outline 动画（如有）
        if let outlineNode = targetOutlineNode, !outlineTextures.isEmpty {
            let outlineAnimate = SKAction.animate(with: outlineTextures, timePerFrame: timePerFrame)
            outlineNode.run(outlineAnimate, withKey: "heicOutlineAnimation")
        }
    }

    // 私有方法：更新帧（双层播放）—— 保留给 seek() 使用
    private func updateFrame() {
        guard isPlaying && !maskTextures.isEmpty else { return }

        // 检查是否播放完成
        if currentIndex >= maskTextures.count {
            // 播放完成
            stop()
            completion?()
            return
        }

        // 更新 mask 节点纹理
        if let maskNode = targetMaskNode {
            maskNode.texture = maskTextures[currentIndex]
        }

        // 更新 outline 节点纹理
        if let outlineNode = targetOutlineNode, currentIndex < outlineTextures.count {
            outlineNode.texture = outlineTextures[currentIndex]
        }

        currentIndex += 1
    }
}
