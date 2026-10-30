// SelfTest.swift — 창을 띄우지 않고 화면 계층을 검증한다(Python 의 test_ui.py 상당).
//
// 실행:  swift run PSolitaire --selftest        (검사만 하고 끝난다)
//        swift run PSolitaire --shots <폴더>    (게임·테마별 PNG + 전적 창을 그려 저장)
//
// 사용자가 게임 중일 때 창을 띄우면 포커스를 빼앗으므로, 모든 검사는 창 없이 돈다.

import SwiftUI
import AppKit
import PSolitaireKit

@MainActor
enum SelfTest {
    private static var passed = 0
    private static var failed = 0
    private static var failures: [String] = []

    // MARK: - 진입

    static func run(_ args: [String]) -> Int32 {
        // 실제 전적 파일을 건드리지 않도록 임시 경로를 쓴다.
        let temp = NSTemporaryDirectory() + "psolitaire-selftest-\(UUID().uuidString).json"
        GameController.statsPathOverride = temp
        defer {
            try? FileManager.default.removeItem(atPath: temp)
            GameController.statsPathOverride = nil
        }

        if let index = args.firstIndex(of: "--shots") {
            let dir = index + 1 < args.count ? args[index + 1] : NSTemporaryDirectory()
            return renderShots(to: dir)
        }

        print("P-Solitaire — 자체 검사 시작")
        checkLayouts()
        checkHitTest()
        checkDragMove()
        checkBuriedCard()
        checkStockKlondike()
        checkStockSpider()
        checkWinnableDeal()
        checkWinnableGameFlow()
        checkUndo()
        checkRedo()
        checkResume()
        checkPlayedCounting()
        checkZoom()
        checkWasteFanHit()
        checkSeedEntry()
        checkConfirmDiscard()
        checkNoMoveHint()
        checkHintSearch()
        checkAutoCollect()
        checkDoubleClick()
        checkAutoCompleteGate()
        checkWinFlow()
        checkSettingsNormalize()
        checkThemeSwitch()
        checkMusicSettings()
        checkControlBar()
        checkStatsRender()
        checkRenderPixels()
        checkCardShadow()
        checkRestingCardShadow()

        print("")
        if failures.isEmpty {
            print("검사 \(passed)/\(passed) 통과")
            return 0
        }
        for line in failures { print("실패: \(line)") }
        print("검사 \(passed)/\(passed + failed) 통과 · 실패 \(failed)")
        return 1
    }

    // MARK: - 검사 도우미

    private static func expect(_ condition: Bool, _ name: String, _ detail: String = "") {
        if condition {
            passed += 1
        } else {
            failed += 1
            failures.append("\(name)\(detail.isEmpty ? "" : " — " + detail)")
        }
    }

    private static func controller(_ kind: GameKind, suits: Int = 2) -> GameController {
        // 자체 검사는 창 없이 바로 판을 검사하므로 풀리는 판 생성(백그라운드)은 끈다.
        let settings: [String: Any] = ["variant": kind.rawValue, "draw_count": 1,
                                       "spider_suits": suits, "spider_group": "same_suit",
                                       "spider_winnable": false,
                                       "theme": defaultTheme, "auto": defaultAuto]
        GameController.writeSettingsForTest(settings)
        let c = GameController()
        c.switchGame(kind)
        return c
    }

    // MARK: - 1. 배치

    private static func checkLayouts() {
        let expected: [GameKind: CGFloat] = [.klondike: 674, .freecell: 767, .spider: 953]
        for kind in GameKind.allCases {
            let c = controller(kind)
            let width = c.windowWidth
            expect(width == expected[kind]!, "\(kind.nameKo) 창 너비", "\(width)")
            expect(Metrics.windowH == 620, "\(kind.nameKo) 창 높이", "\(Metrics.windowH)")
            var outside = 0
            for card in allCards(c.game) {
                guard let spot = c.layout.point(card) else { continue }
                if spot.x < 0 || spot.x + Metrics.cardW > width
                    || spot.y < 0 || spot.y + Metrics.cardH > Metrics.windowH - Metrics.statusH - Metrics.controlH {
                    outside += 1
                }
            }
            expect(outside == 0, "\(kind.nameKo) 카드가 창 안에 있음", "밖 \(outside)장")
            let missing = c.game.tableau.flatMap { $0 }.filter { c.layout.point($0) == nil }.count
                + c.game.freecells.flatMap { $0 }.filter { c.layout.point($0) == nil }.count
            expect(missing == 0, "\(kind.nameKo) 모든 카드에 자리 있음", "빠짐 \(missing)장")
        }
    }

    // MARK: - 2. 누른 자리 찾기

    private static func checkHitTest() {
        for kind in GameKind.allCases {
            let c = controller(kind)
            var ok = 0
            for ti in 0..<c.game.columns {
                guard let card = c.game.tableau[ti].last, let spot = c.layout.point(card) else { continue }
                let hit = hitTest(c.game, c.layout,
                                  at: CGPoint(x: spot.x + 20, y: spot.y + 8))
                if let hit, hit.card === card, hit.kind == .tableau, hit.index == c.game.tableau[ti].count - 1 {
                    ok += 1
                }
            }
            expect(ok == c.game.columns, "\(kind.nameKo) 열마다 맨 위 카드 찾기", "\(ok)/\(c.game.columns)")
        }
    }

    // MARK: - 3. 끌어서 옮기기

