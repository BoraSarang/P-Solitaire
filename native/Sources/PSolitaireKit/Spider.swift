// Spider.swift — 스파이더 규칙 이식(1·2·4무늬, 세트 수거, "무늬 상관없이" 옵션).

import Foundation

final class SpiderState: GameState {
    let stock: [PackedCard]
    let tableau: [[PackedCard]]
    let foundations: [[PackedCard]]
    let score: Int
    let moves: Int

    init(stock: [PackedCard], tableau: [[PackedCard]],
         foundations: [[PackedCard]], score: Int, moves: Int) {
        self.stock = stock
        self.tableau = tableau
        self.foundations = foundations
        self.score = score
        self.moves = moves
    }
}

/// 스파이더 한 판의 시작 배치 — 다시 시작·이어하기 때 같은 배치로 되돌린다.
public struct SpiderStartLayout: Codable, Sendable {
    public var seed: Int
    public var suits: Int
    public var tableau: [[PackedCard]]
    public var stock: [PackedCard]
    /// 풀리는 판으로 배분했다면 그때 찾은 해답(힌트용). 일반 배분은 nil.
    public var solution: [SpiderSolutionMove]?

    public init(seed: Int, suits: Int, tableau: [[PackedCard]], stock: [PackedCard],
                solution: [SpiderSolutionMove]? = nil) {
        self.seed = seed
        self.suits = suits
        self.tableau = tableau
        self.stock = stock
        self.solution = solution
    }
}

public final class Spider: BaseGame {
    public static let sets = 8
    public static let setSize = 13
    public override var kind: GameKind { .spider }
    public override var name: String { "스파이더" }
    public override var totalCards: Int { 104 }
    public override var columns: Int { 10 }
    public override var foundationsCount: Int { Spider.sets }
    public override var hasStock: Bool { true }
    public override var hasWaste: Bool { false }
    public override var hasFreecells: Bool { false }
    public override var groupLimitText: String {
        "무늬가 다르면 한 묶음으로 못 옮깁니다 (게임 → 묶음 이동)"
    }

    public private(set) var suits: Int
    /// 묶음 이동에서 무늬를 따지지 않는다(쉬움 설정).
    public private(set) var suitFree: Bool

    /// 이 판의 시작 배치(풀리는 판 포함). 다시 시작할 때 그대로 되돌린다.
    public internal(set) var startLayout: SpiderStartLayout?

    public init(seed: Int? = nil, suits: Int = 1, suitFree: Bool = false) {
        self.suits = (suits == 1 || suits == 2 || suits == 4) ? suits : 1
        self.suitFree = suitFree
        super.init()
        self.seed = seed ?? randomSeed()
        deal(seed: self.seed)
    }

    /// 묶음 이동 규칙만 바꾼다(판·점수는 그대로).
    public func setSuitFree(_ on: Bool) { suitFree = on }

    /// 풀리는 판을 적용할 때 무늬 수를 맞춘다(모듈 내부용).
    func updateSuits(_ value: Int) {
        suits = (value == 1 || value == 2 || value == 4) ? value : 1
    }

    // ── 배분 ───────────────────────────────────────────────────────────────
    public func deckSuits() -> [Suit] {
        switch suits {
        case 1: return [.spades]
        case 2: return [.spades, .hearts]
        default: return [.spades, .hearts, .diamonds, .clubs]
        }
    }

    /// 무늬 수에 맞춘 104장(2벌): 1무늬=♠ 8벌, 2무늬=각 4벌, 4무늬=각 2벌.
    public func buildDeck() -> [Card] {
        let suits = deckSuits()
        let copies = Spider.sets / suits.count
        var deck: [Card] = []
        for suit in suits {
            for _ in 0..<copies {
                for rank in 1...13 { deck.append(Card(rank: rank, suit: suit)) }
            }
        }
        return deck
    }

    /// 앞 4열은 6장, 나머지 6열은 5장(맨 위만 앞면). 남은 50장이 스톡(10장씩 5번).
    public override func deal(seed: Int?) {
        if let seed { self.seed = seed }
        var rng = SeededRandom(seed: self.seed)
        var deck = buildDeck()
        deck.shuffle(using: &rng)

        tableau = Array(repeating: [], count: columns)
        var idx = 0
        for col in 0..<columns {
            let n = col < 4 ? 6 : 5
            for k in 0..<n {
                let card = deck[idx]
                idx += 1
                card.faceup = (k == n - 1)
                tableau[col].append(card)
            }
        }
        stock = Array(deck[idx...])
        for card in stock { card.faceup = false }
        foundations = []                     // 완성된 세트(각 13장)
        freecells = []
        waste = []
        score = spiderBaseScore
        moves = 0
        clearUndo()
        captureStartLayout()
    }

    /// 지금 배치를 "시작 배치"로 기억한다(풀리는 판 적용 뒤에도 호출).
    func captureStartLayout() {
        startLayout = SpiderStartLayout(seed: seed, suits: suits,
                                        tableau: tableau.map(packPile),
                                        stock: packPile(stock))
    }

