// FreeCell.swift — 프리셀 규칙 이식(프리셀 4칸 + 슈퍼무브).

import Foundation

final class FreeCellState: GameState {
    let tableau: [[PackedCard]]
    let freecells: [[PackedCard]]
    let foundations: [[PackedCard]]
    let score: Int
    let moves: Int

    init(tableau: [[PackedCard]], freecells: [[PackedCard]],
         foundations: [[PackedCard]], score: Int, moves: Int) {
        self.tableau = tableau
        self.freecells = freecells
        self.foundations = foundations
        self.score = score
        self.moves = moves
    }
}

public final class FreeCell: BaseGame {
    public static let freeCellCount = 4

    public override var kind: GameKind { .freecell }
    public override var name: String { "프리셀" }
    public override var columns: Int { 8 }
    public override var foundationsCount: Int { 4 }
    public override var hasStock: Bool { false }
    public override var hasWaste: Bool { false }
    public override var hasFreecells: Bool { true }

    public init(seed: Int? = nil) {
        super.init()
        self.seed = seed ?? randomSeed()
        deal(seed: self.seed)
    }

    // ── 배분 ───────────────────────────────────────────────────────────────
    /// 카드를 섞어 8열에 왼쪽부터 한 장씩 돌아가며 놓는다(모두 앞면).
    public override func deal(seed: Int?) {
        if let seed { self.seed = seed }
        var rng = SeededRandom(seed: self.seed)
        var deck = makeDeck()
        deck.shuffle(using: &rng)

        tableau = Array(repeating: [], count: columns)
        for (i, card) in deck.enumerated() {
            card.faceup = true
            tableau[i % columns].append(card)
        }
        freecells = Array(repeating: [], count: FreeCell.freeCellCount)
        foundations = Array(repeating: [], count: foundationsCount)
        stock = []
        waste = []
        score = 0
        moves = 0
        clearUndo()
    }

    // ── 실행 취소 ──────────────────────────────────────────────────────────
    override func makeSnapshot() -> GameState {
        FreeCellState(tableau: tableau.map(packPile), freecells: freecells.map(packPile),
                      foundations: foundations.map(packPile), score: score, moves: moves)
    }

    override func applySnapshot(_ state: GameState) {
        guard let s = state as? FreeCellState else { return }
        tableau = s.tableau.map(unpackPile)
        freecells = s.freecells.map(unpackPile)
        foundations = s.foundations.map(unpackPile)
        score = s.score
        moves = s.moves
    }

    // ── 규칙 검사 ──────────────────────────────────────────────────────────
    public override func pick(_ ref: Ref, index: Int) -> [Card]? {
        switch ref.kind {
        case .tableau:
            return pickWhole(ref, index: index)
        case .freecell:
            guard ref.index >= 0, ref.index < freecells.count else { return nil }
            let cell = freecells[ref.index]
            return cell.isEmpty ? nil : [cell[cell.count - 1]]
        case .foundation:
            guard ref.index >= 0, ref.index < foundations.count else { return nil }
            let pile = foundations[ref.index]
            if !pile.isEmpty && (index == -1 || index == pile.count - 1) {
                return [pile[pile.count - 1]]
            }
            return nil
        default:
            return nil
        }
    }

    /// 한 번에 옮길 수 있는 카드 수(빈 프리셀·빈 열을 경유).
    public func maxMove(_ dst: Ref? = nil) -> Int {
        var empty = tableau.filter { $0.isEmpty }.count
        let free = freeCellsFree()
        if let dst, dst.kind == .tableau, dst.index < tableau.count,
           tableau[dst.index].isEmpty, empty > 0 {
            empty -= 1                       // 옮겨 갈 빈 열은 경유지로 쓸 수 없다
        }
        return (free + 1) * (1 << max(0, empty))
    }