    private static func checkDragMove() {
        let c = controller(.klondike)
        let king = Card(rank: 13, suit: .spades, faceup: true)
        let queen = Card(rank: 12, suit: .hearts, faceup: true)
        let eight = Card(rank: 8, suit: .clubs, faceup: true)
        c.game.tableau[0] = [king]
        c.game.tableau[1] = [eight, queen]
        c.redraw()

        guard let from = c.layout.point(queen), let to = c.layout.slot(.tableau, 0) else {
            expect(false, "끌어서 옮기기 준비"); return
        }
        c.press(at: CGPoint(x: from.x + 10, y: from.y + 10))
        expect(c.drag?.cards.count == 1, "Q♥ 한 장 집기")
        c.dragTo(CGPoint(x: to.x + 10, y: to.y + 10))
        expect(c.dropTarget == Ref(.tableau, 0), "놓을 자리 찾기")
        c.release(at: CGPoint(x: to.x + 10, y: to.y + 10))
        expect(c.game.tableau[0].count == 2, "K♠ 위에 Q♥ 놓기")
        expect(c.drag == nil, "드래그 상태 정리")
        expect(c.flights.isEmpty, "직접 끌어 옮긴 뒤 비행 연출 없음")

        // 규칙에 맞지 않는 자리에서는 손을 떼도 그대로 있어야 한다
        let before = c.game.tableau[1].count
        c.press(at: CGPoint(x: to.x + 10, y: to.y + 10))
        c.dragTo(CGPoint(x: to.x + 300, y: to.y + 10))
        c.release(at: CGPoint(x: to.x + 300, y: to.y + 10))
        expect(c.game.tableau[1].count == before, "잘못 놓으면 제자리")
    }

    // MARK: - 3-2. 덮인 카드는 집을 수 없다(MS 규칙)

    private static func checkBuriedCard() {
        let c = controller(.spider)                    // 기본은 같은 무늬 묶음 규칙
        let buried = Card(rank: 9, suit: .spades, faceup: true)
        let top = Card(rank: 8, suit: .hearts, faceup: true)
        c.game.tableau[0] = [buried, top]
        c.game.tableau[1] = [Card(rank: 10, suit: .hearts, faceup: true)]
        c.redraw()
        c.restoreHint()

        guard let at = c.layout.point(buried), let topSpot = c.layout.point(top) else {
            expect(false, "덮인 카드 자리 찾기"); return
        }
        let point = CGPoint(x: at.x + 10, y: at.y + 10)
        c.press(at: point)
        expect(c.drag == nil, "덮인 9♠ 는 집히지 않는다")
        expect(c.statusRight.contains("무늬가 다르면"), "못 집는 이유 안내", c.statusRight)
        c.release(at: point)
        expect(c.game.tableau[0].count == 2, "판은 그대로")

        // 맨 위 카드는 그대로 집을 수 있다
        let topPoint = CGPoint(x: topSpot.x + 10, y: topSpot.y + 10)
        c.press(at: topPoint)
        expect(c.drag?.cards.count == 1, "맨 위 8♥ 는 집힌다")
        c.release(at: topPoint)
        expect(c.game.tableau[0].count == 2, "제자리에 놓으면 그대로")
    }

    // MARK: - 4. 스톡(클론다이크)

    private static func checkStockKlondike() {
        let c = controller(.klondike)
        c.setAuto(.collect, on: false)             // 자동 올리기가 끼어들지 않게 한다
        c.setDrawCount(1)
        let stockBefore = c.game.stock.count
        c.clickStock()
        expect(c.game.stock.count == stockBefore - 1, "1장 넘기기")
        expect(c.game.waste.count == 1, "웨이스트 1장")

        c.setDrawCount(3)
        c.clickStock()
        expect(c.game.waste.count == 4, "3장 넘기기")

        // 스톡을 비우고 한 번 더 누르면 웨이스트를 재활용한다(3장 모드 -100점)
        while !c.game.stock.isEmpty { c.clickStock() }
        let score = c.game.score
        c.clickStock()
        expect(c.game.waste.isEmpty && !c.game.stock.isEmpty, "웨이스트 재활용")
        expect(c.game.score == score - 100, "재활용 -100점", "\(c.game.score - score)")
    }

    // MARK: - 5. 스톡(스파이더: 10장 돌리기)

    private static func checkStockSpider() {
        let c = controller(.spider)
        let before = c.game.stock.count
        c.clickStock()
        expect(c.game.stock.count == before - 10, "스톡 10장 돌리기")
        expect(c.game.tableau.allSatisfy { $0.count == 7 || $0.count == 6 }, "열마다 한 장씩")

        // 빈 열이 있으면 돌릴 수 없다
        let c2 = controller(.spider)
        c2.game.tableau[3] = []
        c2.redraw()
        let stock = c2.game.stock.count
        c2.clickStock()
        expect(c2.game.stock.count == stock, "빈 열이면 못 돌림")
        expect(c2.statusRight.contains("빈 열"), "이유 안내", c2.statusRight)
    }

    // MARK: - 5-1. 풀리는 스파이더 판

    private static func checkWinnableDeal() {
        for suits in [1, 2, 4] {
            let deal = SpiderWinnable.makeDeal(suits: suits, startingSeed: 1000,
                                               attempts: 1, timeLimit: 3.0,
                                               nodeLimit: 600_000)
            expect(deal != nil, "풀리는 판: \(suits)무늬 생성")
            guard let deal else { continue }
            expect(deal.suits == suits, "풀리는 판: \(suits)무늬 유지", "\(deal.suits)")
            expect(!deal.solution.isEmpty, "풀리는 판: 해답 있음")

            let counts = Dictionary(grouping: deal.tableau.flatMap { $0 } + deal.stock,
                                    by: { $0.suit })
            expect(counts.count == suits, "풀리는 판: 무늬 가짓수", "\(counts.count)")

            let game = Spider(seed: deal.sourceSeed, suits: deal.suits)
            game.applyDeal(deal)
            let before = layoutKey(game)
            var valid = true
            for move in deal.solution {
                switch move {
                case .deal:
                    valid = game.drawFromStock().ok && valid
                case .move(let src, let index, let dst):
                    valid = game.move(Ref(.tableau, src), index: index, Ref(.tableau, dst)).ok && valid
                }
            }
            expect(valid, "풀리는 판: \(suits)무늬 해답이 규칙에 맞음")
            expect(game.isWon(), "풀리는 판: \(suits)무늬 해답으로 이김")
            expect(game.startLayout != nil, "풀리는 판: 시작 배치 기억")

            // 같은 판 다시 시작해도 풀리는 판 그대로여야 한다.
            game.moves = 1
            game.restart()
            expect(layoutKey(game) == before, "풀리는 판: 다시 시작해도 같은 배치")
        }
    }