    /// 이어하기에서 읽은 시작 배치를 넣는다.
    public func setStartLayout(_ layout: SpiderStartLayout?) {
        startLayout = layout
    }

    /// 같은 판 다시 시작 — 시작 배치가 있으면 그 배치를 그대로 쓴다.
    public override func restart() {
        guard let layout = startLayout else {
            super.restart()
            return
        }
        seed = layout.seed
        updateSuits(layout.suits)
        tableau = layout.tableau.map(unpackPile)
        stock = layout.stock.map { Card(rank: $0.rank, suit: $0.suit, faceup: false) }
        foundations = []
        freecells = []
        waste = []
        score = spiderBaseScore
        moves = 0
        clearUndo()
    }

    /// 스톡에 남은 배분 횟수.
    public func dealsLeft() -> Int { stock.count / columns }

    // ── 실행 취소 ──────────────────────────────────────────────────────────
    override func makeSnapshot() -> GameState {
        SpiderState(stock: packPile(stock), tableau: tableau.map(packPile),
                    foundations: foundations.map(packPile), score: score, moves: moves)
    }

    override func applySnapshot(_ state: GameState) {
        guard let s = state as? SpiderState else { return }
        stock = unpackPile(s.stock)
        tableau = s.tableau.map(unpackPile)
        foundations = s.foundations.map(unpackPile)
        score = s.score
        moves = s.moves
    }

    // ── 규칙 검사 ──────────────────────────────────────────────────────────
    /// 스파이더 묶음 규칙: 같은 무늬 내림차순(쉬움 설정이면 숫자만).
    public override func groupRun(_ ref: Ref, index: Int) -> [Card]? {
        runFrom(ref, index: index, sameSuit: !suitFree, rankOnly: suitFree)
    }

    /// index부터 열 맨 위까지 이어지는 묶음을 집는다(기본은 같은 무늬 내림차순만).
    ///
    /// 무늬가 다른 카드가 위에 덮여 있으면 그 카드는 집을 수 없다(위 카드를 먼저
    /// 옮겨야 한다 — MS 규칙).
    public override func pick(_ ref: Ref, index: Int) -> [Card]? {
        guard ref.kind == .tableau else { return nil }   // 스톡·완성 세트는 집을 수 없다
        return pickWhole(ref, index: index)
    }

    public override func canDrop(_ cards: [Card], _ dst: Ref) -> Bool {
        guard let first = cards.first, dst.kind == .tableau,
              dst.index >= 0, dst.index < tableau.count else { return false }
        let pile = tableau[dst.index]
        guard let top = pile.last else { return true }   // 빈 열에는 아무 카드나
        guard top.faceup else { return false }
        return first.rank == top.rank - 1
    }

    // ── 이동/조작 ──────────────────────────────────────────────────────────
    public override func move(_ src: Ref, index: Int, _ dst: Ref) -> MoveResult {
        if src == dst { return .fail("같은 위치로는 옮길 수 없습니다.") }
        guard let run = pick(src, index: index) else { return .fail("그 카드는 집을 수 없습니다.") }
        guard canDrop(run, dst) else { return .fail("거기에 놓을 수 없습니다.") }

        pushUndo()
        tableau[src.index].removeSubrange(index..<(index + run.count))
        for card in run { card.faceup = true }
        tableau[dst.index].append(contentsOf: run)

        var flipped = false
        let srcPile = tableau[src.index]
        if let last = srcPile.last, !last.faceup {
            last.faceup = true
            flipped = true
        }

        moves += 1
        score += spiderScorePerMove
        let gained = collectSets()
        return MoveResult(ok: true, points: spiderScorePerMove + gained, flipped: flipped,
                          count: run.count, sets: gained / spiderScorePerSet)
    }

    /// 바닥에 K→A 같은 무늬 13장이 모이면 자동으로 걷어낸다(얻은 점수 반환).
    @discardableResult
    public func collectSets() -> Int {
        var gained = 0
        for i in tableau.indices {
            var pile = tableau[i]
            guard pile.count >= Spider.setSize else { continue }
            let run = Array(pile.suffix(Spider.setSize))
            guard run.allSatisfy({ $0.faceup }) else { continue }
            guard Set(run.map { $0.suit }).count == 1 else { continue }
            guard run.map({ $0.rank }) == Array((1...13).reversed()) else { continue }
            pile.removeLast(Spider.setSize)
            if let top = pile.last, !top.faceup { top.faceup = true }   // 드러난 카드는 뒤집는다
            tableau[i] = pile
            foundations.append(run)
            gained += spiderScorePerSet
        }
        score += gained
        return gained
    }

