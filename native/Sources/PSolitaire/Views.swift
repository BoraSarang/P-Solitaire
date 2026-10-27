// Views.swift — 게임 화면(캔버스·상태바·디버그 패널). 그리기만 여기서 한다.

import SwiftUI
import AppKit
import PSolitaireKit

// MARK: - 게임 화면

/// 빨간 닫기 단추로 디버그 창을 닫아도 메뉴에서 다시 열 수 있게 상태를 맞춘다.
final class DebugWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

struct GameWindowView: View {
    @ObservedObject var controller: GameController
    @State private var keyMonitor: Any?
    @State private var debugWindow: NSWindow?
    @State private var debugDelegate: DebugWindowDelegate?

    var body: some View {
        VStack(spacing: 0) {
            BoardCanvas(controller: controller)
                .frame(width: controller.windowWidth,
                       height: controller.windowHeight - Metrics.controlH - Metrics.statusH)
            GameControlBar(controller: controller)
                .frame(height: Metrics.controlH)
            StatusBarView(controller: controller)
                .frame(height: Metrics.statusH)
        }
        .frame(width: controller.windowWidth, height: controller.windowHeight)
        .scaleEffect(controller.zoomScale, anchor: .topLeading)
        .frame(width: controller.windowWidth * controller.zoomScale,
               height: controller.windowHeight * controller.zoomScale,
               alignment: .topLeading)
        .background(controller.tableTheme.bg)
        .overlay {
            if controller.preparingDeal {
                ZStack {
                    controller.tableTheme.bg.opacity(0.94)
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("풀리는 판을 만드는 중…")
                            .font(.title3.weight(.semibold))
                        Text("잠시만 기다려 주세요")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .foregroundStyle(.white)
                }
                .allowsHitTesting(true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("풀리는 판을 만드는 중")
            }
        }
        .background(WindowAppearanceAccessor(backgroundKey: controller.backgroundKey)
                        .frame(width: 0, height: 0))
        .navigationTitle(controller.windowTitle)
        .onAppear {
            controller.updateWindowTitle()
            controller.applyZoomForCurrentGame()
            controller.adjustWindowForZoom()
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
            controller.saveCurrentGame()
        }
        .onChange(of: controller.variant) { _, _ in
            controller.updateWindowTitle()
        }
        .onChange(of: controller.showDebugPanel) { _, show in
            show ? openDebugWindow() : closeDebugWindow()
        }
        .onChange(of: controller.zoomPct) { _, _ in
            controller.adjustWindowForZoom()
        }
        .alert(item: $controller.alert) { info in
            alert(info)
        }
        .alert(item: $controller.confirm) { request in
            Alert(title: Text(request.title),
                  message: Text(request.message),
                  primaryButton: .destructive(Text(request.confirmTitle)) {
                      request.action()
                  },
                  secondaryButton: .cancel(Text("취소")))
        }
        .sheet(isPresented: $controller.showSeedEntry) {
            SeedEntryView(controller: controller)
        }
    }

    private func alert(_ info: AlertInfo) -> Alert {
        if let secondary = info.secondaryTitle {
            return Alert(title: Text(info.title),
                         message: Text(info.message),
                         primaryButton: .default(Text(info.primaryTitle)) {
                             info.onDismiss?()
                         },
                         secondaryButton: .default(Text(secondary)) {
                             info.secondaryAction?()
                         })
        }
        return Alert(title: Text(info.title),
                     message: Text(info.message),
                     dismissButton: .default(Text(info.primaryTitle)) {
                         info.onDismiss?()
                     })
    }

    /// 파이썬 앱과 같은 단축키(F2·R·U·Space·D·H·A·Esc)를 그대로 받는다.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 게임 창이 키 창일 때만 게임 단축키를 처리한다.
            // 설정·전적·디버그 창에서 Space/H/A 같은 키가 뒤의 판을 건드리지 않게 한다.
            guard NSApp.keyWindow?.title.hasPrefix("P-Solitaire —") == true else { return event }
            let handled = controller.handleKey(characters: event.characters,
                                               keyCode: event.keyCode,
                                               modifiers: event.modifierFlags)
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func openDebugWindow() {
        if let debugWindow {
            debugWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 310, height: 230),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "디버그 패널"
        window.level = .floating
        window.contentView = NSHostingView(rootView: DebugPanelView(controller: controller))
        window.isReleasedWhenClosed = false
        let delegate = DebugWindowDelegate { [weak controller] in
            controller?.showDebugPanel = false
        }
        window.delegate = delegate
        window.center()
        window.makeKeyAndOrderFront(nil)
        debugWindow = window
        debugDelegate = delegate
    }

    private func closeDebugWindow() {
        guard let window = debugWindow else {
            debugDelegate = nil
            return
        }
        debugWindow = nil
        debugDelegate = nil
        window.delegate = nil
        window.close()
    }
}

// MARK: - 카드 판

struct BoardCanvas: View {
    @ObservedObject var controller: GameController

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let game = controller.game
            let layout = controller.layout
            let theme = controller.tableTheme