    /// 해답 한 수를 화면 힌트로 바꾼다(힌트가 해답 그대로인지 비교할 때 쓴다).
    private static func solutionHint(_ move: SpiderSolutionMove) -> Hint? {
        switch move {
        case .deal:
            return .draw
        case .move(let src, let index, let dst):
            return .move(src: Ref(.tableau, src), index: index, dst: Ref(.tableau, dst))
        }
    }

    /// 새 게임 흐름: 백그라운드에서 풀리는 판을 만들고 화면 상태가 풀리는지.
    private static func checkWinnableGameFlow() {
        let settings: [String: Any] = ["variant": GameKind.klondike.rawValue,
                                       "draw_count": 1, "spider_suits": 1,
                                       "spider_group": "same_suit", "spider_winnable": true,
                                       "theme": defaultTheme, "auto": defaultAuto]
        GameController.writeSettingsForTest(settings)
        let c = GameController()
        c.switchGame(.spider)
        expect(c.preparingDeal, "풀리는 판 흐름: 만드는 중 표시")

        // 디버그 빌드는 솔버가 느려 재시도가 겹치면 오래 걸릴 수 있다(실제 앱은 릴리스).
        let deadline = Date().addingTimeInterval(45)
        while c.preparingDeal && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(!c.preparingDeal, "풀리는 판 흐름: 생성 완료")
        guard let spider = c.game as? Spider else {
            expect(false, "풀리는 판 흐름: 스파이더 판"); return
        }
        expect(spider.seed > 0, "풀리는 판 흐름: 판 번호 있음", "\(spider.seed)")
        expect(spider.startLayout != nil, "풀리는 판 흐름: 시작 배치 기억")
        let now = spider.tableau.map { pile in
            pile.map { "\($0.suit.rawValue)-\($0.rank)-\($0.faceup ? 1 : 0)" }
                .joined(separator: ",")
        }
        let start = spider.startLayout?.tableau.map { pile in
            pile.map { "\($0.suit.rawValue)-\($0.rank)-\($0.faceup ? 1 : 0)" }
                .joined(separator: ",")
        }
        expect(now == start, "풀리는 판 흐름: 시작 배치와 현재 배치가 같음")
        expect(spider.tableau.map(\.count) == [6, 6, 6, 6, 5, 5, 5, 5, 5, 5],
               "풀리는 판 흐름: 표준 배분")

        // 배분할 때 찾은 해답이 시작 배치에 남고, 힌트가 그 첫 수를 그대로 안내한다.
        guard let solution = spider.startLayout?.solution, !solution.isEmpty else {
            expect(false, "풀리는 판 흐름: 해답 기억"); return
        }
        expect(spider.planHint() == solutionHint(solution[0]),
               "풀리는 판 흐름: 힌트 = 해답 첫 수")
        switch solution[0] {
        case .deal:
            _ = spider.drawFromStock()
        case .move(let src, let index, let dst):
            _ = spider.move(Ref(.tableau, src), index: index, Ref(.tableau, dst))
        }
        if solution.count > 1 {
            expect(spider.planHint() == solutionHint(solution[1]),
                   "풀리는 판 흐름: 한 수 뒤 힌트 = 해답 다음 수")
        }
        spider.restart()

        // 이어하기: 풀리는 판의 시작 배치까지 파일에 남아 다시 시작해도 유지된다.
        c.saveCurrentGame()
        let savedKey = layoutKey(c.game)
        let again = GameController()
        expect(again.variant == .spider, "풀리는 판 흐름: 이어하기 게임 종류")
        expect(layoutKey(again.game) == savedKey, "풀리는 판 흐름: 이어하기 배치")
        guard let resumed = again.game as? Spider else {
            expect(false, "풀리는 판 흐름: 이어하기 스파이더 판"); return
        }
        expect(resumed.startLayout != nil, "풀리는 판 흐름: 이어하기 시작 배치")
        again.game.moves = 3
        again.game.restart()
        expect(layoutKey(again.game) == savedKey, "풀리는 판 흐름: 이어하기 뒤 다시 시작")
    }

    // MARK: - 6. 실행 취소

    private static func checkUndo() {
        let c = controller(.klondike)
        c.setAuto(.collect, on: false)             // 자동 올리기가 끼어들지 않게 한다
        c.setAuto(.finish, on: false)
        let snapshot = layoutKey(c.game)
        c.clickStock()
        expect(c.game.canUndo, "실행 취소 기록 있음")
        c.undo()
        expect(layoutKey(c.game) == snapshot, "실행 취소가 판을 되돌림")
    }

    // MARK: - 6-2. 실행 복귀(리두)

    private static func checkRedo() {
        let c = controller(.klondike)
        c.setAuto(.collect, on: false)
        let before = layoutKey(c.game)
        c.clickStock()
        expect(c.game.canUndo, "리두: 되돌릴 기록 있음")
        c.undo()
        expect(layoutKey(c.game) == before, "리두: 되돌리기")
        expect(c.game.canRedo, "리두: 다시 실행할 기록 있음")
        c.redo()
        expect(layoutKey(c.game) != before, "리두: 다시 실행")
        expect(c.game.waste.count == c.drawCount, "리두: 넘긴 카드 복원")
    }

    // MARK: - 6-3. 이어하기(진행 중인 판 저장/복원)

