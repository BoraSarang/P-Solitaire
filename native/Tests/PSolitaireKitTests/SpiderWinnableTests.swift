import XCTest
@testable import PSolitaireKit

final class SpiderWinnableTests: XCTestCase {
    // 풀리는 판: 1무늬 해답을 찾은 뒤 무늬를 다시 칠해 1·2·4무늬 모두 보장한다.
    // (솔버는 시간 제한이 있어 디버그 빌드에서는 느릴 수 있으므로 여유를 둔다.)
    func testWinnableDealsKeepSuitCountsAndSolve() throws {
        for suits in [1, 2, 4] {
            guard let deal = SpiderWinnable.makeDeal(suits: suits, startingSeed: 1000,
                                                     attempts: 1, timeLimit: 3.0,
                                                     nodeLimit: 600_000) else {
                XCTFail("\(suits)무늬 풀리는 판을 만들지 못했습니다")
                continue
            }
            XCTAssertEqual(deal.suits, suits)

            let tableauCards = deal.tableau.flatMap { $0 }
            XCTAssertEqual(tableauCards.count, 54)
            XCTAssertEqual(deal.stock.count, 50)
            XCTAssertEqual(deal.tableau.map(\.count), [6, 6, 6, 6, 5, 5, 5, 5, 5, 5])
            XCTAssertTrue(deal.tableau.allSatisfy { pile in
                pile.last?.faceup == true && pile.dropLast().allSatisfy { !$0.faceup }
            })
            XCTAssertTrue(deal.stock.allSatisfy { !$0.faceup })
            XCTAssertEqual(Set(tableauCards.map(\.suit)).count, suits)

            // 무늬별 카드 수: 1무늬=104, 2무늬=52씩, 4무늬=26씩.
            let counts = Dictionary(grouping: tableauCards + deal.stock, by: \.suit)
                .mapValues(\.count)
            XCTAssertEqual(counts.values.sorted(), Array(repeating: 104 / suits, count: suits))
            // 각 무늬·숫자 조합은 8/suits장씩(1무늬 8장, 2무늬 4장, 4무늬 2장).
            let bySuitRank = Dictionary(grouping: tableauCards + deal.stock,
                                        by: { "\($0.suit.rawValue)-\($0.rank)" })
            XCTAssertEqual(bySuitRank.count, 13 * suits)
            XCTAssertTrue(bySuitRank.values.allSatisfy { $0.count == 8 / suits })

            let game = Spider(seed: deal.sourceSeed, suits: deal.suits)
            game.applyDeal(deal)
            XCTAssertEqual(game.seed, deal.sourceSeed)
            XCTAssertEqual(game.suits, suits)
            XCTAssertNotNil(game.startLayout)
            for move in deal.solution {
                switch move {
                case .deal:
                    XCTAssertTrue(game.drawFromStock().ok)
                case .move(let src, let index, let dst):
                    XCTAssertTrue(game.move(Ref(.tableau, src), index: index,
                                            Ref(.tableau, dst)).ok)
                }
            }
            XCTAssertTrue(game.isWon(), "\(suits)무늬 해답이 이겨야 합니다")
        }
    }

    func testRestartRestoresWinnableLayout() throws {
        guard let deal = SpiderWinnable.makeDeal(sourceSeed: 1000, suits: 2,
                                                 timeLimit: 3.0,
                                                 nodeLimit: 600_000) else {
            XCTFail("풀리는 판을 만들지 못했습니다")
            return
        }
        let game = Spider(seed: 1, suits: 1)
        game.applyDeal(deal)
        let key = layoutKey(game)
        game.moves = 7
        game.restart()
        XCTAssertEqual(layoutKey(game), key)
        XCTAssertEqual(game.suits, 2)
        XCTAssertEqual(game.seed, deal.sourceSeed)
    }

    func testSuitAssignmentKeepsSolutionGroupsTogether() {
        // 4무늬: 해답에서 묶인 세트(크기 2)는 같은 무늬, 나머지는 짝을 맞춘다.
        let comps4 = [[0], [1, 5], [2], [3], [4], [6], [7]]
        let four = SpiderWinnable.assignSuits(components: comps4, suits: 4)
        XCTAssertNotNil(four)
        XCTAssertEqual(four?[1], four?[5])
        XCTAssertEqual(Set((four ?? [:]).values).count, 4)
        XCTAssertEqual((four ?? [:]).values.filter { $0 == .spades }.count, 2)

        // 2무늬: 덩어리를 합쳐 4+4로 나눈다.
        let two = SpiderWinnable.assignSuits(components: comps4, suits: 2)
        XCTAssertNotNil(two)
        XCTAssertEqual(two?[1], two?[5])
        XCTAssertEqual((two ?? [:]).values.filter { $0 == .spades }.count, 4)
        XCTAssertEqual((two ?? [:]).values.filter { $0 == .hearts }.count, 4)

        // 1무늬: 모두 스페이드.
        let one = SpiderWinnable.assignSuits(components: comps4, suits: 1)
        XCTAssertEqual(Set((one ?? [:]).values), [.spades])

        // 4무늬에서 크기 3 덩어리는 나눌 수 없다.
        XCTAssertNil(SpiderWinnable.assignSuits(components: [[0, 1, 2], [3], [4], [5], [6], [7]],
                                                suits: 4))
    }

    private func layoutKey(_ game: Spider) -> String {
        var parts = game.tableau.map { pile in
            pile.map { "\($0.suit.rawValue)-\($0.rank)-\($0.faceup ? 1 : 0)" }
                .joined(separator: ",")
        }
        parts.append(game.stock.map { "\($0.suit.rawValue)-\($0.rank)" }.joined(separator: ","))
        return parts.joined(separator: "|")
    }
}
