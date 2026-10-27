// CoreTests.swift — solitaire_core.py 의 규칙 검사 50개를 Swift 로 옮긴 것이다.
// 창 없이 규칙 엔진만 검증하며, 파이썬 원본과 1:1 로 대응한다.

import XCTest
@testable import PSolitaireKit

// ── 테스트 도우미 ───────────────────────────────────────────────────────────

/// 클론다이크 새 판(파이썬 fresh()).
private func fresh(seed: Int = 1, drawCount: Int = 3) -> Klondike {
    Klondike(seed: seed, drawCount: drawCount)
}

/// 프리셀 새 판(파이썬 fc()).
private func fc(seed: Int = 1) -> FreeCell {
    FreeCell(seed: seed)
}

/// 스파이더 새 판(파이썬 sp()).
private func sp(seed: Int = 1, suits: Int = 1) -> Spider {
    Spider(seed: seed, suits: suits)
}

/// 카드 한 장(파이썬 Card(rank, suit, faceup)).
private func card(_ rank: Int, _ suit: Suit, _ faceup: Bool = false) -> Card {
    Card(rank: rank, suit: suit, faceup: faceup)
}

/// 무늬 번호(0=♠ … 3=♣)로 카드 한 장.
private func card(_ rank: Int, _ suitIndex: Int, _ faceup: Bool = false) -> Card {
    Card(rank: rank, suit: Suit(rawValue: suitIndex)!, faceup: faceup)
}

/// 카드의 규칙상 정체성(무늬·숫자) — 파이썬 key() 와 같다.
/// uid는 카드마다 붙는 일련번호라 되돌리기 뒤에는 달라진다(스파이더는 같은 카드가 여러 장).
private func key(_ card: Card) -> String { "\(card.suit.rawValue)-\(card.rank)" }

/// 실행 취소 검증용 배치 스냅숏(파이썬 layout()).
private struct Layout: Equatable {
    let tableau: [[String]]
    let stock: [String]
    let waste: [String]
    let foundations: [[String]]
    let score: Int
    let moves: Int
}

private func layout(_ game: BaseGame) -> Layout {
    Layout(tableau: game.tableau.map { $0.map(key) },
           stock: game.stock.map(key),
           waste: game.waste.map(key),
           foundations: game.foundations.map { $0.map(key) },
           score: game.score,
           moves: game.moves)
}

/// "옮기기" 힌트에서 src/index/dst를 꺼낸다(다른 종류면 nil).
private func moveHint(_ hint: Hint?) -> (src: Ref, index: Int, dst: Ref)? {
    guard let hint, case let .move(src, index, dst) = hint else { return nil }
    return (src, index, dst)
}

final class CoreTests: XCTestCase {

    // ── 카드 배분 ───────────────────────────────────────────────────────────