            // 아주 옅은 대각선 그늘을 깔아 평평한 색면보다 탁자처럼 보이게 한다.
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(
                        Gradient(colors: [.clear, .black.opacity(0.16)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)))

            drawSlots(&ctx, game: game, layout: layout, theme: theme)
            drawStock(&ctx, game: game, layout: layout)
            drawPiles(&ctx, game: game, layout: layout, skipDragged: true)
            if let drag = controller.drag {                      // 집은 카드는 맨 위에
                for card in drag.cards {
                    if let origin = draggedOrigin(card, drag: drag) {
                        drawRaisedCard(&ctx, card: card, origin: origin)
                    }
                }
            }
            for flight in controller.flights {
                drawRaisedCard(&ctx, card: flight.card,
                               origin: controller.flightPosition(flight))
            }
            if let target = controller.dropTarget, let spot = layout.slot(target.kind, target.index) {
                drawHighlight(&ctx, origin: spot)
            }
            drawFlashes(&ctx, layout: layout)
            for bounce in controller.bounceCards {               // 우승 연출
                drawRaisedCard(&ctx, card: bounce.card,
                               origin: CGPoint(x: bounce.x, y: bounce.y))
            }
        }
        .background(controller.tableTheme.bg)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if controller.pressActive {
                        controller.dragTo(value.location)
                    } else {
                        controller.press(at: value.location)
                    }
                }
                .onEnded { value in
                    controller.release(at: value.location)
                }
        )
        .onHover { inside in
            if inside { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(controller.gameLabel) 카드판")
        .accessibilityValue("점수 \(controller.game.score), 이동 \(controller.game.moves)회")
        .accessibilityHint("카드를 끌어서 옮기거나, 스톡을 눌러 카드를 넘깁니다.")
    }

    /// 끌고 있거나 날아가는 카드는 그림자로 띄워 보인다.
    private func drawRaisedCard(_ ctx: inout GraphicsContext, card: Card, origin: CGPoint) {
        drawCardFaceShadow(&ctx, card: card, origin: origin, radius: 5, opacity: 0.38, y: 3)
    }

    private func drawCardFaceShadow(_ ctx: inout GraphicsContext, card: Card, origin: CGPoint,
                                    radius: CGFloat, opacity: Double, y: CGFloat) {
        // 그림자는 카드 전체 실루엣에만 준다. drawCardFace를 그대로 레이어에 넣으면
        // 카드 안의 하트 핍 하나하나에도 그림자가 생겨, 핍 주위에 동그란 테두리처럼 보인다.
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(opacity), radius: radius, x: 0, y: y))
            layer.fill(cardPath(origin), with: .color(.white))
        }
        drawCardFace(&ctx, card: card, origin: origin)
    }

    private func draggedOrigin(_ card: Card, drag: DragState) -> CGPoint? {
        guard let base = controller.layout.point(card) else { return nil }
        return CGPoint(x: base.x + drag.delta.width, y: base.y + drag.delta.height)
    }

    private func isDragged(_ card: Card) -> Bool {
        controller.drag?.cards.contains { $0 === card } ?? false
    }

    // ── 빈 자리 ───────────────────────────────────────────────────────────
    private func drawSlots(_ ctx: inout GraphicsContext, game: BaseGame,
                           layout: BoardLayout, theme: TableTheme) {
        for (ref, spot) in layout.slots {
            switch ref.kind {
            case .stock where !game.stock.isEmpty: continue
            case .waste where !game.waste.isEmpty: continue
            case .freecell where !(game.freecells[safe: ref.index]?.isEmpty ?? true): continue
            case .foundation where foundationCard(game, ref.index) != nil: continue
            case .tableau where !(game.tableau[safe: ref.index]?.isEmpty ?? true): continue
            default: break
            }
            drawSlot(&ctx, origin: spot, theme: theme)
        }
    }

    // ── 스톡(뒷면 더미) ───────────────────────────────────────────────────
    private func drawStock(_ ctx: inout GraphicsContext, game: BaseGame, layout: BoardLayout) {
        guard game.hasStock, !game.stock.isEmpty,
              let spot = layout.slot(.stock, 0) else { return }
        for k in stride(from: 2, through: 0, by: -1) {
            drawCardBack(&ctx, origin: CGPoint(x: spot.x + CGFloat(k) * 2, y: spot.y + CGFloat(k) * 2),
                         style: controller.backKey, theme: controller.backTheme)
        }
        if controller.variant == .spider, let spider = game as? Spider {   // 남은 배분 횟수
            ctx.draw(Text("\(spider.dealsLeft())").font(DrawFonts.statusBold)
                        .foregroundStyle(.white),
                     at: CGPoint(x: spot.x + Metrics.cardW - 6, y: spot.y + 6), anchor: .topTrailing)
        }
    }

    // ── 웨이스트·프리셀·파운데이션·태블로 ──────────────────────────────────
    private func drawPiles(_ ctx: inout GraphicsContext, game: BaseGame,
                           layout: BoardLayout, skipDragged: Bool) {
        func draw(_ card: Card) {
            guard let spot = layout.point(card) else { return }
            if skipDragged && isDragged(card) { return }
            if controller.isFlying(card) { return }
            if card.faceup {
                // 쉬는 카드는 그림자 없이 평평하게 그린다. 위 카드에 옅은 그림자를
                // 두르면 집지 않았는데도 집은 것처럼(둥근 테두리처럼) 보인다.
                drawCardFace(&ctx, card: card, origin: spot)
            } else {
                drawCardBack(&ctx, origin: spot, style: controller.backKey,
                             theme: controller.backTheme)
            }
        }

        if game.hasWaste {
            let drawCount = (game as? Klondike)?.drawCount ?? 3
            let visible = game.kind == .klondike ? (drawCount == 3 ? 3 : 1) : 1
            let shown = game.waste.suffix(visible)
            for card in shown {
                draw(card)
            }
        }
        for cell in game.freecells {
            if let card = cell.last { draw(card) }
        }
        for fi in 0..<game.foundationsCount {
            if let card = foundationCard(game, fi) { draw(card) }
        }
        for pile in game.tableau {
            for card in pile {
                draw(card)
            }
        }
    }

    // ── 힌트 깜빡임 ───────────────────────────────────────────────────────
    private func drawFlashes(_ ctx: inout GraphicsContext, layout: BoardLayout) {
        guard controller.flashOn else { return }
        for identifier in controller.flashCards {
            for card in allCards() where ObjectIdentifier(card) == identifier {
                if let spot = layout.point(card) { drawHighlight(&ctx, origin: spot) }
            }
        }
        for ref in controller.flashSlots {
            if let spot = layout.slot(ref.kind, ref.index) { drawHighlight(&ctx, origin: spot) }
        }
    }

    private func allCards() -> [Card] {
        let game = controller.game
        var cards: [Card] = []
        cards += game.stock
        cards += game.waste
        cards += game.freecells.flatMap { $0 }
        cards += game.foundations.flatMap { $0 }
        cards += game.tableau.flatMap { $0 }
        return cards
    }
}

