// Klondike.swift — 클론다이크(MS "클래식 솔리테어") 규칙 이식.

import Foundation

final class KlondikeState: GameState {
    let stock: [PackedCard]
    let waste: [PackedCard]
    let foundations: [[PackedCard]]
    let tableau: [[PackedCard]]
    let score: Int
    let moves: Int

    init(stock: [PackedCard], waste: [PackedCard], foundations: [[PackedCard]],
         tableau: [[PackedCard]], score: Int, moves: Int) {
        self.stock = stock
        self.waste = waste
        self.foundations = foundations
        self.tableau = tableau
        self.score = score
        self.moves = moves
    }
}

public final class Klondike: BaseGame {
    public override var kind: GameKind { .klondike }
    public override var name: String { "클론다이크" }
    public override var columns: Int { 7 }
    public override var foundationsCount: Int { 4 }
    public override var hasStock: Bool { true }
    public override var hasWaste: Bool { true }
    public override var hasFreecells: Bool { false }

    public private(set) var drawCount: Int

    /// 카드 넘기기 장수를 바꾼다(1 또는 3).
    public func setDrawCount(_ count: Int) {
        drawCount = (count == 1 || count == 3) ? count : 3
    }

    public init(seed: Int? = nil, drawCount: Int = 3) {
        self.drawCount = (drawCount == 1 || drawCount == 3) ? drawCount : 3
        super.init()
        self.seed = seed ?? randomSeed()
        deal(seed: self.seed)
    }

    // ── 배분 ───────────────────────────────────────────────────────────────
    public override func deal(seed: Int?) {
        if let seed { self.seed = seed }
        var rng = SeededRandom(seed: self.seed)
        var deck = makeDeck()
        deck.shuffle(using: &rng)

        stock = []
        waste = []
        foundations = Array(repeating: [], count: 4)
        tableau = Array(repeating: [], count: 7)

        var idx = 0
        for col in 0..<7 {                          // 0열 1장 … 6열 7장
            for k in 0...col {
                let card = deck[idx]
                idx += 1
                card.faceup = (k == col)            // 맨 위 한 장만 앞면
                tableau[col].append(card)
            }
        }
        for card in deck[idx...] {                   // 남은 24장이 스톡
            card.faceup = false
            stock.append(card)
        }

        score = 0
        moves = 0
        clearUndo()
    }

    // ── 실행 취소 ──────────────────────────────────────────────────────────
    override func makeSnapshot() -> GameState {
        KlondikeState(stock: packPile(stock), waste: packPile(waste),
                      foundations: foundations.map(packPile), tableau: tableau.map(packPile),
                      score: score, moves: moves)
    }

    override func applySnapshot(_ state: GameState) {
        guard let s = state as? KlondikeState else { return }
        stock = unpackPile(s.stock)
        waste = unpackPile(s.waste)
        foundations = s.foundations.map(unpackPile)
        tableau = s.tableau.map(unpackPile)
        score = s.score
        moves = s.moves
    }

    // ── 규칙 검사 ──────────────────────────────────────────────────────────
    public override func pick(_ ref: Ref, index: Int) -> [Card]? {
        switch ref.kind {
        case .tableau:
            return pickWhole(ref, index: index)
        case .waste:
            guard !waste.isEmpty else { return nil }
            if index == -1 || index == waste.count - 1 { return [waste[waste.count - 1]] }
            return nil
        case .foundation:
            guard ref.index >= 0, ref.index < foundations.count else { return nil }
            let pile = foundations[ref.index]
            guard !pile.isEmpty else { return nil }
            if index == -1 || index == pile.count - 1 { return [pile[pile.count - 1]] }
            return nil
        default:
            return nil
        }
    }

    public override func canDrop(_ cards: [Card], _ dst: Ref) -> Bool {
        guard let first = cards.first else { return false }
        switch dst.kind {
        case .tableau:
            guard dst.index >= 0, dst.index < tableau.count else { return false }
            let pile = tableau[dst.index]
            guard let top = pile.last else { return first.rank == 13 }   // 빈 열에는 K만
            guard top.faceup else { return false }
            return first.rank == top.rank - 1 && first.isRed != top.isRed
        case .foundation:
            guard cards.count == 1, dst.index >= 0, dst.index < foundations.count else { return false }
            let pile = foundations[dst.index]
            guard let top = pile.last else { return first.rank == 1 }    // 빈 칸에는 A만
            return first.suit == top.suit && first.rank == top.rank + 1
        default:
            return false
        }
    }

    // ── 이동/조작 ──────────────────────────────────────────────────────────
    public override func move(_ src: Ref, index: Int, _ dst: Ref) -> MoveResult {
        if src == dst { return .fail("같은 위치로는 옮길 수 없습니다.") }
        guard let run = pick(src, index: index) else { return .fail("그 카드는 집을 수 없습니다.") }
        guard canDrop(run, dst) else { return .fail("거기에 놓을 수 없습니다.") }

        pushUndo()
        var points = 0

        // 원래 더미에서 떼어내기
        switch src.kind {
        case .tableau:
            tableau[src.index].removeSubrange(index..<(index + run.count))
        case .waste:
            waste.removeLast()
        case .foundation:
            foundations[src.index].removeLast()
        default:
            break
        }

        // 대상 더미에 놓기
        for card in run { card.faceup = true }
        if dst.kind == .tableau {
            tableau[dst.index].append(contentsOf: run)
        } else if dst.kind == .foundation {
            foundations[dst.index].append(contentsOf: run)
        }

        // 점수 계산
        if dst.kind == .foundation {
            points += scoreToFoundation
        } else if src.kind == .waste {
            points += scoreWasteToTableau
        } else if src.kind == .foundation {
            points += scoreFoundationToTableau
        }

        // 원래 열에서 뒤집힌 카드가 드러나면 자동으로 공개한다.
        var flipped = false
        if src.kind == .tableau {
            let pile = tableau[src.index]
            if let last = pile.last, !last.faceup {
                last.faceup = true
                flipped = true
                points += scoreFlip
            }
        }

        score += points
        moves += 1
        return MoveResult(ok: true, points: points, flipped: flipped, count: run.count)
    }