    private static func checkResume() {
        let c = controller(.klondike)
        c.setAuto(.collect, on: false)
        c.setAuto(.finish, on: false)
        c.setDrawCount(1)
        c.clickStock()
        let seed = c.game.seed
        let moves = c.game.moves
        let key = layoutKey(c.game)
        c.saveCurrentGame()

        let again = GameController()
        expect(again.variant == .klondike, "이어하기: 게임 종류", again.variant.rawValue)
        expect(again.game.seed == seed, "이어하기: 판 번호", "\(again.game.seed)")
        expect(again.game.moves == moves, "이어하기: 이동 수", "\(again.game.moves)")
        expect(layoutKey(again.game) == key, "이어하기: 판 배치")
        expect(!again.game.canUndo, "이어하기: 이전 실행 취소 기록은 없음")
        expect(again.elapsedSeconds() >= 0, "이어하기: 시간 복원")
    }

    // MARK: - 6-4. 판 수는 첫 수를 둘 때만 센다

    private static func checkPlayedCounting() {
        let c = controller(.klondike)
        let start = c.record(for: .klondike).played
        c.newGame()
        expect(c.record(for: .klondike).played == start, "판 수: 새 게임만으로는 늘지 않음",
               "\(c.record(for: .klondike).played)")
        c.clickStock()
        expect(c.record(for: .klondike).played == start + 1, "판 수: 첫 수 뒤 +1",
               "\(c.record(for: .klondike).played)")
        c.restartGame()
        expect(c.record(for: .klondike).played == start + 1, "판 수: 다시 시작만으로는 늘지 않음")
    }

    // MARK: - 6-5. 확대/축소

    private static func checkZoom() {
        let c = controller(.klondike)
        c.setZoom(200)
        expect(c.preferredZoomPct == 200, "확대: 설정값 저장", "\(c.preferredZoomPct)")
        expect(c.zoomPct >= 100 && c.zoomPct <= 200, "확대: 화면 안 단계", "\(c.zoomPct)")
        c.zoomReset()
        expect(c.zoomPct == 100, "확대: 100%로", "\(c.zoomPct)")
        let fixed = GameController.normalize(["zoom": 999])
        expect(fixed["zoom"] as? Int == 200, "확대: 이상한 값은 200%로")
    }

    // MARK: - 6-6. 웨이스트 부채꼴 클릭

    private static func checkWasteFanHit() {
        let c = controller(.klondike)
        c.setAuto(.collect, on: false)
        c.setDrawCount(3)
        c.clickStock()
        c.clickStock()
        guard c.game.waste.count >= 3 else {
            expect(false, "웨이스트 부채꼴 준비"); return
        }
        let firstVisible = c.game.waste[c.game.waste.count - 3]
        guard let spot = c.layout.point(firstVisible) else {
            expect(false, "웨이스트 부채꼴 자리"); return
        }
        let hit = hitTest(c.game, c.layout, at: CGPoint(x: spot.x + 5, y: spot.y + 8))
        expect(hit?.kind == .waste, "웨이스트 부채꼴 클릭: 더미 인식")
        expect(hit?.index == c.game.waste.count - 1, "웨이스트 부채꼴 클릭: 맨 위 카드")
        expect(hit?.card === c.game.waste.last, "웨이스트 부채꼴 클릭: 맨 위 카드 참조")
    }

    // MARK: - 6-7. 판 번호

    private static func checkSeedEntry() {
        let c = controller(.klondike)
        c.startGame(withSeedText: "424242")
        expect(c.game.seed == 424242, "판 번호: 새 게임 시드", "\(c.game.seed)")
        expect(c.windowTitle.contains("#424242"), "판 번호: 제목 표시", c.windowTitle)
        c.startGame(withSeedText: "숫자아님")
        expect(c.alert?.title == "판 번호", "판 번호: 잘못된 입력 안내")
        c.alert = nil
    }

    // MARK: - 6-8. 진행 중인 판 버리기 확인

    private static func checkConfirmDiscard() {
        let c = controller(.klondike)
        c.setAuto(.collect, on: false)
        c.clickStock()
        expect(c.game.moves == 1, "확인: 이동 한 번")
        c.requestNewGame()
        expect(c.confirm != nil, "확인: 진행 중이면 확인 창")
        c.confirm?.action()
        expect(c.confirm == nil, "확인: 확인 뒤 닫힘")
        expect(c.game.moves == 0, "확인: 새 게임 시작")
    }

    // MARK: - 6-9. 둘 수 있는 수 없음

    private static func checkNoMoveHint() {
        let c = controller(.freecell)
        c.clearBoard()
        c.redraw()
        c.afterMove()
        expect(c.statusRight.contains("둘 수 있는 수가 없습니다"),
               "둘 수 있는 수 없음 안내", c.statusRight)
    }

    // MARK: - 6-1. 해답 힌트(비동기)

    /// 힌트는 백그라운드에서 해답을 찾고, 결과가 돌아오면 카드·자리를 깜빡인다.
    private static func checkHintSearch() {
        let c = controller(.freecell)
        c.switchGame(.freecell, seed: 3)          // 해답을 빨리 찾는 판
        expect(c.game.seed == 3, "힌트 탐색: 판 고정", "\(c.game.seed)")
        c.showHint()
        expect(c.statusRight.contains("찾는 중"), "힌트 탐색: 찾는 중 안내", c.statusRight)
        let deadline = Date().addingTimeInterval(30)
        while c.flashCards.isEmpty && c.alert == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        expect(c.alert == nil, "힌트 탐색: 해답을 찾음")
        expect(!c.flashCards.isEmpty, "힌트 탐색: 카드 깜빡임")
        expect(c.statusRight.contains("첫 수"), "힌트 탐색: 해답 안내", c.statusRight)

        // 판이 바뀌면 진행 중이던 탐색 결과는 버린다.
        c.showHint()
        c.switchGame(.klondike)
        expect(c.statusRight == hintTextDefault, "힌트 탐색: 판이 바뀌면 안내 해제", c.statusRight)
    }