    public override func canDrop(_ cards: [Card], _ dst: Ref) -> Bool {
        guard let first = cards.first else { return false }
        switch dst.kind {
        case .freecell:
            guard dst.index >= 0, dst.index < freecells.count else { return false }
            return cards.count == 1 && freecells[dst.index].isEmpty
        case .foundation:
            guard cards.count == 1, dst.index >= 0, dst.index < foundations.count else { return false }
            let pile = foundations[dst.index]
            guard let top = pile.last else { return first.rank == 1 }
            return first.suit == top.suit && first.rank == top.rank + 1
        case .tableau:
            guard dst.index >= 0, dst.index < tableau.count else { return false }
            if cards.count > maxMove(dst) { return false }
            let pile = tableau[dst.index]
            guard let top = pile.last else { return true }       // 빈 열에는 아무 카드나
            guard top.faceup else { return false }
            return first.rank == top.rank - 1 && first.isRed != top.isRed
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
        switch src.kind {
        case .tableau:
            tableau[src.index].removeSubrange(index..<(index + run.count))
        case .freecell:
            freecells[src.index].removeLast()
        case .foundation:
            foundations[src.index].removeLast()
        default:
            break
        }

        for card in run { card.faceup = true }
        switch dst.kind {
        case .tableau:
            tableau[dst.index].append(contentsOf: run)
        case .freecell:
            freecells[dst.index].append(contentsOf: run)
        case .foundation:
            foundations[dst.index].append(contentsOf: run)
        default:
            break
        }

        moves += 1
        return MoveResult(ok: true, points: 0, flipped: false, count: run.count)
    }

    public override func drawFromStock() -> MoveResult {
        .fail("프리셀에는 스톡이 없습니다.")
    }

    // ── 자동 이동/힌트 ─────────────────────────────────────────────────────
    public override func findFoundationMove() -> (src: Ref, index: Int, dst: Ref)? {
        for fi in 0..<foundationsCount {
            let dst = Ref(.foundation, fi)
            for (ci, cell) in freecells.enumerated() {
                if let card = cell.last, canDrop([card], dst) {
                    return (Ref(.freecell, ci), cell.count - 1, dst)
                }
            }
            for (ti, pile) in tableau.enumerated() {
                if let card = pile.last, canDrop([card], dst) {
                    return (Ref(.tableau, ti), pile.count - 1, dst)
                }
            }
        }
        return nil
    }

    /// 더블클릭: 파운데이션 → 태블로 → 빈 프리셀 순으로 보낸다.
    public override func autoMove(_ ref: Ref, index: Int) -> MoveResult? {
        guard let run = pick(ref, index: index), !run.isEmpty else { return nil }
        if run.count == 1, let fi = foundationSlotFor(run[0]) {
            return move(ref, index: index, Ref(.foundation, fi))
        }

        var best: Int?
        var bestGain = 0
        for ti in 0..<columns {
            if ref.kind == .tableau && ti == ref.index { continue }
            guard canDrop(run, Ref(.tableau, ti)) else { continue }
            var gain = 0
            if ref.kind == .tableau && index == 0 && !tableau[ti].isEmpty { gain += 2 }
            if ref.kind == .freecell { gain += 1 }
            if gain > bestGain {
                bestGain = gain
                best = ti
            }
        }
        if let best { return move(ref, index: index, Ref(.tableau, best)) }

        if ref.kind != .freecell && run.count == 1 {
            for (ci, cell) in freecells.enumerated() where cell.isEmpty {
                return move(ref, index: index, Ref(.freecell, ci))
            }
        }
        return nil
    }

    /// 프리셀이 비어 있고 모든 열이 내림차순이면 끝까지 정리할 수 있다.
    public override func canAutoComplete() -> Bool {
        if freeCellsFree() != FreeCell.freeCellCount { return false }
        for pile in tableau {
            for (lower, upper) in zip(pile, pile.dropFirst()) where lower.rank != upper.rank + 1 {
                return false
            }
        }
        return true
    }

    public override func hint() -> Hint? {
        if let found = findFoundationMove() {
            return .move(src: found.src, index: found.index, dst: found.dst)
        }

        for (ci, cell) in freecells.enumerated() {          // 프리셀 카드를 쓸 자리
            guard let card = cell.last else { continue }
            for ti in 0..<columns where canDrop([card], Ref(.tableau, ti)) {
                return .move(src: Ref(.freecell, ci), index: 0, dst: Ref(.tableau, ti))
            }
        }

        var best: Hint?
        var bestGain = 0
        for (si, pile) in tableau.enumerated() {
            for i in 0..<pile.count {
                guard let run = pick(Ref(.tableau, si), index: i), !run.isEmpty else { continue }
                for ti in 0..<columns {
                    if ti == si || !canDrop(run, Ref(.tableau, ti)) { continue }
                    let gain = (i == 0 && !tableau[ti].isEmpty) ? 2 : 1
                    if gain > bestGain {
                        bestGain = gain
                        best = .move(src: Ref(.tableau, si), index: i, dst: Ref(.tableau, ti))
                    }
                }
            }
        }
        if let best { return best }

        for (si, pile) in tableau.enumerated() {            // 마지막 수단: 프리셀 비우기
            guard !pile.isEmpty else { continue }
            for (ci, cell) in freecells.enumerated() where cell.isEmpty {
                return .move(src: Ref(.tableau, si), index: pile.count - 1, dst: Ref(.freecell, ci))
            }
        }
        return nil
    }

    public override func summary() -> String {
        "프리셀 \(freeCellsFree())칸 비어 있음 · 남은 카드 \(cardsRemaining())"
    }
}