    // 카드 배분 모양: 1~7장, 뒤집힌 카드 21장, 스톡 24장, uid 52개
    func testDealShape() {
        let g = fresh()
        XCTAssertEqual(g.tableau.map { $0.count }, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(g.faceDownCount(), 21)
        XCTAssertTrue(g.tableau.allSatisfy { $0.last?.faceup == true })
        XCTAssertEqual(g.stock.count, 24)
        XCTAssertTrue(g.waste.isEmpty)
        XCTAssertTrue(g.stock.allSatisfy { !$0.faceup })
        let uids = Set(g.tableau.flatMap { $0 }.map { $0.uid }).union(g.stock.map { $0.uid })
        XCTAssertEqual(uids.count, 52, "카드가 중복되거나 빠졌습니다")
    }

    // 같은 시드는 같은 판, 다른 시드는 다른 판
    func testDealDeterministic() {
        let a = fresh(seed: 7)
        let b = fresh(seed: 7)
        XCTAssertEqual(layout(a), layout(b))
        let c = fresh(seed: 8)
        XCTAssertNotEqual(layout(a), layout(c))
    }

    // 다시 시작은 같은 판이어야 한다
    func testRestartSameDeal() {
        let g = fresh(seed: 11)
        let first = layout(g)
        g.drawFromStock()
        g.restart()
        XCTAssertEqual(layout(g), first, "다시 시작은 같은 판이어야 합니다")
    }

    // ── 집기(pick) 규칙 ─────────────────────────────────────────────────────

    // 색이 번갈아 내림차순이면 통째로, 끊기면 거기까지
    func testPickRun() {
        let g = fresh()
        g.tableau[0] = [card(8, .hearts, true), card(7, .spades, true), card(6, .hearts, true)]
        XCTAssertEqual(g.pick(Ref(.tableau, 0), index: 0)?.count, 3, "색이 번갈아 내림차순이면 통째로")
        XCTAssertEqual(g.pick(Ref(.tableau, 0), index: 2)?.count, 1)
        g.tableau[1] = [card(8, .hearts, true), card(7, .diamonds, true)]   // 빨강 위에 빨강
        XCTAssertNil(g.pick(Ref(.tableau, 1), index: 0), "위 카드가 이어지지 않으면 집을 수 없다")
        XCTAssertEqual(g.pick(Ref(.tableau, 1), index: 1)?.count, 1)
        g.tableau[2] = [card(9, .spades, false), card(8, .hearts, true)]    // 뒤집힌 카드 포함
        XCTAssertNil(g.pick(Ref(.tableau, 2), index: 0))
        XCTAssertEqual(g.pick(Ref(.tableau, 2), index: 1)?.count, 1)
    }

    // 덮여 있는 카드는 집을 수 없다 — 위 카드를 먼저 옮겨야 한다(MS 규칙)
    func testBuriedCardCannotBePicked() {
        let g = fresh()
        g.tableau[0] = [card(8, .hearts, true), card(7, .diamonds, true)]
        g.tableau[1] = [card(8, .clubs, true)]
        XCTAssertNil(g.pick(Ref(.tableau, 0), index: 0), "7♦에 덮인 8♥는 집을 수 없습니다")
        XCTAssertFalse(g.move(Ref(.tableau, 0), index: 0, Ref(.tableau, 1)).ok, "덮인 카드는 옮길 수 없습니다")
        let res = g.move(Ref(.tableau, 0), index: 1, Ref(.tableau, 1))
        XCTAssertTrue(res.ok, "맨 위 카드는 옮길 수 있어야 합니다")
        XCTAssertEqual(g.tableau[0].count, 1)
        XCTAssertEqual(g.tableau[0][0].rank, 8)
        XCTAssertEqual(g.tableau[1].map { $0.rank }, [8, 7])
        g.undo()
        XCTAssertEqual(g.tableau[0].count, 2, "실행 취소로 되돌아와야 합니다")
    }

    // ── 태블로 규칙 ─────────────────────────────────────────────────────────

    // 색 교대(빨강 위 검정)와 한 단계 아래 숫자만 놓을 수 있다
    func testTableauColorsAndRanks() {
        let g = fresh()
        g.tableau[0] = [card(6, .spades, true)]
        // 파이썬 원본은 시드가 만든 tableau[1] 맨 위 카드에 기대는데, 셔플이 다르므로
        // 규칙(색 교대 / 숫자 연속)을 그대로 검사하도록 대상을 고정한다.
        g.tableau[1] = [card(6, .clubs, true)]

        g.waste = [card(5, .hearts, true)]
        XCTAssertTrue(g.move(Ref(.waste, 0), index: 0, Ref(.tableau, 0)).ok)
        XCTAssertEqual(g.score, 5, "웨이스트→태블로는 +5점")

        g.waste = [card(5, .spades, true)]                  // 같은 색(검정) → 불가
        XCTAssertFalse(g.move(Ref(.waste, 0), index: 0, Ref(.tableau, 1)).ok)
        g.waste = [card(7, .hearts, true)]                  // 숫자가 이어지지 않음 → 불가
        XCTAssertFalse(g.move(Ref(.waste, 0), index: 0, Ref(.tableau, 1)).ok)
    }

    // 빈 열에는 K만 놓을 수 있다
    func testEmptyColumnTakesKingOnly() {
        let g = fresh()
        g.tableau[3] = []
        g.waste = [card(11, .hearts, true)]
        XCTAssertFalse(g.move(Ref(.waste, 0), index: 0, Ref(.tableau, 3)).ok)
        g.waste = [card(13, .hearts, true)]
        XCTAssertTrue(g.move(Ref(.waste, 0), index: 0, Ref(.tableau, 3)).ok)
    }

    // ── 파운데이션 규칙 ─────────────────────────────────────────────────────

    // 빈 칸에는 A만, 무늬가 같고 한 단계 위만, 내려오면 -15점
    func testFoundationRules() {
        let g = fresh()
        g.waste = [card(2, .hearts, true)]
        XCTAssertFalse(g.move(Ref(.waste, 0), index: 0, Ref(.foundation, 0)).ok, "빈 칸에는 A만")

        g.waste = [card(1, .hearts, true)]
        XCTAssertTrue(g.move(Ref(.waste, 0), index: 0, Ref(.foundation, 0)).ok)
        XCTAssertEqual(g.score, 10)

        g.waste = [card(2, .spades, true)]
        XCTAssertFalse(g.move(Ref(.waste, 0), index: 0, Ref(.foundation, 0)).ok, "무늬가 다르면 불가")
        g.waste = [card(2, .hearts, true)]
        XCTAssertTrue(g.move(Ref(.waste, 0), index: 0, Ref(.foundation, 0)).ok)
        XCTAssertEqual(g.score, 20)

        // 파운데이션 → 태블로: -15점
        g.tableau[0] = [card(3, .spades, true)]
        XCTAssertTrue(g.move(Ref(.foundation, 0), index: -1, Ref(.tableau, 0)).ok)
        XCTAssertEqual(g.score, 5)
    }

    // 카드가 드러나면 자동 공개되고 +5점
    func testFlipScoresFivePoints() {
        let g = fresh()
        g.tableau[0] = [card(6, .clubs, false), card(5, .hearts, true)]
        g.foundations[0] = [card(4, .hearts, true)]
        let res = g.move(Ref(.tableau, 0), index: 1, Ref(.foundation, 0))
        XCTAssertTrue(res.ok && res.flipped, "카드가 드러나면 자동 공개되어야 합니다")
        XCTAssertEqual(g.score, 15, "이동 +10, 공개 +5")
        XCTAssertTrue(g.tableau[0].last?.faceup == true)
        XCTAssertEqual(g.tableau[0].last?.rank, 6)
    }

    // ── 스톡/웨이스트 ───────────────────────────────────────────────────────

    // 1장 넘기기와 3장 넘기기
    func testDrawOneAndThree() {
        var g = fresh(seed: 3, drawCount: 1)
        g.drawFromStock()
        XCTAssertEqual(g.waste.count, 1)
        XCTAssertEqual(g.stock.count, 23)

        g = fresh(seed: 3, drawCount: 3)
        g.drawFromStock()
        XCTAssertEqual(g.waste.count, 3)
        XCTAssertEqual(g.stock.count, 21)
        g.drawFromStock()
        XCTAssertEqual(g.waste.count, 6)
    }

    // 재활용 감점은 3장 넘기기 모드에서만 -100점
    func testRecyclePenaltyDependsOnMode() {
        var g = fresh(seed: 3, drawCount: 3)
        while !g.stock.isEmpty { g.drawFromStock() }
        let before = g.score
        let res = g.drawFromStock()
        XCTAssertEqual(res.action, "recycle")
        XCTAssertEqual(g.score, before - 100, "3장 넘기기 재활용은 -100점")
        XCTAssertEqual(g.stock.count, 24)
        XCTAssertTrue(g.waste.isEmpty)
        XCTAssertTrue(g.stock.allSatisfy { !$0.faceup })

        g = fresh(seed: 3, drawCount: 1)
        while !g.stock.isEmpty { g.drawFromStock() }
        let beforeOne = g.score
        XCTAssertEqual(g.drawFromStock().action, "recycle")
        XCTAssertEqual(g.score, beforeOne, "1장 넘기기 재활용은 감점 없음")
    }

    // 빈 스톡에서 넘기기: 실패하고 실행 취소 항목도 남지 않는다
    func testDrawOnEmptyStock() {
        let g = fresh(seed: 3)
        g.stock = []
        g.waste = []
        let res = g.drawFromStock()
        XCTAssertFalse(res.ok)
        XCTAssertFalse(g.canUndo, "아무 일도 없었으면 실행 취소 항목도 남지 않아야 합니다")
    }

    // ── 실행 취소 ───────────────────────────────────────────────────────────

    // 실행 취소는 점수·이동 수까지 통째로 되돌린다
    func testUndoRestoresEverything() {
        let g = fresh(seed: 5)
        g.tableau[6] = []                            // 빈 열에 K♥를 내려놓는다
        g.waste = [card(13, .hearts, true)]
        let initial = layout(g)
        XCTAssertTrue(g.move(Ref(.waste, 0), index: 0, Ref(.tableau, 6)).ok)
        g.drawFromStock()
        let before = layout(g)
        g.drawFromStock()
        XCTAssertTrue(g.undo())
        XCTAssertEqual(layout(g), before)
        XCTAssertTrue(g.undo() && g.undo())
        XCTAssertFalse(g.canUndo)
        XCTAssertEqual(layout(g), initial, "모두 되돌리면 이동 전 상태여야 합니다")
    }

    // ── 자동 이동 / 자동 완성 / 힌트 ────────────────────────────────────────

    // 더블클릭 자동 이동은 파운데이션을 먼저 노린다
    func testAutoMovePrefersFoundation() {
        let g = fresh()
        g.waste = [card(1, .spades, true)]
        let res = g.autoMove(Ref(.waste, 0), index: 0)
        XCTAssertNotNil(res)
        XCTAssertTrue(res?.ok == true)
        XCTAssertEqual(g.foundations[0].last?.rank, 1)
    }

    // 빈 열 ↔ 빈 열 킹 이동은 제안하지 않는다
    func testAutoMoveIgnoresPointlessKingShuffle() {
        let g = fresh()
        g.tableau = [[card(13, .spades, true)], [], [], [], [], [], []]
        g.waste = []
        XCTAssertNil(g.autoMove(Ref(.tableau, 0), index: 0), "빈 열 ↔ 빈 열 킹 이동은 제안하지 않는다")
    }

    // 자동 완성으로 게임을 끝낸다
    func testAutocompleteFinishesGame() {
        let g = fresh()
        g.stock = []
        g.waste = []
        g.foundations = (0..<4).map { s in (1...12).map { card($0, s, true) } }
        g.tableau = Array(repeating: [], count: 7)
        for s in 0..<4 {
            g.tableau[s] = [card(13, s, true)]
        }
        XCTAssertTrue(g.canAutoComplete())
        var steps = 0
        while g.autocompleteStep() != nil { steps += 1 }
        XCTAssertTrue(g.isWon())
        XCTAssertEqual(steps, 4)
    }

    // 카드가 숨어 있으면 자동 완성을 쓰지 않는다
    func testAutocompleteBlockedWhileCardsHidden() {
        let g = fresh()
        XCTAssertFalse(g.canAutoComplete())
    }

    // 힌트가 파운데이션으로 올리는 수를 찾는다
    func testHintFindsFoundationMove() {
        let g = fresh()
        g.waste = [card(1, .diamonds, true)]
        let h = moveHint(g.hint())
        XCTAssertNotNil(h)
        XCTAssertEqual(h?.dst.kind, .foundation)
    }

    // 다른 수가 없으면 스톡을 넘기라고 알려준다
    func testHintFallsBackToDraw() {
        let g = fresh()
        g.tableau = [[card(13, .spades, true)], [], [], [], [], [], []]
        g.waste = []
        XCTAssertEqual(g.hint(), Hint.draw, "다른 수가 없으면 스톡을 넘기라고 알려준다")
    }

    // 우승 판정과 보너스 계산
    func testWinDetectionAndBonus() {
        let g = fresh()
        g.foundations = (0..<4).map { s in (1...13).map { card($0, s, true) } }
        g.tableau = Array(repeating: [], count: 7)
        g.stock = []
        g.waste = []
        XCTAssertTrue(g.isWon())
        XCTAssertEqual(g.cardsRemaining(), 0)
        XCTAssertEqual(winBonus(seconds: 10), 70_000)
        XCTAssertEqual(winBonus(seconds: 0.5), 700_000)
    }

    // ── 프리셀 ──────────────────────────────────────────────────────────────

    // 프리셀 배분 모양: 7·7·7·7·6·6·6·6, 모두 앞면, 프리셀 4칸 비어 있음
    func testFreeCellDealShape() {
        let g = fc()
        XCTAssertEqual(g.tableau.map { $0.count }, [7, 7, 7, 7, 6, 6, 6, 6])
        XCTAssertTrue(g.tableau.allSatisfy { $0.allSatisfy { $0.faceup } }, "프리셀은 모두 앞면으로 시작")
        XCTAssertTrue(g.stock.isEmpty)
        XCTAssertTrue(g.waste.isEmpty)
        XCTAssertEqual(g.freecells.count, 4)
        XCTAssertTrue(g.freecells.allSatisfy { $0.isEmpty })
        XCTAssertEqual(Set(g.tableau.flatMap { $0 }.map { $0.uid }).count, 52)
    }

    // 프리셀도 시드가 같으면 같은 판
    func testFreeCellDealDeterministic() {
        XCTAssertEqual(layout(fc(seed: 7)), layout(fc(seed: 7)))
        XCTAssertNotEqual(layout(fc(seed: 7)), layout(fc(seed: 8)))
    }

    // 태블로 → 프리셀 한 칸으로 옮기기와 실행 취소
    func testFreeCellMoveToFreeCell() {
        let g = fc()
        let top = g.tableau[0].last!
        XCTAssertTrue(g.move(Ref(.tableau, 0), index: g.tableau[0].count - 1, Ref(.freecell, 0)).ok)
        XCTAssertEqual(g.freecells[0].count, 1)
        XCTAssertTrue(g.freecells[0][0] === top)
        XCTAssertFalse(g.tableau[0].contains(where: { $0 === top }))
        XCTAssertEqual(g.freeCellsFree(), 3)
        XCTAssertFalse(g.canDrop([g.tableau[1].last!], Ref(.freecell, 0)), "찬 프리셀에는 못 놓는다")
        XCTAssertTrue(g.undo())
        XCTAssertTrue(g.freecells[0].isEmpty)
        XCTAssertEqual(g.freeCellsFree(), 4)
    }

    // 프리셀 → 태블로, 프리셀 → 파운데이션
    func testFreeCellFreeCellToTableauAndFoundation() {
        let g = fc()
        g.freecells[0] = [card(5, .hearts, true)]
        g.tableau[0] = [card(6, .spades, true)]
        XCTAssertTrue(g.move(Ref(.freecell, 0), index: 0, Ref(.tableau, 0)).ok)
        XCTAssertEqual(g.tableau[0].last?.rank, 5)
        XCTAssertTrue(g.freecells[0].isEmpty)

        g.freecells[1] = [card(1, .diamonds, true)]
        XCTAssertTrue(g.move(Ref(.freecell, 1), index: 0, Ref(.foundation, 0)).ok)
        XCTAssertEqual(g.foundations[0].last?.rank, 1)
    }

    // 프리셀 파운데이션 규칙
    func testFreeCellFoundationRules() {
        let g = fc()
        g.foundations[0] = [card(1, .spades, true)]
        XCTAssertTrue(g.canDrop([card(2, .spades, true)], Ref(.foundation, 0)))
        XCTAssertFalse(g.canDrop([card(2, .hearts, true)], Ref(.foundation, 0)), "다른 무늬는 못 올린다")
        XCTAssertFalse(g.canDrop([card(3, .spades, true)], Ref(.foundation, 0)), "한 장씩만 올린다")
        XCTAssertFalse(g.canDrop([card(2, .spades, true)], Ref(.foundation, 1)), "빈 칸에는 A만")
    }

    // 프리셀 태블로는 색 교대 내림차순, 빈 열에는 아무 카드나
    func testFreeCellTableauAlternatingColors() {
        let g = fc()
        g.tableau[0] = [card(6, .spades, true)]
        XCTAssertTrue(g.canDrop([card(5, .hearts, true)], Ref(.tableau, 0)))
        XCTAssertFalse(g.canDrop([card(5, .clubs, true)], Ref(.tableau, 0)), "같은 색은 못 놓는다")
        XCTAssertFalse(g.canDrop([card(7, .hearts, true)], Ref(.tableau, 0)), "오름차순은 못 놓는다")
        g.tableau[1] = []
        XCTAssertTrue(g.canDrop([card(9, .clubs, true)], Ref(.tableau, 1)), "빈 열에는 아무 카드나")
    }

    // 슈퍼무브 용량: 빈 프리셀·빈 열을 경유해야 여러 장을 옮길 수 있다
    func testFreeCellSupermoveCapacity() {
        let g = fc()
        for i in 0..<4 {                                // 프리셀 4칸을 모두 채운다
            g.freecells[i] = [card(2 + i, .clubs, true)]
        }
        for i in g.tableau.indices {                    // 빈 열도 없앤다
            g.tableau[i] = [card(6, .spades, true)]
        }
        g.tableau[0] = [card(6, .spades, true), card(5, .hearts, true)]
        g.tableau[1] = [card(7, .hearts, true)]
        XCTAssertEqual(g.maxMove(Ref(.tableau, 1)), 1)
        XCTAssertFalse(g.canDrop(g.tableau[0], Ref(.tableau, 1)), "경유할 곳이 없으면 한 장씩만")

        g.freecells[0] = []                             // 프리셀을 한 칸 비우면 2장까지
        XCTAssertEqual(g.maxMove(Ref(.tableau, 1)), 2)
        XCTAssertTrue(g.canDrop(g.tableau[0], Ref(.tableau, 1)))
        let res = g.move(Ref(.tableau, 0), index: 0, Ref(.tableau, 1))
        XCTAssertTrue(res.ok && res.count == 2)
        XCTAssertEqual(g.tableau[1].map { $0.rank }, [7, 6, 5])
        XCTAssertEqual(g.freeCellsFree(), 1, "프리셀은 그대로 한 칸만 비어 있다")
    }

    // 프리셀 자동 완성으로 게임을 끝낸다
    func testFreeCellAutocompleteFinishesGame() {
        let g = fc()
        g.freecells = [[], [], [], []]
        g.foundations = (0..<4).map { s in (1...12).map { card($0, s, true) } }
        g.tableau = Array(repeating: [], count: 8)
        for s in 0..<4 {
            g.tableau[s] = [card(13, s, true)]
        }
        XCTAssertTrue(g.canAutoComplete())
        var steps = 0
        while g.autocompleteStep() != nil { steps += 1 }
        XCTAssertTrue(g.isWon())
        XCTAssertEqual(steps, 4)
    }

    // 프리셀이 차 있으면 자동 완성을 쓰지 않는다
    func testFreeCellAutocompleteNeedsEmptyCells() {
        let g = fc()
        g.freecells[0] = [card(4, .clubs, true)]
        XCTAssertFalse(g.canAutoComplete(), "프리셀이 차 있으면 자동 완성을 쓰지 않는다")
    }

    // 프리셀 힌트가 파운데이션을 먼저 노린다
    func testFreeCellHintPrefersFoundation() {
        let g = fc()
        g.tableau[0] = [card(1, .clubs, true)]
        let h = moveHint(g.hint())
        XCTAssertNotNil(h)
        XCTAssertEqual(h?.dst.kind, .foundation)
    }

    // 프리셀에는 스톡이 없다
    func testFreeCellNoStock() {
        let g = fc()
        let res = g.drawFromStock()
        XCTAssertFalse(res.ok)
        XCTAssertFalse(g.canUndo)
    }

    // ── 스파이더 ────────────────────────────────────────────────────────────

    // 스파이더 배분 모양: 6·6·6·6·5×6, 스톡 50장(5번), 점수 500
    func testSpiderDealShape() {
        let g = sp()
        XCTAssertEqual(g.tableau.map { $0.count }, [6, 6, 6, 6, 5, 5, 5, 5, 5, 5])
        XCTAssertEqual(g.tableau.reduce(0) { $0 + $1.count }, 54)
        XCTAssertEqual(g.stock.count, 50)
        XCTAssertEqual(g.dealsLeft(), 5)
        XCTAssertTrue(g.tableau.allSatisfy { $0.filter { $0.faceup }.count == 1 }, "맨 위 한 장만 앞면")
        XCTAssertEqual(g.score, 500)
        XCTAssertTrue(g.foundations.isEmpty)
        let uids = Set(g.tableau.flatMap { $0 }.map { $0.uid }).union(g.stock.map { $0.uid })
        XCTAssertEqual(uids.count, 104)
    }

    // 무늬 수 설정에 따른 덱 구성(1무늬=♠ 8벌, 2무늬, 4무늬)
    func testSpiderSuitCounts() {
        XCTAssertEqual(Set(sp(suits: 1).buildDeck().map { $0.suit }), [Suit.spades])
        XCTAssertEqual(Set(sp(suits: 2).buildDeck().map { $0.suit }), [Suit.spades, Suit.hearts])
        XCTAssertEqual(Set(sp(suits: 4).buildDeck().map { $0.suit }).count, 4)
        XCTAssertEqual(sp(suits: 4).buildDeck().count, 104)
    }

    // 스파이더도 시드가 같으면 같은 판
    func testSpiderDealDeterministic() {
        XCTAssertEqual(layout(sp(seed: 9)), layout(sp(seed: 9)))
        XCTAssertNotEqual(layout(sp(seed: 9)), layout(sp(seed: 10)))
    }

    // 같은 무늬 내림차순만 통째로 집는다
    func testSpiderSameSuitRunOnly() {
        let g = sp()
        g.tableau[0] = [card(7, .spades, true), card(6, .spades, true), card(5, .spades, true)]
        XCTAssertEqual(g.pick(Ref(.tableau, 0), index: 0)?.count, 3, "같은 무늬 내림차순은 통째로")
        XCTAssertEqual(g.pick(Ref(.tableau, 0), index: 1)?.count, 2)
        g.tableau[1] = [card(7, .spades, true), card(6, .hearts, true)]         // 무늬가 섞임
        XCTAssertNil(g.pick(Ref(.tableau, 1), index: 0), "무늬가 섞여 덮여 있으면 집을 수 없다")
        XCTAssertEqual(g.pick(Ref(.tableau, 1), index: 1)?.count, 1)
        g.tableau[2] = [card(7, .spades, false), card(6, .spades, true)]        // 뒤집힌 카드 포함
        XCTAssertNil(g.pick(Ref(.tableau, 2), index: 0))
        XCTAssertEqual(g.pick(Ref(.tableau, 2), index: 1)?.count, 1)
    }

    // 무늬가 섞인 열에서는 맨 위 카드만 옮길 수 있고, 아래 카드는 집을 수 없다
    func testSpiderMixedRunMovesTopCardOnly() {
        let g = sp()
        g.tableau[0] = [card(7, .spades, true), card(6, .hearts, true)]
        g.tableau[1] = [card(7, .diamonds, true)]
        XCTAssertNil(g.pick(Ref(.tableau, 0), index: 0), "6♥에 덮인 7♠는 집을 수 없습니다")
        let res = g.move(Ref(.tableau, 0), index: 1, Ref(.tableau, 1))
        XCTAssertTrue(res.ok && res.count == 1, "무늬가 섞이면 맨 위 카드만 옮긴다")
        XCTAssertEqual(g.tableau[0].map { $0.rank }, [7], "아래 카드는 그대로 남아야 합니다")
        XCTAssertEqual(g.tableau[1].map { $0.rank }, [7, 6])
        g.undo()
        XCTAssertEqual(g.tableau[0].map { $0.rank }, [7, 6])
    }

    // '무늬 상관없이' 설정이면 무늬가 섞여도 통째로 집고 옮긴다(쉬움 옵션)
    func testSpiderSuitFreeMovesMixedGroup() {
        let g = Spider(seed: 3, suits: 2, suitFree: true)
        XCTAssertTrue(g.suitFree)
        g.tableau[0] = [card(10, .hearts, true)]
        g.tableau[1] = [card(9, .spades, true), card(8, .hearts, true), card(7, .diamonds, true)]
        XCTAssertEqual(g.pick(Ref(.tableau, 1), index: 0)?.map { $0.rank }, [9, 8, 7], "무늬가 섞여도 내림차순이면 통째로")
        let res = g.move(Ref(.tableau, 1), index: 0, Ref(.tableau, 0))
        XCTAssertTrue(res.ok && res.count == 3)
        XCTAssertEqual(g.tableau[0].map { $0.rank }, [10, 9, 8, 7])
        XCTAssertTrue(g.tableau[1].isEmpty)
        g.undo()
        XCTAssertEqual(g.tableau[1].map { $0.rank }, [9, 8, 7], "실행 취소도 그대로")
    }

    // 설정을 켜고 꺼도 판은 그대로 두고 규칙만 바뀐다
    func testSpiderSuitFreeToggleKeepsBoard() {
        let g = sp(seed: 4, suits: 2)
        g.tableau[0] = [card(9, .spades, true), card(8, .hearts, true)]
        XCTAssertNil(g.pick(Ref(.tableau, 0), index: 0), "기본은 MS 규칙(같은 무늬만)")
        let cardsBefore = g.cardsRemaining()
        g.setSuitFree(true)
        XCTAssertEqual(g.pick(Ref(.tableau, 0), index: 0)?.count, 2, "켜면 무늬가 섞여도 통째로")
        XCTAssertEqual(g.cardsRemaining(), cardsBefore, "판은 그대로")
        g.setSuitFree(false)
        XCTAssertNil(g.pick(Ref(.tableau, 0), index: 0))
    }

    // 집을 수 없을 때 이유 문구를 준다(설정을 켜면 문구가 사라진다)
    func testGroupLimitNoteExplainsWhyNotPickable() {
        let g = sp(seed: 5, suits: 2)
        g.tableau[0] = [card(9, .spades, true), card(8, .hearts, true)]
        XCTAssertNil(g.pick(Ref(.tableau, 0), index: 0))
        XCTAssertEqual(g.groupLimitNote(Ref(.tableau, 0), index: 0), g.groupLimitText)
        XCTAssertNil(g.groupLimitNote(Ref(.tableau, 0), index: 1), "맨 위 카드는 집을 수 있다")
        g.setSuitFree(true)
        XCTAssertNil(g.groupLimitNote(Ref(.tableau, 0), index: 0), "무늬 상관없이면 집을 수 있다")

        let k = fresh()
        k.tableau[0] = [card(9, .spades, true), card(8, .spades, true)]         // 같은 색(검정)
        XCTAssertEqual(k.groupLimitNote(Ref(.tableau, 0), index: 0), k.groupLimitText)
        k.tableau[1] = [card(9, .spades, true), card(8, .hearts, true)]         // 색이 번갈아
        XCTAssertNil(k.groupLimitNote(Ref(.tableau, 1), index: 0))
        k.tableau[2] = [card(9, .spades, true), card(7, .hearts, true)]         // 숫자가 안 이어짐
        XCTAssertEqual(k.groupLimitNote(Ref(.tableau, 2), index: 0), k.buriedText)
    }

    // suit_free는 스파이더 전용 — 다른 게임에 넘겨도 무시된다
    func testMakeGameIgnoresSuitFreeElsewhere() {
        XCTAssertEqual(makeGame(kind: "klondike", options: GameOptions(suitFree: true)).kind, .klondike)
        XCTAssertEqual(makeGame(kind: "freecell", options: GameOptions(suitFree: true)).kind, .freecell)
        XCTAssertTrue(makeGame(kind: "spider", options: GameOptions(suits: 2, suitFree: true)) is Spider)
        XCTAssertEqual((makeGame(kind: "spider", options: GameOptions(suits: 2, suitFree: true)) as? Spider)?.suitFree, true)
        XCTAssertEqual((makeGame(kind: "spider", options: GameOptions(suits: 2)) as? Spider)?.suitFree, false)
    }

    // '무늬 상관없이'면 무늬가 섞인 묶음도 통째로 옮겨지고 아래 카드가 드러난다
    func testSpiderSuitFreeMixedGroupRevealsCard() {
        let g = Spider(seed: 8, suits: 2, suitFree: true)
        g.tableau[0] = [card(4, .spades, false), card(9, .spades, true), card(8, .hearts, true)]
        g.tableau[1] = [card(10, .hearts, true)]
        let res = g.move(Ref(.tableau, 0), index: 1, Ref(.tableau, 1))
        XCTAssertTrue(res.ok && res.count == 2 && res.flipped)
        XCTAssertEqual(g.tableau[1].map { $0.rank }, [10, 9, 8])
        XCTAssertTrue(g.tableau[0][0].faceup, "묶음이 빠지면 아래 카드가 드러난다")
        g.undo()
        XCTAssertFalse(g.tableau[0][0].faceup)
        XCTAssertEqual(g.tableau[0].count, 3, "실행 취소는 드러내기까지 되돌린다")
    }

    // 힌트·더블클릭 자동 이동도 '무늬 상관없이' 설정을 따라 묶음을 통째로 잡는다
    func testSpiderSuitFreeHintAndAutoMoveFollowOption() {
        let g = Spider(seed: 9, suits: 2, suitFree: true)
        for i in g.tableau.indices { g.tableau[i] = [] }
        g.stock = []
        g.tableau[0] = [card(9, .spades, true), card(8, .hearts, true)]
        g.tableau[1] = [card(10, .hearts, true)]
        let hint = moveHint(g.hint())
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.src, Ref(.tableau, 0))
        XCTAssertEqual(g.pick(hint!.src, index: hint!.index)?.count, 2, "무늬 상관없이면 섞인 묶음 2장")

        g.setSuitFree(false)
        let hint2 = moveHint(g.hint())
        XCTAssertTrue(hint2 == nil || hint2?.index != 0, "기본 규칙은 섞인 묶음을 힌트로 주지 않는다")

        g.setSuitFree(true)
        let res = g.autoMove(Ref(.tableau, 0), index: 0)
        XCTAssertTrue(res?.ok == true && res?.count == 2, "자동 이동도 두 장을 옮긴다")
    }