    // MARK: - 7. 자동 올리기

    private static func checkAutoCollect() {
        let c = controller(.klondike)
        c.clearBoard()                              // 판을 비우고 A♠ 한 장만 둔다
        c.game.tableau[0] = [Card(rank: 1, suit: .spades, faceup: true)]
        c.redraw()
        c.afterMove()
        expect(c.game.foundations[0].count == 1, "A♠ 자동 올리기",
               "foundations=\(c.game.foundations.map { $0.count })")
        expect(c.game.score == scoreToFoundation, "자동 올리기 +10점", "\(c.game.score)")

        let c2 = controller(.klondike)
        c2.setAuto(.collect, on: false)
        c2.clearBoard()
        c2.game.tableau[0] = [Card(rank: 1, suit: .hearts, faceup: true)]
        c2.redraw()
        c2.afterMove()
        expect(c2.game.foundations[0].isEmpty, "자동 올리기가 꺼져 있으면 안 올림")
    }

    // MARK: - 8. 더블클릭 자동 이동

    private static func checkDoubleClick() {
        let c = controller(.klondike)
        c.clearBoard()
        let ace = Card(rank: 1, suit: .hearts, faceup: true)
        c.game.tableau[2] = [Card(rank: 5, suit: .clubs, faceup: true), ace]
        c.redraw()
        guard let spot = c.layout.point(ace) else {
            expect(false, "더블클릭 준비"); return
        }
        let point = CGPoint(x: spot.x + 10, y: spot.y + 10)
        c.press(at: point); c.release(at: point)
        c.press(at: point); c.release(at: point)
        expect(c.game.foundations[0].count == 1, "더블클릭으로 A♥ 올리기",
               "foundations=\(c.game.foundations.map { $0.count })")

        // 자동 이동이 꺼져 있으면 안내만 나온다
        let c2 = controller(.klondike)
        c2.setAuto(.double, on: false)
        c2.clearBoard()
        let ace2 = Card(rank: 1, suit: .diamonds, faceup: true)
        c2.game.tableau[2] = [ace2]
        c2.redraw()
        guard let spot2 = c2.layout.point(ace2) else { return }
        let point2 = CGPoint(x: spot2.x + 10, y: spot2.y + 10)
        c2.press(at: point2); c2.release(at: point2)
        c2.press(at: point2); c2.release(at: point2)
        expect(c2.game.foundations[0].isEmpty, "꺼져 있으면 안 옮김")
        expect(c2.statusRight.contains("꺼져 있습니다"), "꺼짐 안내", c2.statusRight)
    }

    // MARK: - 9. 자동 완성 조건

    private static func checkAutoCompleteGate() {
        let c = controller(.klondike)
        expect(!c.game.canAutoComplete(), "처음에는 자동 완성 불가")
        c.startAutoComplete()
        expect(c.alert?.title == "자동 완성", "불가 안내 표시")
        expect(c.alert?.message.contains("뒤집힌 카드") == true, "이유 문구")
        c.alert = nil

        let spider = controller(.spider)
        spider.startAutoComplete()
        expect(spider.alert?.message.contains("스파이더") == true, "스파이더는 세트로 설명")
    }

    // MARK: - 10. 우승

    private static func checkWinFlow() {
        let c = controller(.klondike)
        c.clearBoard()
        for suit in Suit.allCases {
            let top = (suit == .spades) ? 12 : 13        // 스페이드는 K만 남겨 둔다
            c.game.foundations[suit.rawValue] = (1...top).map { Card(rank: $0, suit: suit) }
        }
        c.game.tableau[0] = [Card(rank: 13, suit: .spades, faceup: true)]
        c.redraw()
        c.startTimer()
        expect(c.game.sortedCards() == 51, "우승 직전 51장")
        let moved = c.game.move(Ref(.tableau, 0), index: 0, Ref(.foundation, 0))
        expect(moved.ok, "마지막 K♠ 올리기")
        c.afterMove()
        expect(c.game.isWon(), "우승 판정")
        expect(c.alert?.title == "우승", "우승 알림")
        let record = (c.stats["games"] as? [String: Any])?["klondike"] as? [String: Any]
        expect(((record?["won"] as? Int) ?? 0) >= 1, "전적에 승리 기록")
        expect(c.alert?.message.contains("시간 보너스") == true, "보너스 문구")
        c.alert = nil
    }

    // MARK: - 11. 설정 정리

    private static func checkSettingsNormalize() {
        let broken: [String: Any] = ["variant": "없는게임", "draw_count": 7, "spider_suits": 3,
                                     "spider_group": "이상함", "theme": ["background": "무지개"],
                                     "auto": ["double": false]]
        let fixed = GameController.normalize(broken)
        expect(fixed["variant"] as? String == "klondike", "이상한 게임 이름 → 클론다이크")
        expect(fixed["draw_count"] as? Int == 3, "이상한 장수 → 3")
        expect(fixed["spider_suits"] as? Int == 1, "이상한 무늬 수 → 1")
        expect(fixed["spider_group"] as? String == defaultSpiderGroup, "이상한 묶음 규칙 → 기본")
        expect(fixed["spider_winnable"] as? Bool == true, "풀리는 판 기본값 → 켬")
        var off = broken
        off["spider_winnable"] = false
        expect(GameController.normalize(off)["spider_winnable"] as? Bool == false,
               "풀리는 판 끔 유지")
        let theme = fixed["theme"] as? [String: String] ?? [:]
        expect(theme["background"] == "green", "이상한 배경 → 클래식 초록")
        let auto = fixed["auto"] as? [String: Bool] ?? [:]
        expect(auto["double"] == false, "꺼진 자동 기능은 그대로 둠")
        expect(auto["collect"] == true, "없던 자동 기능은 기본값")

        // 저장 → 읽기 왕복
        let c = controller(.spider)
        c.setTheme(background: "dark", back: "dots")
        c.setAuto(.finish, on: true)
        c.save()
        let again = GameController()
        expect(again.backgroundKey == "dark", "배경 저장됨", again.backgroundKey)
        expect(again.backKey == "dots", "카드 뒷면 저장됨", again.backKey)
        expect(again.autoOn(.finish), "자동 기능 저장됨")
        expect(again.variant == .spider, "게임 종류 저장됨")
    }