// MARK: - 게임 조작 버튼

/// 보드 아래 버튼 줄. 메뉴·단축키와 같은 GameController 메서드를 부른다.
struct GameControlBar: View {
    @ObservedObject var controller: GameController

    var body: some View {
        HStack(spacing: 7) {
            ControlBarButton(title: "새 게임", symbol: "plus.rectangle.on.rectangle",
                             help: "새 게임 (⌘N)") {
                controller.requestNewGame()
            }
            .disabled(controller.preparingDeal)

            ControlBarButton(title: "취소", symbol: "arrow.uturn.backward",
                             help: "실행 취소 (⌘Z)") {
                controller.undo()
            }
            .disabled(!controller.game.canUndo || controller.busy)

            ControlBarButton(title: "힌트", symbol: "lightbulb",
                             help: "힌트 (⇧⌘H)") {
                controller.showHint()
            }
            .disabled(controller.busy)

            Spacer(minLength: 8)

            zoomGroup
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(controller.tableTheme.statusBg)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("게임 조작 버튼")
    }

    private var zoomGroup: some View {
        HStack(spacing: 2) {
            ControlBarButton(symbol: "minus", help: "축소 (⌘−)", width: 30) {
                controller.zoomOut()
            }
            .disabled(controller.preferredZoomPct <= GameController.zoomLevels.first!)

            ControlBarButton(title: "\(controller.zoomPct)%", symbol: "magnifyingglass",
                             help: "100%로 보기 (⌘0)", width: 80) {
                controller.zoomReset()
            }

            ControlBarButton(symbol: "plus", help: "확대 (⌘=)", width: 30) {
                controller.zoomIn()
            }
            .disabled(controller.preferredZoomPct >= GameController.zoomLevels.last!)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("확대 조절")
    }
}

/// 버튼 줄에 쓰는 작은 버튼(테마 색 위에서도 읽히게 반투명 흰 바탕).
private struct ControlBarButton: View {
    var title: String?
    let symbol: String
    let help: String
    var width: CGFloat?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: title == nil ? 0 : 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Palette.controlFG.opacity(isEnabled ? 1 : 0.38))
            .padding(.horizontal, title == nil ? 0 : 10)
            .frame(width: width, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? (hovering ? 0.22 : 0.12) : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.28 : 0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(title ?? help)
        .accessibilityHint(help)
    }
}

// MARK: - 상태바

struct StatusBarView: View {
    @ObservedObject var controller: GameController