    public override func drawFromStock() -> MoveResult {
        if !stock.isEmpty {
            pushUndo()
            let n = min(drawCount, stock.count)
            for _ in 0..<n {
                let card = stock.removeLast()
                card.faceup = true
                waste.append(card)
            }
            moves += 1
            return MoveResult(ok: true, points: 0, count: n, action: "draw")
        }
        if !waste.isEmpty {
            pushUndo()
            let penalty = (drawCount == 3) ? scoreRecycleDrawThree : 0
            while let card = waste.popLast() {
                card.faceup = false
                stock.append(card)
            }
            score += penalty
            moves += 1
            return MoveResult(ok: true, points: penalty, count: stock.count, action: "recycle")
        }
        return .fail("스톡과 웨이스트가 모두 비었습니다.")
    }

    /// 태블로 맨 위의 뒤집힌 카드를 공개한다(+5점).
    public override func flipTop(_ ref: Ref) -> Bool {
        guard ref.kind == .tableau, ref.index >= 0, ref.index < tableau.count else { return false }
        let pile = tableau[ref.index]
        guard let last = pile.last, !last.faceup else { return false }
        pushUndo()
        last.faceup = true
        score += scoreFlip
        moves += 1
        return true
    }

    // ── 자동 이동/힌트 ─────────────────────────────────────────────────────
    public override func findFoundationMove() -> (src: Ref, index: Int, dst: Ref)? {
        for fi in 0..<4 {
            let dst = Ref(.foundation, fi)
            if let top = waste.last, canDrop([top], dst) {
                return (Ref(.waste, 0), waste.count - 1, dst)
            }
            for ti in 0..<7 {
                guard let top = tableau[ti].last, canDrop([top], dst) else { continue }
                return (Ref(.tableau, ti), tableau[ti].count - 1, dst)
            }
        }
        return nil
    }

    /// 더블클릭용: 파운데이션 우선, 그다음 카드를 드러내는 태블로 이동.
    public override func autoMove(_ ref: Ref, index: Int) -> MoveResult? {
        guard let run = pick(ref, index: index), !run.isEmpty else { return nil }

        if run.count == 1, let fi = foundationSlotFor(run[0]) {
            return move(ref, index: index, Ref(.foundation, fi))
        }
        guard run.count == 1 || ref.kind == .tableau else { return nil }

        var best: Int?
        var bestGain = 0
        for di in 0..<7 {
            if ref.kind == .tableau && di == ref.index { continue }
            guard canDrop(run, Ref(.tableau, di)) else { continue }
            var gain = 0
            if ref.kind == .tableau {
                let pile = tableau[ref.index]
                if index > 0 && !pile[index - 1].faceup {
                    gain += 3                       // 카드가 드러난다
                } else if index == 0 && !tableau[di].isEmpty
                            && !pile.contains(where: { !$0.faceup }) {
                    gain += 1                       // 열을 비운다(빈 열끼리 K 옮기기는 제외)
                }
            }
            if gain > bestGain {
                bestGain = gain
                best = di
            }
        }
        if let best { return move(ref, index: index, Ref(.tableau, best)) }
        return nil
    }

    /// 모든 카드가 공개되어 자동 완성을 쓸 수 있는 상태인가.
    public override func canAutoComplete() -> Bool {
        if !stock.isEmpty { return false }
        return tableau.allSatisfy { $0.allSatisfy { $0.faceup } }
    }

    public override func hint() -> Hint? {
        if let found = findFoundationMove() {
            return .move(src: found.src, index: found.index, dst: found.dst)
        }

        var best: Hint?
        var bestGain = 0
        for si in 0..<7 {
            let pile = tableau[si]
            for i in 0..<pile.count {
                guard let run = pick(Ref(.tableau, si), index: i), !run.isEmpty else { continue }
                for di in 0..<7 {
                    if di == si || !canDrop(run, Ref(.tableau, di)) { continue }
                    var gain = 0
                    if i > 0 && !pile[i - 1].faceup {
                        gain += 3                   // 카드가 드러난다
                    } else if i == 0 && !tableau[di].isEmpty
                                && !pile.contains(where: { !$0.faceup }) {
                        gain += 1                   // 열을 비운다(빈 열끼리 K 옮기기는 제외)
                    }
                    if gain > bestGain {
                        bestGain = gain
                        best = .move(src: Ref(.tableau, si), index: i, dst: Ref(.tableau, di))
                    }
                }
            }
        }
        if let best { return best }

        if let card = waste.last {
            for di in 0..<7 where canDrop([card], Ref(.tableau, di)) {
                return .move(src: Ref(.waste, 0), index: waste.count - 1, dst: Ref(.tableau, di))
            }
        }
        if !stock.isEmpty { return .draw }
        if !waste.isEmpty { return .recycle }
        return nil
    }

    public override func summary() -> String {
        "스톡 \(stock.count) · 남은 카드 \(cardsRemaining())"
    }
}