    // MARK: - 12. 테마

    private static func checkThemeSwitch() {
        let c = controller(.klondike)
        c.setTheme(background: "blue")
        expect(c.tableTheme.title == "파란 탁자", "배경 바꾸기", c.tableTheme.title)
        c.setTheme(back: "rays")
        expect(c.backTheme.title == "붉은 햇살", "카드 뒷면 바꾸기", c.backTheme.title)
        c.setSpiderGroup("any_suit")
        expect(c.spiderGroup == "any_suit", "스파이더 묶음 규칙 저장")
        c.switchGame(.spider)
        expect((c.game as? Spider)?.suitFree == true, "쉬움 규칙이 판에 반영")
    }

    // MARK: - 12-2. 배경음

    private static func checkMusicSettings() {
        expect(musicTracks.count == 5, "배경음 5곡", "\(musicTracks.count)")
        expect(Set(musicTracks.map { $0.id }).count == musicTracks.count, "곡 id 중복 없음")
        for track in musicTracks {
            expect(MusicPlayer.url(for: track.file) != nil, "음악 파일 있음: \(track.file)")
        }

        // 깨진 설정은 기본값으로, 볼륨은 0~1로 맞춘다.
        let broken: [String: Any] = ["music": ["on": "켬", "track": "없는 곡",
                                               "repeat": "가끔", "volume": 3.0]]
        let fixed = GameController.normalize(broken)
        let music = fixed["music"] as? [String: Any] ?? [:]
        expect(music["on"] as? Bool == MusicDefaults.on, "이상한 배경음 → 기본 켬")
        expect(music["track"] as? String == MusicDefaults.trackID, "없는 곡 → 첫 곡")
        expect(music["repeat"] as? String == MusicRepeatMode.all.rawValue,
               "이상한 반복 → 목록 반복")
        expect((music["volume"] as? NSNumber)?.doubleValue == 1.0, "볼륨 상한 1.0")
        let low = GameController.normalize(["music": ["volume": -2.0]])
        expect(((low["music"] as? [String: Any])?["volume"] as? NSNumber)?.doubleValue == 0,
               "볼륨 하한 0")

        // 저장 → 읽기 왕복
        let c = controller(.klondike)
        c.setMusicTrack("bossa_bossa")
        c.setMusicRepeat(.one)
        c.setMusicVolume(0.5)
        c.setMusic(on: false)
        c.save()
        let again = GameController()
        expect(again.musicTrackID == "bossa_bossa", "배경음 곡 저장됨", again.musicTrackID)
        expect(again.musicRepeatMode == .one, "배경음 반복 저장됨")
        expect(abs(again.musicVolume - 0.5) < 0.001, "배경음 볼륨 저장됨")
        expect(!again.musicOn, "배경음 끔 저장됨")

        // 목록 반복으로 다음 곡이 시작되면 선택값도 따라간다.
        again.musicDidAdvance(to: "night_in_venice")
        expect(again.musicTrackID == "night_in_venice", "목록 반복이 곡 선택을 따라감")
        again.setMusic(on: true)
        expect(!again.music.isPlaying, "자체 검사에서는 소리를 내지 않음")
        expect(MusicPlayer.isSuppressed, "검사 모드 소리 억제")
    }

    // MARK: - 12-3. 화면 조작 버튼

    private static func checkControlBar() {
        let c = controller(.klondike)
        guard let image = renderControlBar(c) else {
            expect(false, "조작 버튼 줄 렌더")
            return
        }
        expect(image.width == Int(c.windowWidth) * 2, "조작 버튼 줄 너비", "\(image.width)")
        expect(image.height == Int(Metrics.controlH) * 2, "조작 버튼 줄 높이",
               "\(image.height)")

        // 버튼이 부르는 메서드가 메뉴와 같은 경로로 동작하는지 확인한다.
        let oldSeed = c.game.seed
        c.requestNewGame()                    // 이동 0 → 확인 없이 바로 새 판
        expect(c.game.seed != oldSeed, "새 게임 버튼 → 새 배분", "\(c.game.seed)")
        expect(c.game.moves == 0, "새 게임은 이동 0에서 시작")
        expect(!c.game.canUndo, "새 판은 취소할 수 없음")
        expect(c.statusRight == hintTextDefault, "새 게임 뒤 기본 안내", c.statusRight)
        c.showHint()                          // 힌트 버튼 경로(대화상자/깜빡임)
        c.setZoom(100)
        c.zoomIn()
        expect(c.preferredZoomPct == 125, "확대 버튼 → 다음 배율", "\(c.preferredZoomPct)")
        c.zoomReset()
        expect(c.preferredZoomPct == 100, "100% 버튼 → 100%")
    }

    // MARK: - 13. 전적 창 렌더

    private static let sampleRecords = [
        GameRecord(kind: .klondike, played: 128, won: 42, bestTime: 126, bestScore: 1240),
        GameRecord(kind: .freecell, played: 76, won: 31, bestTime: 204, bestScore: 980),
        GameRecord(kind: .spider, played: 12, won: 1, bestTime: 731, bestScore: 450),
    ]

    private static func checkStatsRender() {
        guard let image = renderStats(sampleRecords, current: .klondike) else {
            expect(false, "전적 창 렌더")
            return
        }
        expect(image.width == 620 * 2, "전적 창 너비", "\(image.width)")
        expect(image.height > 200 * 2, "전적 창 높이", "\(image.height)")
    }

