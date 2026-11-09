import AppKit
import SwiftUI

@main
struct DailyDigestApp: App {
    @StateObject private var store = DigestStore()

    var body: some Scene {
        WindowGroup("行星日报") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.preferredAppearance)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        AppearanceMenu(store: store)
                    }
                }
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandMenu("外观") {
                Button("跟随系统") { store.appearanceMode = "system" }
                Button("浅色纸面") { store.appearanceMode = "light" }
                Button("深色墨蓝") { store.appearanceMode = "dark" }
            }

            CommandGroup(after: .appSettings) {
                Button("偏好设置…") {
                    NotificationCenter.default.post(
                        name: Notification.Name("DailyDigestOpenSettings"),
                        object: nil
                    )
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Button("重新加载") {
                    store.reload()
                }
                .keyboardShortcut("r")

                Button("立即更新") {
                    store.generateNow()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(store.isGenerating)

                Divider()

                Button("前一天") {
                    store.previousDay()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                Button("后一天") {
                    store.nextDay()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!store.canGoNext)

                Button("回到今天") {
                    store.goToday()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("打开数据文件夹") {
                    store.openDataFolder()
                }

                Button("打开日志文件夹") {
                    store.openLogFolder()
                }

                Divider()

                Button("导出 Windows 版…") {
                    exportWindows()
                }
                .help("把当天日报打包成 Windows 双击可用的离线客户端")
            }
        }
    }

    /// 导出 Windows 离线版：调用工程内的打包器，生成自包含页面、数据快照与中文播报音频。
    /// 全程本地、零网络、零大模型；完成后在访达里打开交付目录。
    private func exportWindows() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let windowsDir = home.appendingPathComponent("Developer/DailyDigest/windows")
        let script = windowsDir.appendingPathComponent("build_windows.py")
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = ["-u", script.path]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            environment["LANG"] = "zh_CN.UTF-8"
            environment.removeValue(forKey: "PYTHONPATH")
            task.environment = environment
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            DispatchQueue.main.async {
                NSWorkspace.shared.open(windowsDir)
            }
        }
    }
}

// 保留系统菜单，同时在窗口中提供明确的外观入口。
private struct AppearanceMenu: View {
    @ObservedObject var store: DigestStore

    private func option(_ title: String, mode: String, symbol: String) -> some View {
        Button {
            store.appearanceMode = mode
        } label: {
            Label(title, systemImage: store.appearanceMode == mode ? "checkmark" : symbol)
        }
    }

    var body: some View {
        Menu {
            option("白天模式", mode: "light", symbol: "sun.max")
            option("深色模式", mode: "dark", symbol: "moon")
            Divider()
            option("跟随系统", mode: "system", symbol: "circle.lefthalf.filled")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "circle.lefthalf.filled")
                Text("外观")
            }
        }
        .help("切换白天、深色或跟随系统")
        .accessibilityLabel("切换外观")
    }
}
