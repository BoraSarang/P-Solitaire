import XCTest
@testable import PSolitaireKit

/// 힌트 탐색기 검증 — 찾은 해답이 실제로 이기는지, 풀 수 없는 판을 구분하는지.
final class HintSolverTests: XCTestCase {
    private func play(_ game: BaseGame, _ hints: [Hint]) -> String? {
        for (n, hint) in hints.enumerated() {
            switch hint {
            case .move(let src, let index, let dst):
                if src == dst { return "\(n)번째 수가 같은 곳으로 이동" }
                let result = game.move(src, index: index, dst)
                if !result.ok { return "\(n)번째 수 실패: \(result.reason ?? "")" }
            case .draw, .recycle:
                if !game.drawFromStock().ok { return "\(n)번째 스톡 넘기기 실패" }
            }
        }
        return game.isWon() ? nil : "해답을 다 둬도 이기지 못함(\(hints.count)수)"
    }

    // MARK: - 해답 재생

    func testFreeCellHintWins() {
        let game = FreeCell(seed: 3)
        guard case .solved(let line) = game.searchHint(timeLimit: 2, nodeLimit: 120_000) else {
            return XCTFail("프리셀 시드 3의 해답을 찾지 못함")
        }
        XCTAssertNil(play(game, line))
    }

    func testKlondikeHintWins() {
        let game = Klondike(seed: 5, drawCount: 1)
        guard case .solved(let line) = game.searchHint(timeLimit: 2, nodeLimit: 120_000) else {
            return XCTFail("클론다이크 시드 5의 해답을 찾지 못함")
        }
        XCTAssertNil(play(game, line))
    }

    func testFreeCellHintFromMidGame() {
        // 몇 수 둔 뒤에도 힌트가 이기는 줄을 이어서 찾아야 한다.
        let game = FreeCell(seed: 2)
        guard case .solved(let line) = game.searchHint(timeLimit: 2, nodeLimit: 120_000),
              let first = line.first else { return XCTFail("처음 해답 없음") }
        // 해답의 첫 수만 두고 다시 물어본다.
        switch first {
        case .move(let src, let index, let dst):
            XCTAssertTrue(game.move(src, index: index, dst).ok)
        case .draw, .recycle:
            XCTAssertTrue(game.drawFromStock().ok)
        }
        guard case .solved(let rest) = game.searchHint(timeLimit: 2, nodeLimit: 120_000) else {
            return XCTFail("한 수 둔 뒤 해답을 찾지 못함")
        }
        XCTAssertNil(play(game, rest))
    }

    // MARK: - 풀 수 없음

    func testFreeCellImpossible() {
        // 프리셀 4칸이 2로 가득 차 있고, 여덟 열의 맨 위가 7과 10뿐이라
        // 어떤 수도 둘 수 없다. 이때는 "힌트 없음"이 아니라 "풀 수 없음"이다.
        func card(_ rank: Int, _ suit: Suit) -> PackedCard {
            PackedCard(rank: rank, suit: suit, faceup: true)
        }
        let suits: [Suit] = [.spades, .hearts, .diamonds, .clubs]
        let cells = suits.map { [card(2, $0)] }
        var tableau: [[PackedCard]] = []
        for suit in suits { tableau.append([card(13, suit), card(7, suit)]) }
        for suit in suits { tableau.append([card(12, suit), card(10, suit)]) }
        let snapshot = GameSnapshot(seed: 1, score: 0, moves: 0,
                                    stock: [], waste: [],
                                    freecells: cells,
                                    foundations: [[], [], [], []],
                                    tableau: tableau)
        let game = FreeCell(seed: 1)
        game.restoreSnapshot(snapshot)
        XCTAssertEqual(game.hint(), nil, "둘 수 있는 수가 없어야 한다")
        XCTAssertEqual(HintSolver.solve(kind: .freecell, snapshot: snapshot,
                                        timeLimit: 1, nodeLimit: 20_000),
                       .impossible)
    }