    // 스파이더 놓기 규칙: 무늬는 상관없고 한 단계 아래 숫자만
    func testSpiderDropRules() {
        let g = sp()
        g.tableau[0] = [card(8, .hearts, true)]
        XCTAssertTrue(g.canDrop([card(7, .spades, true)], Ref(.tableau, 0)), "무늬가 달라도 한 단계 아래면 놓는다")
        XCTAssertFalse(g.canDrop([card(9, .spades, true)], Ref(.tableau, 0)))
        g.tableau[1] = []
        XCTAssertTrue(g.canDrop([card(3, .clubs, true)], Ref(.tableau, 1)), "빈 열에는 아무 카드나")
        XCTAssertNotNil(g.pick(Ref(.tableau, 0), index: 0))
        XCTAssertFalse(g.canDrop([card(7, .spades, true)], Ref(.foundation, 0)), "완성 세트에는 못 놓는다")
    }

    // 빈 열이 있으면 스톡을 돌릴 수 없다
    func testSpiderStockDealNeedsFullColumns() {
        let g = sp()
        g.tableau[3] = []
        XCTAssertFalse(g.drawFromStock().ok, "빈 열이 있으면 돌릴 수 없다")
        g.tableau[3] = [card(4, .spades, true)]
        let res = g.drawFromStock()
        XCTAssertTrue(res.ok && res.count == 10 && res.action == "deal")
        XCTAssertEqual(g.stock.count, 40)
        XCTAssertEqual(g.dealsLeft(), 4)
        XCTAssertTrue(g.tableau.allSatisfy { $0.count >= 2 })
        XCTAssertEqual(g.score, 499, "이동마다 1점씩 준다")
        XCTAssertTrue(g.undo())
        XCTAssertEqual(g.stock.count, 50)
    }