    var body: some View {
        HStack(spacing: 8) {
            Text(controller.statusLeft)
                .font(DrawFonts.statusBold)
                .monospacedDigit()
                .foregroundStyle(Palette.statusFG)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 8)
            Text(controller.statusRight)
                .font(DrawFonts.status)
                .monospacedDigit()
                .foregroundStyle(controller.showNotice ? Palette.noticeFG : Palette.statusFGDim)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(controller.tableTheme.statusBg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("상태: \(controller.statusLeft). \(controller.statusRight)")
    }
}

// MARK: - 디버그 패널

struct DebugPanelView: View {
    @ObservedObject var controller: GameController
    @State private var memoryMB: Double = 0
    @State private var errorCount = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("디버그 패널")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.panelHead)
            row("게임", "\(controller.gameLabel)")
            row("카드", "\(controller.game.sortedCards())/\(controller.cardsInPlay)장 정리")
            row("다시 그리기", String(format: "%.1f ms", controller.lastDrawMS))
            row("메모리", String(format: "%.0f MB", memoryMB))
            row("오류", "\(errorCount)건")
            HStack {
                Button("오류 초기화") {
                    Logger.shared.resetErrors()
                    errorCount = 0
                }
                Button("닫기") { controller.showDebugPanel = false }
                Spacer()
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(12)
        .frame(width: 310, height: 230, alignment: .topLeading)
        .background(Palette.panelBG)
        .onAppear { startRefresh() }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func row(_ head: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(head).font(DrawFonts.status).foregroundStyle(Palette.panelHead)
                .frame(width: 84, alignment: .leading)
            Text(value).font(DrawFonts.status).foregroundStyle(Palette.panelFG)
            Spacer()
        }
    }

    private func startRefresh() {
        guard timer == nil else { return }
        errorCount = Logger.shared.errorCount
        memoryMB = controller.residentMemoryMB()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                memoryMB = controller.residentMemoryMB()
                errorCount = Logger.shared.errorCount
            }
        }
    }
}

// MARK: - 안전한 배열 접근

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