    // MARK: - 14. 오프스크린 렌더(창 없이 그림 확인)

    private static func checkRenderPixels() {
        for kind in GameKind.allCases {
            let c = controller(kind)
            for (background, expected) in [("green", "#008000"), ("blue", "#0f3f6e"),
                                           ("dark", "#232326")] {
                c.setTheme(background: background)
                c.redraw()
                guard let image = render(c, width: c.windowWidth,
                                         height: Metrics.windowH - Metrics.statusH - Metrics.controlH) else {
                    expect(false, "\(kind.nameKo)/\(background) 렌더"); continue
                }
                expect(image.width == Int(c.windowWidth) * 2 || image.width == Int(c.windowWidth),
                       "\(kind.nameKo)/\(background) 그림 크기", "\(image.width)")
                let pixel = pixelHex(color(of: image, at: CGPoint(x: 4, y: 4)))
                expect(colorsClose(pixel, expected), "\(kind.nameKo)/\(background) 배경색",
                       pixel + " (기대 \(expected))")

                guard let full = renderWindow(c) else {
                    expect(false, "\(kind.nameKo)/\(background) 전체 창 렌더"); continue
                }
                expect(full.width == Int(c.windowWidth) * 2
                        && full.height == Int(Metrics.windowH) * 2,
                       "\(kind.nameKo)/\(background) 전체 창 크기",
                       "\(full.width)x\(full.height)")
            }
        }
    }

    /// 카드를 집었을 때 그림자가 카드 안의 핍까지 번지지 않는지 확인한다.
    /// (예전에는 핍마다 그림자가 생겨 하트 주위에 동그란 테두리처럼 보였다.)
    private static func checkCardShadow() {
        let c = controller(.klondike)
        c.clearBoard()
        let card = Card(rank: 3, suit: .hearts, faceup: true)
        c.game.tableau[0] = [card]
        c.redraw()
        guard let origin = c.layout.point(card) else {
            expect(false, "카드 그림자 준비"); return
        }
        let boardH = Metrics.windowH - Metrics.statusH - Metrics.controlH
        let outside = CGPoint(x: origin.x + Metrics.cardW + 2,
                              y: origin.y + Metrics.cardH / 2)
        guard let resting = render(c, width: c.windowWidth, height: boardH) else {
            expect(false, "카드 그림자 렌더(쉼)"); return
        }
        let restHex = pixelHex(color(of: resting, at: outside))

        let point = CGPoint(x: origin.x + 10, y: origin.y + 10)
        c.press(at: point)
        c.dragTo(point)                         // 집은 카드(강한 그림자) 상태
        guard let image = render(c, width: c.windowWidth, height: boardH) else {
            expect(false, "카드 그림자 렌더"); return
        }
        // 3♥의 맨 위 핍 바로 위, 카드 안쪽 흰 영역.
        let sample = CGPoint(x: origin.x + Metrics.cardW / 2, y: origin.y + 15)
        let hex = pixelHex(color(of: image, at: sample))
        expect(colorsClose(hex, "#ffffff", tolerance: 4),
               "카드 그림자가 핍 안쪽을 어둡게 하지 않음", hex)
        // 집은 카드는 바깥에 그림자를 남기고, 쉬는 카드보다 확실히 어둡다.
        let dragHex = pixelHex(color(of: image, at: outside))
        expect(!colorsClose(dragHex, restHex, tolerance: 2),
               "집은 카드만 그림자로 띄워 보임", "집음 \(dragHex) · 쉼 \(restHex)")
    }

    /// 드래그하지 않은 카드는 그림자를 두르지 않는다.
    /// (위 카드에 늘 옅은 그림자가 생겨, 집지 않았는데도 집은 것처럼 보였다.)
    private static func checkRestingCardShadow() {
        let c = controller(.klondike)
        c.clearBoard()
        c.setTheme(background: "green")
        let card = Card(rank: 2, suit: .spades, faceup: true)
        c.game.tableau[0] = [card]
        c.redraw()
        guard let origin = c.layout.point(card) else {
            expect(false, "쉬는 카드 그림자 준비"); return
        }
        let boardH = Metrics.windowH - Metrics.statusH - Metrics.controlH
        // 카드 아래 4px 지점. 카드가 있으면 그림자가, 없으면 탁자색만 보여야 한다.
        let sample = CGPoint(x: origin.x + Metrics.cardW / 2,
                             y: origin.y + Metrics.cardH + 4)
        guard let withCard = render(c, width: c.windowWidth, height: boardH) else {
            expect(false, "쉬는 카드 그림자 렌더"); return
        }
        let lifted = pixelHex(color(of: withCard, at: sample))

        c.game.tableau[0] = []
        c.redraw()
        guard let without = render(c, width: c.windowWidth, height: boardH) else {
            expect(false, "빈 자리 그림자 렌더"); return
        }
        let flat = pixelHex(color(of: without, at: sample))
        expect(colorsClose(lifted, flat, tolerance: 2),
               "쉬는 카드는 그림자를 만들지 않음", "카드 \(lifted) · 빈 자리 \(flat)")
    }

    // MARK: - 그림 그리기(창 없이)