    // K→A 같은 무늬 13장이 모이면 완성 세트로 걷어낸다
    func testSpiderCollectsCompletedSet() {
        let g = sp()
        for i in g.tableau.indices { g.tableau[i] = [] }
        g.score = 500
        g.tableau[0] = [card(13, .spades, true)]
        g.tableau[1] = (1...12).reversed().map { card($0, .spades, true) }   // Q♠…A♠
        let res = g.move(Ref(.tableau, 1), index: 0, Ref(.tableau, 0))       // K♠ 위로 12장을 옮긴다
        XCTAssertTrue(res.ok)
        XCTAssertEqual(g.foundations.count, 1)
        XCTAssertEqual(g.foundations[0].count, 13)
        XCTAssertTrue(g.tableau[0].isEmpty, "완성된 세트는 바닥에서 빠진다")
        XCTAssertEqual(res.sets, 1)
        XCTAssertEqual(g.score, 500 - 1 + 100)
    }

    // 8세트를 모으면 우승
    /// 세트를 걷어낸 자리에 드러난 카드가 뒤집힌다(회귀: 뒤집히지 않던 버그).
    func testSpiderSetCollectFlipsExposedCard() {
        let g = sp()
        for i in g.tableau.indices { g.tableau[i] = [] }
        g.tableau[0] = [card(5, .hearts, false), card(13, .spades, true)]    // 뒤집힌 5♥ 위에 K♠
        g.tableau[1] = (1...12).reversed().map { card($0, .spades, true) }   // Q♠…A♠
        XCTAssertFalse(g.tableau[0][0].faceup)
        let res = g.move(Ref(.tableau, 1), index: 0, Ref(.tableau, 0))       // K♠ 위로 12장 → 세트
        XCTAssertTrue(res.ok)
        XCTAssertEqual(res.sets, 1)
        XCTAssertEqual(g.tableau[0].count, 1, "세트는 빠지고 아래 카드만 남는다")
        XCTAssertTrue(g.tableau[0][0].faceup, "걷어낸 자리에 드러난 카드는 뒤집혀야 한다")
    }

