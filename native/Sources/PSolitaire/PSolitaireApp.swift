// PSolitaireApp.swift — 앱 진입점·메뉴·단축키.

import SwiftUI
import AppKit

@main
struct PSolitaireApp: App {
    @StateObject private var controller = GameController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // 창 탭 기능은 카드 게임에 필요 없고 윈도우 메뉴만 복잡하게 만든다.
        NSWindow.allowsAutomaticWindowTabbing = false

        // 창을 띄우지 않는 검사 모드(자체 검사 · PNG 렌더).
        let args = CommandLine.arguments
        if args.contains("--selftest") || args.contains("--shots") {
            let code = MainActor.assumeIsolated { SelfTest.run(args) }
            exit(code)
        }
    }

    var body: some Scene {
        WindowGroup {
            GameWindowView(controller: controller)
                .onAppear { appDelegate.controller = controller }
        }
        .windowResizability(.contentSize)
        .commands { GameCommands(controller: controller) }

        Settings {
            SettingsView(controller: controller)
        }

        Window("전적", id: "stats") {
            StatsView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}

/// 앱 종료·마지막 창 닫기 때 진행 중인 판을 한 번 더 저장한다.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: GameController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.saveCurrentGame()
    }
}

struct GameCommands: Commands {
    @ObservedObject var controller: GameController
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(replacing: .undoRedo) {
            Button("실행 취소") { controller.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!controller.game.canUndo || controller.busy)
            Button("실행 복귀") { controller.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!controller.game.canRedo || controller.busy)
        }

        CommandMenu("게임") {
            Button("새 게임") { controller.requestNewGame() }
                .keyboardShortcut("n", modifiers: .command)
            Button("같은 판 다시 시작") { controller.requestRestartGame() }
                .keyboardShortcut("r", modifiers: .command)
            Button("판 번호 복사") { controller.copySeed() }
            Button("판 번호로 새 게임…") { controller.showSeedEntry = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("클론다이크") { controller.requestSwitchGame(.klondike) }
                .keyboardShortcut("1", modifiers: .command)
            Button("프리셀") { controller.requestSwitchGame(.freecell) }
                .keyboardShortcut("2", modifiers: .command)
            Button("스파이더") { controller.requestSwitchGame(.spider) }
                .keyboardShortcut("3", modifiers: .command)

            Menu("스파이더 난이도") {
                Button(mark(controller.spiderSuits == 1, "1무늬 (쉬움)")) {
                    controller.setSpiderSuits(1)
                }
                Button(mark(controller.spiderSuits == 2, "2무늬 (보통)")) {
                    controller.setSpiderSuits(2)
                }
                Button(mark(controller.spiderSuits == 4, "4무늬 (어려움)")) {
                    controller.setSpiderSuits(4)
                }
            }
            .disabled(controller.variant != .spider)
            Menu("스파이더 묶음 이동") {
                Button(mark(controller.spiderGroup == "same_suit", "같은 무늬만 (MS 규칙)")) {
                    controller.setSpiderGroup("same_suit")
                }
                Button(mark(controller.spiderGroup == "any_suit", "무늬 상관없이 (쉬움)")) {
                    controller.setSpiderGroup("any_suit")
                }
            }
            .disabled(controller.variant != .spider)

            Toggle("스파이더 풀리는 판만", isOn: Binding(
                get: { controller.spiderWinnable },
                set: { controller.setSpiderWinnable($0) }))
                .disabled(controller.preparingDeal)

            Divider()

            Button(mark(controller.drawCount == 1, "카드 1장씩 넘기기")) {
                controller.setDrawCount(1)
            }
            .disabled(controller.variant != .klondike)
            Button(mark(controller.drawCount == 3, "카드 3장씩 넘기기")) {
                controller.setDrawCount(3)
            }
            .disabled(controller.variant != .klondike)

            Divider()

            Menu("자동 기능") {
                Button(mark(controller.autoAllOn(), "자동 기능 모두 켜기/끄기")) {
                    controller.toggleAutoAll()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                ForEachFeatures(controller: controller)
            }
            Button("자동 완성") { controller.startAutoComplete() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(controller.busy)
            Button("힌트 보기") { controller.showHint() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(controller.busy)

            Divider()

            Button("전적 보기") { openWindow(id: "stats") }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(controller.busy)
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("확대") { controller.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(controller.preferredZoomPct >= GameController.zoomLevels.last!)
            Button("축소") { controller.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(controller.preferredZoomPct <= GameController.zoomLevels.first!)
            Button("100%로 보기") { controller.zoomReset() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(controller.preferredZoomPct == 100)

            Divider()

            Menu("배경") {
                ForEach(backgroundKeys, id: \.self) { key in
                    Button(mark(controller.backgroundKey == key,
                                tableThemes[key]?.title ?? key)) {
                        controller.setTheme(background: key)
                    }
                }
            }
            Menu("카드 뒷면") {
                ForEach(backKeys, id: \.self) { key in
                    Button(mark(controller.backKey == key,
                                backThemes[key]?.title ?? key)) {
                        controller.setTheme(back: key)
                    }
                }
            }
        }

        CommandGroup(replacing: .appInfo) {
            Button("P-Solitaire 정보") { controller.showAbout() }
        }

        CommandGroup(replacing: .help) {
            Button("사용 방법") { controller.showHelp() }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            Button(mark(controller.showDebugPanel, "디버그 패널")) {
                controller.showDebugPanelToggle()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }

    /// 켜짐 표시(✓)를 붙인 메뉴 이름.
    private func mark(_ on: Bool, _ title: String) -> String {
        on ? "✓ " + title : "  " + title
    }
}

/// 자동 기능 세 가지 토글(메뉴 안에서 쓴다).
private struct ForEachFeatures: View {
    @ObservedObject var controller: GameController

    var body: some View {
        ForEach(AutoFeature.allCases, id: \.rawValue) { feature in
            Button(mark(controller.autoOn(feature), feature.title)) {
                controller.setAuto(feature, on: !controller.autoOn(feature))
            }
        }
    }

    private func mark(_ on: Bool, _ title: String) -> String {
        on ? "✓ " + title : "  " + title
    }
}
