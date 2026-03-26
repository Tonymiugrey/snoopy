//
//  DualDisplayTestView.swift
//  SnoopyPreview
//
//  双屏不同刷新率测试视图
//  模拟 ProMotion 120Hz 内置屏 + 60Hz 外接屏 的场景，
//  验证 SpriteKit preferredFramesPerSecond 修复是否生效。
//

import AppKit
import SwiftUI

// MARK: - NSViewRepresentable Wrapper (支持刷新率模拟 + FPS 回调)

struct DualDisplaySnoopyWrapper: NSViewRepresentable {
    let simulatedFPS: Int
    let screenLabel: String
    /// 回调：将创建的实例 ID 传给父级，用于匹配 FPS 通知
    var onInstanceCreated: ((Int) -> Void)?

    func makeNSView(context: Context) -> SnoopyScreenSaverView {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        guard let view = SnoopyScreenSaverView(frame: frame, isPreview: false) else {
            return SnoopyScreenSaverView()
        }
        view.disableLameDuck = true
        view.setSimulatedRefreshRate(simulatedFPS)
        view.startAnimation()
        let instanceID = ObjectIdentifier(view).hashValue
        DispatchQueue.main.async {
            onInstanceCreated?(instanceID)
        }
        return view
    }

    func updateNSView(_ nsView: SnoopyScreenSaverView, context: Context) {
        nsView.setSimulatedRefreshRate(simulatedFPS)
    }
}

// MARK: - FPS Monitor (接收通知并更新 SwiftUI 状态)

@Observable
final class FPSStore {
    var leftFPS: Double = 0
    var rightFPS: Double = 0
    var leftInstanceID: Int = 0
    var rightInstanceID: Int = 0

    private var observer: Any?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: SnoopyScreenSaverView.fpsDidUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let fps = notification.userInfo?["fps"] as? Double,
                  let instanceID = notification.userInfo?["instanceID"] as? Int
            else { return }
            if instanceID == self.leftInstanceID {
                self.leftFPS = fps
            } else if instanceID == self.rightInstanceID {
                self.rightFPS = fps
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

// MARK: - Dual Display Test View

struct DualDisplayTestView: View {
    @AppStorage("dualTest_leftFPS") private var leftFPS: Int = 120
    @AppStorage("dualTest_rightFPS") private var rightFPS: Int = 60
    @State private var fpsStore = FPSStore()

    private let fpsOptions = [24, 30, 48, 60, 120]

    var body: some View {
        VStack(spacing: 0) {
            // 双屏预览区域
            HStack(spacing: 0) {
                // 左屏（模拟内置屏）
                ZStack(alignment: .topLeading) {
                    DualDisplaySnoopyWrapper(
                        simulatedFPS: leftFPS,
                        screenLabel: "内置屏"
                    ) { instanceID in
                        fpsStore.leftInstanceID = instanceID
                    }
                    screenBadge(
                        label: "内置屏", fps: leftFPS,
                        measuredFPS: fpsStore.leftFPS, color: .blue
                    )
                }

                // 分隔线
                Rectangle()
                    .fill(Color.yellow.opacity(0.8))
                    .frame(width: 2)

                // 右屏（模拟外接屏）
                ZStack(alignment: .topTrailing) {
                    DualDisplaySnoopyWrapper(
                        simulatedFPS: rightFPS,
                        screenLabel: "外接屏"
                    ) { instanceID in
                        fpsStore.rightInstanceID = instanceID
                    }
                    screenBadge(
                        label: "外接屏", fps: rightFPS,
                        measuredFPS: fpsStore.rightFPS, color: .green
                    )
                }
            }

            // 底部控制面板
            controlPanel
        }
        .background(Color.black)
    }

    // MARK: - 屏幕标签

    @ViewBuilder
    private func screenBadge(label: String, fps: Int, measuredFPS: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(fps == leftFPS && fps == rightFPS ? .orange : color)
                    .frame(width: 8, height: 8)
                Text("\(label)  \(fps) Hz")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            HStack(spacing: 4) {
                Text("实际:")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                Text(String(format: "%.1f fps", measuredFPS))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(fpsColor(measuredFPS, target: fps))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.65))
        .cornerRadius(8)
        .padding(12)
    }

    private func fpsColor(_ measured: Double, target: Int) -> Color {
        if measured < 1 { return .gray }
        let ratio = measured / Double(min(target, 60))
        if ratio >= 0.9 { return .green }
        if ratio >= 0.5 { return .yellow }
        return .red
    }

    // MARK: - 控制面板

    private var controlPanel: some View {
        HStack(spacing: 32) {
            fpsPicker(label: "内置屏 刷新率", selection: $leftFPS, color: .blue)

            // 状态指示
            VStack(spacing: 4) {
                if leftFPS == rightFPS {
                    Text("刷新率一致")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.green)
                    Text("不会触发 SpriteKit bug")
                        .font(.system(size: 10))
                        .foregroundColor(.green.opacity(0.7))
                } else {
                    Text("刷新率不一致")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                    Text("验证 preferredFramesPerSecond=60 修复")
                        .font(.system(size: 10))
                        .foregroundColor(.orange.opacity(0.7))
                }
            }
            .frame(minWidth: 180)

            fpsPicker(label: "外接屏 刷新率", selection: $rightFPS, color: .green)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func fpsPicker(label: String, selection: Binding<Int>, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                ForEach(fpsOptions, id: \.self) { fps in
                    Button {
                        selection.wrappedValue = fps
                    } label: {
                        Text("\(fps)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(selection.wrappedValue == fps ? .white : .secondary)
                            .frame(minWidth: 36)
                            .padding(.vertical, 5)
                            .background(
                                selection.wrappedValue == fps
                                    ? color.opacity(0.85) : Color.white.opacity(0.08)
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    DualDisplayTestView()
        .frame(width: 1200, height: 700)
}