    func testSpiderWinDetection() {
        let g = sp()
        g.foundations = (0..<8).map { _ in (1...13).map { card($0, .spades, true) } }
        g.tableau = Array(repeating: [], count: 10)
        g.stock = []
        XCTAssertTrue(g.isWon())
        XCTAssertEqual(g.cardsRemaining(), 0)
    }

    // 같은 무늬로만 쌓아 올려 우승까지 가는지(규칙 자체 점검)
    func testSpiderFullFlowReachesWin() {
        let g = sp()
        for i in g.tableau.indices { g.tableau[i] = [] }
        g.stock = []
        // 8개 열에 A~K을 거꾸로 쌓아 두고, 빈 열로 옮겨 완성시킨다
        g.tableau[0] = (1...13).reversed().map { card($0, .spades, true) }
        for i in 1..<10 { g.tableau[i] = [] }
        // 파이썬은 무늬 자리에 0~6을 넣지만 Swift Suit는 0~3만 표현한다.
        // 이 테스트는 세트 수와 우승 판정만 보므로 무늬는 상관없다.
        g.foundations = (0..<7).map { s in (1...13).map { card($0, s % 4, true) } }
        g.score = 500
        for _ in 0..<7 { g.collectSets() }
        XCTAssertEqual(g.foundations.count, 8)
        XCTAssertTrue(g.isWon())
    }