    func testEndgameSolved() {
        // 파운데이션에 K 3장이 끝까지 올라가 있고 남은 카드가 하나면 바로 이긴다.
        func card(_ rank: Int, _ suit: Suit) -> PackedCard {
            PackedCard(rank: rank, suit: suit, faceup: true)
        }
        var foundations: [[PackedCard]] = []
        for suit in [Suit.spades, .hearts, .diamonds] {
            foundations.append((1...13).map { card($0, suit) })
        }
        foundations.append((1...12).map { card($0, .clubs) })
        let snapshot = GameSnapshot(seed: 1, score: 0, moves: 0,
                                    stock: [], waste: [],
                                    freecells: [[], [], [], []],
                                    foundations: foundations,
                                    tableau: [[card(13, .clubs)]])
        let game = FreeCell(seed: 1)
        game.restoreSnapshot(snapshot)
        guard case .solved(let line) = game.searchHint(timeLimit: 1, nodeLimit: 20_000) else {
            return XCTFail("마지막 한 장을 못 찾음")
        }
        XCTAssertEqual(line, [.move(src: Ref(.tableau, 0), index: 0,
                                    dst: Ref(.foundation, 3))])
        XCTAssertNil(play(game, line))
    }

    // MARK: - 풀리는 스파이더 판의 해답

    func testSpiderPlanHint() {
        guard let deal = SpiderWinnable.makeDeal(sourceSeed: 3, suits: 1,
                                                 timeLimit: 20, nodeLimit: 1_000_000) else {
            return XCTFail("풀리는 판을 만들지 못함")
        }
        let game = Spider(seed: deal.sourceSeed, suits: deal.suits)
        game.applyDeal(deal)
        XCTAssertNotNil(game.startLayout?.solution, "해답이 시작 배치에 남아야 한다")
        // 해답을 한 수씩 따라가며 힌트가 즉시 같은 수를 알려 주는지 확인한다.
        for (n, expected) in deal.solution.enumerated() {
            guard case .solved(let line) = game.searchHint(timeLimit: 1, nodeLimit: 20_000),
                  let hint = line.first else {
                return XCTFail("\(n)수째 힌트 없음")
            }
            switch (hint, expected) {
            case (.draw, .deal):
                XCTAssertTrue(game.drawFromStock().ok)
            case let (.move(src, index, dst), .move(esrc, eindex, edst)):
                XCTAssertEqual([src.index, index, dst.index], [esrc, eindex, edst],
                               "\(n)수째 힌트가 해답과 다름")
                XCTAssertTrue(game.move(src, index: index, dst).ok)
            default:
                return XCTFail("\(n)수째 힌트 종류가 다름: \(hint) vs \(expected)")
            }
        }
        XCTAssertTrue(game.isWon(), "해답을 따라갔는데 이기지 못함")
    }

    func testSpiderPlanHintStopsAfterDeviation() {
        guard let deal = SpiderWinnable.makeDeal(sourceSeed: 3, suits: 1,
                                                 timeLimit: 20, nodeLimit: 1_000_000) else {
            return XCTFail("풀리는 판을 만들지 못함")
        }
        let game = Spider(seed: deal.sourceSeed, suits: deal.suits)
        game.applyDeal(deal)
        // 해답의 첫 수와 다른 수를 하나 둔다.
        var planned: (src: Int, index: Int, dst: Int)?
        if case .move(let s, let i, let d)? = deal.solution.first {
            planned = (s, i, d)
        }
        var moved = false
        outer: for src in 0..<10 {
            let pile = game.tableau[src]
            for dst in 0..<10 where dst != src {
                let index = pile.count - 1
                if let plan = planned, plan.src == src, plan.index == index, plan.dst == dst {
                    continue
                }
                if game.move(Ref(.tableau, src), index: index, Ref(.tableau, dst)).ok {
                    moved = true
                    break outer
                }
            }
        }
        guard moved else { return XCTFail("아무 수도 두지 못함") }
        // 해답 경로에서 벗어났으면 계획 힌트를 쓰지 않는다(탐색으로 넘어간다).
        XCTAssertNil(game.planHint())
    }

    // MARK: - 예산

    func testBudgetStaysSmall() {
        // 힌트 한 번에 화면이 오래 멈추지 않도록 게임별 예산을 좁게 둔다.
        for kind in GameKind.allCases {
            let budget = HintSolver.budget(for: kind)
            XCTAssertLessThanOrEqual(budget.time, 3.0, "\(kind) 힌트 시간 예산")
            XCTAssertLessThanOrEqual(budget.nodes, 600_000, "\(kind) 힌트 노드 예산")
        }
    }
}