    static func render(_ controller: GameController, width: CGFloat, height: CGFloat) -> CGImage? {
        let view = BoardCanvas(controller: controller)
            .frame(width: width, height: height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 전적 창 내용을 창 없이 그린다(정렬 확인용).
    static func renderStats(_ records: [GameRecord], current: GameKind) -> CGImage? {
        let view = StatsContent(records: records,
                                currentKind: current,
                                statsPath: "~/.psolitaire-nat.json",
                                onReset: {})
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 보드 아래 조작 버튼 줄을 창 없이 그린다.
    static func renderControlBar(_ controller: GameController) -> CGImage? {
        let view = GameControlBar(controller: controller)
            .frame(width: controller.windowWidth, height: Metrics.controlH)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 상태바까지 포함한 실제 창 내용 전체를 그린다.
    static func renderWindow(_ controller: GameController) -> CGImage? {
        let view = VStack(spacing: 0) {
            BoardCanvas(controller: controller)
                .frame(width: controller.windowWidth,
                       height: controller.windowHeight - Metrics.controlH - Metrics.statusH)
            GameControlBar(controller: controller)
                .frame(height: Metrics.controlH)
            StatusBarView(controller: controller)
                .frame(height: Metrics.statusH)
        }
        .frame(width: controller.windowWidth, height: controller.windowHeight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 확대 배율을 적용한 창 내용(스케일 경계 확인용).
    static func renderWindow(_ controller: GameController, zoom: CGFloat) -> CGImage? {
        let view = VStack(spacing: 0) {
            BoardCanvas(controller: controller)
                .frame(width: controller.windowWidth,
                       height: controller.windowHeight - Metrics.controlH - Metrics.statusH)
            GameControlBar(controller: controller)
                .frame(height: Metrics.controlH)
            StatusBarView(controller: controller)
                .frame(height: Metrics.statusH)
        }
        .frame(width: controller.windowWidth, height: controller.windowHeight)
        .scaleEffect(zoom, anchor: .topLeading)
        .frame(width: controller.windowWidth * zoom,
               height: controller.windowHeight * zoom, alignment: .topLeading)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage
    }

    /// 색 공간 차이를 없앤 sRGB 비트맵(렌더 결과를 있는 그대로 본다).
    private static func srgbRep(_ image: CGImage) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: image.width,
                                         pixelsHigh: image.height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .calibratedRGB, bytesPerRow: 0,
                                         bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.cgContext.draw(image, in: CGRect(x: 0, y: 0,
                                                     width: image.width, height: image.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func color(of image: CGImage, at point: CGPoint) -> NSColor {
        guard let rep = srgbRep(image) else { return .black }
        let x = min(Int(point.x * 2), rep.pixelsWide - 1)
        let y = min(Int(point.y * 2), rep.pixelsHigh - 1)
        return rep.colorAt(x: x, y: y) ?? .black
    }

    private static func colorsClose(_ a: String, _ b: String, tolerance: Int = 4) -> Bool {
        func parts(_ hex: String) -> [Int] {
            let text = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            guard text.count == 6, let value = Int(text, radix: 16) else { return [0, 0, 0] }
            return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]
        }
        return zip(parts(a), parts(b)).allSatisfy { abs($0 - $1) <= tolerance }
    }

    private static func pixelHex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02x%02x%02x",
                      Int(rgb.redComponent * 255 + 0.5),
                      Int(rgb.greenComponent * 255 + 0.5),
                      Int(rgb.blueComponent * 255 + 0.5))
    }

    // MARK: - 게임·테마별 PNG 저장(눈으로 확인용)

    private static func renderShots(to dir: String) -> Int32 {
        let folder = (dir as NSString).expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        var saved = 0
        for kind in GameKind.allCases {
            for background in backgroundKeys {
                for back in backKeys {
                    let c = controller(kind)
                    c.setTheme(background: background, back: back)
                    c.redraw()
                    guard let image = render(c, width: c.windowWidth,
                                             height: Metrics.windowH - Metrics.statusH - Metrics.controlH),
                          let data = pngData(image) else { continue }
                    let name = "\(kind.rawValue)-\(background)-\(back).png"
                    try? data.write(to: URL(fileURLWithPath: folder + "/" + name))
                    saved += 1
                }
            }
        }

        // 상태바까지 포함한 창 전체와 150% 확대 모습.
        for kind in GameKind.allCases {
            for background in backgroundKeys {
                let c = controller(kind)
                c.setTheme(background: background)
                c.redraw()
                if let image = renderWindow(c), let data = pngData(image) {
                    let name = "full-\(kind.rawValue)-\(background).png"
                    try? data.write(to: URL(fileURLWithPath: folder + "/" + name))
                    saved += 1
                }
                if let image = renderWindow(c, zoom: 1.5), let data = pngData(image) {
                    let name = "zoom150-\(kind.rawValue)-\(background).png"
                    try? data.write(to: URL(fileURLWithPath: folder + "/" + name))
                    saved += 1
                }
            }
        }

        // 전적 창 정렬 확인용(실제 기록 대신 폭이 다른 예시 값).
        if let image = renderStats(sampleRecords, current: .klondike),
           let data = pngData(image) {
            try? data.write(to: URL(fileURLWithPath: folder + "/stats.png"))
            saved += 1
        }

        print("PNG \(saved)장 저장 → \(folder)")
        return saved > 0 ? 0 : 1
    }

    private static func pngData(_ image: CGImage) -> Data? {
        srgbRep(image)?.representation(using: .png, properties: [:])
    }

    // MARK: - 작은 도우미

    private static func allCards(_ game: BaseGame) -> [Card] {
        game.stock + game.waste + game.freecells.flatMap { $0 } + game.foundations.flatMap { $0 }
            + game.tableau.flatMap { $0 }
    }

    private static func layoutKey(_ game: BaseGame) -> String {
        var parts: [String] = []
        for pile in game.tableau {
            parts.append(pile.map { "\($0.suit.rawValue)-\($0.rank)-\($0.faceup ? 1 : 0)" }
                            .joined(separator: ","))
        }
        parts.append(game.stock.map { "\($0.suit.rawValue)-\($0.rank)" }.joined(separator: ","))
        parts.append(game.waste.map { "\($0.suit.rawValue)-\($0.rank)" }.joined(separator: ","))
        parts.append("score=\(game.score)")
        return parts.joined(separator: "|")
    }
}
