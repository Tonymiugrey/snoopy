//
//  SnoopyPreviewApp.swift
//  SnoopyPreview
//
//  Created by miuGrey on 2025/5/5.
//

import SwiftUI

@main
struct SnoopyPreviewApp: App {
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("测试") {
                Button("双屏刷新率测试") {
                    openWindow(id: "dual-display-test")
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])
            }
        }

        Window("双屏刷新率测试", id: "dual-display-test") {
            DualDisplayTestView()
        }
        .defaultSize(width: 1400, height: 750)
    }
}