    // 같은 무늬로 이어 붙이는 수를 힌트로 주고 자동 이동한다
    func testSpiderHintAndAutoMove() {
        let g = sp()
        for i in g.tableau.indices { g.tableau[i] = [] }
        g.tableau[0] = [card(6, .spades, true)]
        g.tableau[1] = [card(5, .spades, true), card(4, .spades, true)]
        let h = moveHint(g.hint())
        XCTAssertNotNil(h)
        XCTAssertEqual(h?.dst, Ref(.tableau, 0), "같은 무늬로 이어 붙이는 수")
        let res = g.autoMove(Ref(.tableau, 1), index: 0)
        XCTAssertTrue(res?.ok == true)
        XCTAssertEqual(g.tableau[0].count, 3)
        for i in g.tableau.indices { g.tableau[i] = [card(6, .spades, true)] }
        g.stock = [card(1, .spades, false)]
        XCTAssertEqual(g.hint(), Hint.draw, "다른 수가 없으면 스톡을 돌리라고 알려준다")
    }

    // ── 게임 만들기 / 카드 일련번호 ─────────────────────────────────────────

    // 게임 종류 이름으로 게임을 만든다(모르는 값은 클론다이크)
    func testMakeGameFactory() {
        XCTAssertTrue(makeGame(kind: "klondike", options: GameOptions(seed: 1, drawCount: 1)) is Klondike)
        XCTAssertTrue(makeGame(kind: "freecell", options: GameOptions(seed: 1, drawCount: 3)) is FreeCell)
        let spider = makeGame(kind: "spider", options: GameOptions(seed: 1, suits: 2))
        XCTAssertTrue(spider is Spider)
        XCTAssertEqual((spider as? Spider)?.suits, 2)
        XCTAssertTrue(makeGame(kind: "없는게임", options: GameOptions(seed: 1)) is Klondike, "모르는 값은 클론다이크")
    }