    /// 스톡에서 10장을 돌려 각 열에 한 장씩 놓는다(빈 열이 있으면 못 돌린다).
    public override func drawFromStock() -> MoveResult {
        if stock.isEmpty { return .fail("스톡이 비었습니다.") }
        if tableau.contains(where: { $0.isEmpty }) {
            return .fail("빈 열이 있으면 카드를 돌릴 수 없습니다.")
        }
        pushUndo()
        let n = min(columns, stock.count)
        for i in 0..<n {
            let card = stock.removeLast()
            card.faceup = true
            tableau[i].append(card)
        }
        moves += 1
        score += spiderScorePerMove
        let gained = collectSets()
        return MoveResult(ok: true, points: spiderScorePerMove + gained, count: n,
                          sets: gained / spiderScorePerSet, action: "deal")
    }

    // ── 자동 이동/힌트 ─────────────────────────────────────────────────────
    /// 더블클릭: 같은 무늬로 이어지거나 카드를 드러내는 자리로 옮긴다.
    public override func autoMove(_ ref: Ref, index: Int) -> MoveResult? {
        guard let run = pick(ref, index: index), !run.isEmpty, ref.kind == .tableau else { return nil }
        let pile = tableau[ref.index]
        var best: Int?
        var bestGain = 0
        for ti in 0..<columns {
            if ti == ref.index || !canDrop(run, Ref(.tableau, ti)) { continue }
            let target = tableau[ti]
            var gain = 0
            if let top = target.last, top.suit == run[0].suit { gain += 3 }
            if index > 0 && !pile[index - 1].faceup { gain += 4 }
            if index == 0 && !target.isEmpty { gain += 2 }
            if gain > bestGain {
                bestGain = gain
                best = ti
            }
        }
        guard let best else { return nil }
        return move(ref, index: index, Ref(.tableau, best))
    }

    /// 풀리는 판으로 시작했다면 배분할 때 찾아 둔 해답을 그대로 안내한다.
    ///
    /// 해답 경로 위에 있는 판이면 다음 수가 곧 이기는 수다. 플레이어가 해답에서
    /// 벗어났으면 nil 을 돌려주고, 호출 쪽이 탐색기(`searchHint`)로 넘어간다.
    public func planHint() -> Hint? {
        guard let layout = startLayout, let solution = layout.solution, !solution.isEmpty else {
            return nil
        }
        let probe = Spider(seed: layout.seed, suits: layout.suits)
        probe.tableau = layout.tableau.map(unpackPile)
        probe.stock = layout.stock.map { Card(rank: $0.rank, suit: $0.suit, faceup: false) }
        probe.foundations = []
        probe.freecells = []
        probe.waste = []

        if sameBoard(as: probe) { return planHint(for: solution[0]) }
        for (i, move) in solution.enumerated() {
            let ok: Bool
            switch move {
            case .deal:
                ok = probe.drawFromStock().ok
            case .move(let src, let index, let dst):
                ok = probe.move(Ref(.tableau, src), index: index, Ref(.tableau, dst)).ok
            }
            guard ok else { return nil }
            if sameBoard(as: probe) {
                return i + 1 < solution.count ? planHint(for: solution[i + 1]) : nil
            }
        }
        return nil
    }

    private func sameBoard(as other: Spider) -> Bool {
        guard stock.count == other.stock.count,
              foundations.count == other.foundations.count,
              tableau.count == other.tableau.count else { return false }
        for i in tableau.indices where !samePile(tableau[i], other.tableau[i]) { return false }
        return samePile(stock, other.stock)
    }

    private func samePile(_ a: [Card], _ b: [Card]) -> Bool {
        guard a.count == b.count else { return false }
        for i in a.indices where a[i].rank != b[i].rank || a[i].suit != b[i].suit
            || a[i].faceup != b[i].faceup {
            return false
        }
        return true
    }

    private func planHint(for move: SpiderSolutionMove) -> Hint? {
        switch move {
        case .deal:
            return stock.isEmpty ? nil : .draw
        case .move(let src, let index, let dst):
            guard src < tableau.count, dst < tableau.count,
                  index >= 0, index < tableau[src].count else { return nil }
            return .move(src: Ref(.tableau, src), index: index, dst: Ref(.tableau, dst))
        }
    }

    public override func hint() -> Hint? {
        var best: Hint?
        var bestGain = 0
        for (si, pile) in tableau.enumerated() {
            for i in 0..<pile.count {
                guard let run = pick(Ref(.tableau, si), index: i), !run.isEmpty else { continue }
                for ti in 0..<columns {
                    if ti == si || !canDrop(run, Ref(.tableau, ti)) { continue }
                    let target = tableau[ti]
                    var gain = 0
                    if let top = target.last, top.suit == run[0].suit { gain += 3 }
                    if i > 0 && !pile[i - 1].faceup { gain += 4 }
                    if i == 0 && !target.isEmpty { gain += 2 }
                    if gain > bestGain {
                        bestGain = gain
                        best = .move(src: Ref(.tableau, si), index: i, dst: Ref(.tableau, ti))
                    }
                }
            }
        }
        if let best { return best }
        if !stock.isEmpty && !tableau.contains(where: { $0.isEmpty }) { return .draw }
        return nil
    }

    public override func summary() -> String {
        "완성 \(foundations.count)/\(Spider.sets) · 스톡 \(dealsLeft())번 · 남은 카드 \(cardsRemaining())"
    }
}