    // ── 실행 복귀(리두) ─────────────────────────────────────────────────────

    func testUndoRedoRestoresLayout() {
        let g = fresh(seed: 5, drawCount: 1)
        let before = layout(g)
        XCTAssertTrue(g.drawFromStock().ok)
        let after = layout(g)
        XCTAssertTrue(g.canUndo)
        XCTAssertTrue(g.undo())
        XCTAssertEqual(layout(g), before)
        XCTAssertTrue(g.canRedo)
        XCTAssertTrue(g.redo())
        XCTAssertEqual(layout(g), after)
        XCTAssertFalse(g.canRedo)

        // 새 수를 두면 되돌린 가지는 사라진다.
        XCTAssertTrue(g.undo())
        XCTAssertTrue(g.drawFromStock().ok)
        XCTAssertFalse(g.canRedo)
    }

    // ── 진행 중인 판 저장/복원 ─────────────────────────────────────────────

    func testSnapshotRoundTripAllGames() {
        let klondike = fresh(seed: 19, drawCount: 1)
        _ = klondike.drawFromStock()
        let kSnapshot = klondike.exportSnapshot()
        let k2 = fresh(seed: 19, drawCount: 1)
        k2.restoreSnapshot(kSnapshot)
        XCTAssertEqual(layout(k2), layout(klondike))
        XCTAssertFalse(k2.canUndo, "복원한 판에는 이전 실행 취소 기록이 없다")

        let fc = fc(seed: 23)
        let cellCard = fc.tableau[0].last!
        XCTAssertTrue(fc.move(Ref(.tableau, 0), index: fc.tableau[0].count - 1,
                              Ref(.freecell, 0)).ok)
        XCTAssertTrue(fc.freecells[0].last === cellCard)
        let fSnapshot = fc.exportSnapshot()
        let fc2 = FreeCell(seed: 23)
        fc2.restoreSnapshot(fSnapshot)
        XCTAssertEqual(layout(fc2), layout(fc))

        let spider = sp(seed: 29, suits: 2)
        _ = spider.drawFromStock()
        let sSnapshot = spider.exportSnapshot()
        let spider2 = sp(seed: 29, suits: 2)
        spider2.restoreSnapshot(sSnapshot)
        XCTAssertEqual(layout(spider2), layout(spider))
        XCTAssertEqual(spider2.stock.count, spider.stock.count)
    }

    // 같은 무늬·숫자 카드가 여러 장이어도 uid는 서로 달라야 한다(화면 구분용)
    func testCardUidsAreUniqueInSpider() {
        let g = sp(suits: 4)
        let cards = g.tableau.flatMap { $0 } + g.stock
        XCTAssertEqual(Set(cards.map { $0.uid }).count, cards.count)
        XCTAssertEqual(cards.count, 104)
        let same = cards.filter { $0.suit == .spades && $0.rank == 1 }
        XCTAssertEqual(same.count, 2)
        XCTAssertNotEqual(same[0].uid, same[1].uid)
    }
}
