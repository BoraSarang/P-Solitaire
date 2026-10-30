// HintSolver.swift — 힌트용 해답 탐색기.
//
// 기존 `hint()` 는 "지금 둘 수 있는 한 수"를 점수로만 고르기 때문에
// A→B, B→A 같은 왕복 수를 계속 추천할 수 있다. 이 파일은 현재 판에서
// 이기는 줄을 직접 찾아 그 첫 수를 힌트로 돌려준다.
//
// 결과는 세 가지다.
//   .solved(해답)  : 이기는 줄을 찾았다(첫 수가 힌트).
//   .impossible    : 모든 도달 가능한 상태를 살펴봤는데 이기는 줄이 없다.
//   .unknown       : 시간·노드 한도 안에 결론을 내지 못했다.
//
// 탐색은 최선 우선(best-first)이며, 상태는 카드 배열을 압축해 보관한다.
// UI는 이 계산을 백그라운드에서 돌리고, 결과가 돌아왔을 때 판이 그대로인지
// 스냅숏으로 확인한 뒤에만 화면에 반영한다.

import Foundation

// MARK: - 공개 결과

public enum HintSearchResult: Sendable, Equatable {
    /// 이기는 줄(첫 수가 화면에 표시할 힌트).
    case solved([Hint])
    /// 탐색을 끝까지 마쳤고 이기는 줄이 없다.
    case impossible
    /// 시간·노드 한도에 걸려 결론을 내리지 못했다.
    case unknown
}

// MARK: - 공개 진입점

public enum HintSolver {
    /// 게임별 탐색 예산. 화면을 오래 붙잡지 않으면서 대부분의 판을 풀 만큼만 준다.
    public static func budget(for kind: GameKind) -> (time: TimeInterval, nodes: Int) {
        switch kind {
        case .freecell: return (1.5, 250_000)
        case .klondike: return (2.5, 400_000)
        case .spider: return (3.0, 600_000)
        }
    }

    /// 현재 판 스냅숏에서 이기는 줄을 찾는다.
    ///
    /// - Parameters:
    ///   - timeLimit: 벽시계 기준 탐색 시간(초).
    ///   - nodeLimit: 만들어 둘 상태 수 상한(메모리 보호).
    public static func solve(kind: GameKind, snapshot: GameSnapshot,
                             drawCount: Int = 3, suits: Int = 1, suitFree: Bool = false,
                             timeLimit: TimeInterval = 0.9,
                             nodeLimit: Int = 140_000) -> HintSearchResult {
        switch kind {
        case .freecell:
            return solveFreeCell(snapshot, timeLimit: timeLimit, nodeLimit: nodeLimit)
        case .klondike:
            return solveKlondike(snapshot, drawCount: drawCount,
                                 timeLimit: timeLimit, nodeLimit: nodeLimit)
        case .spider:
            return solveSpider(snapshot, suits: suits, suitFree: suitFree,
                               timeLimit: timeLimit, nodeLimit: nodeLimit)
        }
    }
}

// MARK: - 카드 압축

// 카드 한 장을 UInt8 로 줄인다.
//   bit 0~3: 숫자(1~13), bit 4~5: 무늬(0~3), bit 7: 앞면
@inline(__always) private func pack(_ card: PackedCard, faceUp: Bool? = nil) -> UInt8 {
    let up = (faceUp ?? card.faceup) ? 0x80 : 0
    return UInt8(card.rank & 0x0F) | UInt8((card.suit.rawValue & 0x03) << 4) | UInt8(up)
}

@inline(__always) private func rank(_ b: UInt8) -> Int { Int(b & 0x0F) }
@inline(__always) private func suit(_ b: UInt8) -> Int { Int((b >> 4) & 0x03) }
@inline(__always) private func isUp(_ b: UInt8) -> Bool { b & 0x80 != 0 }
@inline(__always) private func up(_ b: UInt8) -> UInt8 { b | 0x80 }
@inline(__always) private func down(_ b: UInt8) -> UInt8 { b & 0x7F }
@inline(__always) private func isRed(_ b: UInt8) -> Bool { let s = suit(b); return s == 1 || s == 2 }
@inline(__always) private func sameColor(_ a: UInt8, _ b: UInt8) -> Bool { isRed(a) == isRed(b) }

private func pileCards(_ pile: [PackedCard], faceUp: Bool? = nil) -> [UInt8] {
    pile.map { pack($0, faceUp: faceUp) }
}

private func tableColumns(_ piles: [[PackedCard]], count: Int,
                          faceUp: Bool? = nil) -> (lengths: [UInt8], cards: [UInt8]) {
    var lengths = [UInt8](repeating: 0, count: count)
    var cards: [UInt8] = []
    for i in 0..<count {
        let pile = i < piles.count ? piles[i] : []
        lengths[i] = UInt8(min(pile.count, 255))
        cards.append(contentsOf: pileCards(pile, faceUp: faceUp))
    }
    return (lengths, cards)
}

private func foundationPiles(_ piles: [[PackedCard]], count: Int)
    -> (tops: [UInt8], suits: [Int8]) {
    var tops = [UInt8](repeating: 0, count: count)
    var suits = [Int8](repeating: -1, count: count)
    for i in 0..<count where i < piles.count {
        if let top = piles[i].last {
            tops[i] = UInt8(top.rank)
            suits[i] = Int8(top.suit.rawValue)
        }
    }
    return (tops, suits)
}

// MARK: - 공통 최선 우선 탐색

private struct SearchNode<S, M> {
    let parent: Int?
    let moves: [M]?
    let depth: Int
    let state: S
}

private struct SearchHeap {
    struct Item {
        let order: Int      // 작을수록 먼저
        let depth: Int
        let seq: Int
        let index: Int
    }

    private var items: [Item] = []

    mutating func push(_ item: Item) {
        items.append(item)
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if less(items[i], items[p]) {
                items.swapAt(p, i)
                i = p
            } else {
                break
            }
        }
    }

    mutating func pop() -> Item? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = i * 2 + 1
                let r = l + 1
                var best = i
                if l < items.count, less(items[l], items[best]) { best = l }
                if r < items.count, less(items[r], items[best]) { best = r }
                if best == i { break }
                items.swapAt(i, best)
                i = best
            }
        }
        return top
    }

    private func less(_ a: Item, _ b: Item) -> Bool {
        if a.order != b.order { return a.order < b.order }
        if a.depth != b.depth { return a.depth < b.depth }
        return a.seq < b.seq
    }
}

private func bestFirst<S: Hashable, K: Hashable, M>(
    start: S,
    key: (S) -> K,
    normalize: (S) -> (S, [M]),
    isWin: (S) -> Bool,
    heuristic: (S) -> Int,
    moves: (S) -> [M],
    apply: (S, M) -> S,
    hint: (S, M) -> Hint,
    timeLimit: TimeInterval,
    nodeLimit: Int
) -> HintSearchResult {
    let (startState, startMoves) = normalize(start)
    var startHints: [Hint] = []
    if !startMoves.isEmpty {
        var replay = start
        for move in startMoves {
            startHints.append(hint(replay, move))
            replay = apply(replay, move)
        }
    }
    if isWin(startState) { return .solved(startHints) }

    let deadline = Date().addingTimeInterval(max(0.02, timeLimit))
    let capacity = max(1, min(nodeLimit, 1_000_000))
    var seen = Set<K>()
    seen.reserveCapacity(min(capacity, 120_000))
    seen.insert(key(startState))
    var nodes: [SearchNode<S, M>] = [
        SearchNode(parent: nil, moves: nil, depth: 0, state: startState)
    ]
    nodes.reserveCapacity(min(capacity, 120_000))
    var heap = SearchHeap()
    heap.push(.init(order: -heuristic(startState) * 2, depth: 0, seq: 0, index: 0))
    var seq = 1
    var tick = 0

    while let item = heap.pop() {
        let node = nodes[item.index]
        if isWin(node.state) {
            var hints = startHints
            var index = item.index
            var chain: [(state: S, moves: [M])] = []
            while let parent = nodes[index].parent {
                if let moves = nodes[index].moves {
                    chain.append((nodes[parent].state, moves))
                }
                index = parent
            }
            for (state, moves) in chain.reversed() {
                var replay = state
                for move in moves {
                    hints.append(hint(replay, move))
                    replay = apply(replay, move)
                }
            }
            return .solved(hints)
        }
        if nodes.count >= capacity { return .unknown }
        tick += 1
        if tick & 63 == 0, Date() >= deadline { return .unknown }

        for move in moves(node.state) {
            let raw = apply(node.state, move)
            var child = raw
            var pathMoves = [move]
            let normalized = normalize(raw)
            child = normalized.0
            if !normalized.1.isEmpty {
                pathMoves.append(contentsOf: normalized.1)
            }
            guard seen.insert(key(child)).inserted else { continue }
            let depth = node.depth + pathMoves.count
            let priority = heuristic(child) * 2 - depth
            nodes.append(SearchNode(parent: item.index, moves: pathMoves,
                                     depth: depth, state: child))
            heap.push(.init(order: -priority, depth: depth, seq: seq, index: nodes.count - 1))
            seq += 1
            if nodes.count >= capacity { return .unknown }
        }
    }
    return .impossible
}

// MARK: - 프리셀

private enum FreeCellMove: Hashable {
    case columnToFoundation(column: Int, slot: Int)
    case cellToFoundation(cell: Int, slot: Int)
    case columnToColumn(src: Int, index: Int, dst: Int)
    case cellToColumn(cell: Int, dst: Int)
    case columnToCell(column: Int, cell: Int)
}

private struct FreeCellSearchState: Hashable {
    var lengths: [UInt8]
    var cards: [UInt8]
    var cells: [UInt8]
    var tops: [UInt8]
    var suits: [Int8]

    @inline(__always) func start(_ column: Int) -> Int {
        var offset = 0
        for i in 0..<column { offset += Int(lengths[i]) }
        return offset
    }

    @inline(__always) func end(_ column: Int) -> Int { start(column) + Int(lengths[column]) }

    func isWin() -> Bool { tops.reduce(0) { $0 + Int($1) } >= 52 }
}

/// 프리셀은 열과 프리셀이 서로 자리를 바꿔도 같은 판이다.
/// 탐색용 키에서는 열·프리셀을 정렬해 같은 판을 한 번만 방문한다.
private struct FreeCellKey: Hashable {
    let columns: [[UInt8]]
    let cells: [UInt8]
    let foundations: [UInt16]
}

private func freeCellKey(_ state: FreeCellSearchState) -> FreeCellKey {
    var columns: [[UInt8]] = []
    columns.reserveCapacity(8)
    for column in 0..<8 {
        columns.append(Array(state.cards[state.start(column)..<state.end(column)]))
    }
    columns.sort { $0.lexicographicallyPrecedes($1) }

    var foundations: [UInt16] = []
    foundations.reserveCapacity(4)
    for i in 0..<4 {
        let suitBits = UInt16(Int(state.suits[i]) + 1)
        foundations.append(UInt16(state.tops[i]) | (suitBits << 8))
    }
    foundations.sort()
    return FreeCellKey(columns: columns, cells: state.cells.sorted(), foundations: foundations)
}

private func freeCellSlot(for card: UInt8, _ state: FreeCellSearchState) -> Int? {
    let cardSuit = Int8(suit(card))
    let cardRank = UInt8(rank(card))
    for i in 0..<state.tops.count where state.suits[i] == cardSuit {
        return state.tops[i] + 1 == cardRank ? i : nil
    }
    if cardRank == 1, let empty = state.suits.firstIndex(of: -1) { return empty }
    return nil
}

/// 안전하게 파운데이션에 올릴 수 있는 카드 하나를 고른다.
///
/// 반대 색 파운데이션이 `rank - 1` 이상이면, 이 카드가 받아 줄 반대 색의
/// 아래 숫자는 이미 정리되어 있다. 따라서 지금 올려도 나중에 다시 꺼낼 일이 없다.
private func freeCellSafeFoundationMove(_ state: FreeCellSearchState) -> FreeCellMove? {
    // 반대 색의 두 무늬 중 "가장 낮은" 파운데이션을 기준으로 한다.
    // 한 무늬만 높다고 안전한 것이 아니다(다른 무늬의 같은 숫자가 아직 바닥에 있을 수 있다).
    var redTop = 13
    var blackTop = 13
    var redCount = 0
    var blackCount = 0
    for i in 0..<4 {
        let suitIndex = Int(state.suits[i])
        guard suitIndex >= 0 else { continue }
        if suitIndex == 1 || suitIndex == 2 {
            redTop = min(redTop, Int(state.tops[i]))
            redCount += 1
        } else {
            blackTop = min(blackTop, Int(state.tops[i]))
            blackCount += 1
        }
    }
    // 두 무늬 중 하나라도 아직 파운데이션에 자리를 잡지 못했다면 그 색은 0으로 본다.
    if redCount < 2 { redTop = 0 }
    if blackCount < 2 { blackTop = 0 }

    var bestRank = Int.max
    var bestMove: FreeCellMove?
    func consider(_ card: UInt8, _ move: FreeCellMove) {
        guard let _ = freeCellSlot(for: card, state) else { return }
        let cardRank = rank(card)
        let opposite = isRed(card) ? blackTop : redTop
        guard cardRank <= opposite + 1 else { return }
        if cardRank < bestRank {
            bestRank = cardRank
            bestMove = move
        }
    }

    for column in 0..<8 {
        let e = state.end(column)
        guard let card = state.cards[safe: e - 1],
              let slot = freeCellSlot(for: card, state) else { continue }
        consider(card, .columnToFoundation(column: column, slot: slot))
    }
    for cell in 0..<4 where state.cells[cell] != 0 {
        let card = state.cells[cell]
        guard let slot = freeCellSlot(for: card, state) else { continue }
        consider(card, .cellToFoundation(cell: cell, slot: slot))
    }
    return bestMove
}

private func freeCellNormalize(_ state: FreeCellSearchState)
    -> (FreeCellSearchState, [FreeCellMove]) {
    var next = state
    var moves: [FreeCellMove] = []
    while let move = freeCellSafeFoundationMove(next) {
        next = freeCellApply(next, move)
        moves.append(move)
    }
    return (next, moves)
}

private func freeCellHeuristic(_ state: FreeCellSearchState) -> Int {
    var value = 0
    for top in state.tops { value += Int(top) * 40 }

    var emptyColumns = 0
    var topSequenceCards = 0
    var goodPairs = 0
    var badPairs = 0
    for column in 0..<8 {
        let s = state.start(column), e = state.end(column)
        if s == e { emptyColumns += 1; continue }
        var seq = 1
        if e - s >= 2 {
            for i in (s + 1)..<e {
                let lower = state.cards[i - 1], upper = state.cards[i]
                if isUp(lower), isUp(upper), rank(lower) == rank(upper) + 1,
                   !sameColor(lower, upper) {
                    goodPairs += 1
                    if i == e - 1 { seq += 1 }
                } else {
                    badPairs += 1
                }
            }
            // 위에서 이어지는 묶음 길이
            var i = e - 2
            while i >= s, isUp(state.cards[i]), isUp(state.cards[i + 1]),
                  rank(state.cards[i]) == rank(state.cards[i + 1]) + 1,
                  !sameColor(state.cards[i], state.cards[i + 1]) {
                seq += 1
                i -= 1
            }
        }
        topSequenceCards += seq
    }

    value += topSequenceCards * 22
    value += emptyColumns * 55
    value += state.cells.filter { $0 == 0 }.count * 28
    value -= state.cells.filter { $0 != 0 }.count * 8
    value += goodPairs * 3
    value -= badPairs * 4
    for column in 0..<8 {
        if let card = state.cards[safe: state.end(column) - 1], freeCellSlot(for: card, state) != nil {
            value += 18
        }
    }
    for card in state.cells where card != 0 {
        if freeCellSlot(for: card, state) != nil { value += 18 }
    }
    return value
}

private func freeCellMoves(_ state: FreeCellSearchState) -> [FreeCellMove] {
    var result: [FreeCellMove] = []
    let emptyColumns = (0..<8).filter { state.lengths[$0] == 0 }
    let firstEmptyColumn = emptyColumns.first
    let freeCells = state.cells.filter { $0 == 0 }.count
    let firstEmptyCell = state.cells.firstIndex(of: 0)

    for column in 0..<8 {
        let s = state.start(column), e = state.end(column)
        guard s < e, let top = state.cards[safe: e - 1] else { continue }
        if let slot = freeCellSlot(for: top, state) {
            result.append(.columnToFoundation(column: column, slot: slot))
        }
        if let cell = firstEmptyCell {
            result.append(.columnToCell(column: column, cell: cell))
        }

        var starts = [e - 1]
        var i = e - 2
        while i >= s,
              isUp(state.cards[i]), isUp(state.cards[i + 1]),
              rank(state.cards[i]) == rank(state.cards[i + 1]) + 1,
              !sameColor(state.cards[i], state.cards[i + 1]) {
            starts.append(i)
            i -= 1
        }

        for start in starts {
            let runLength = e - start
            let first = state.cards[start]
            for dst in 0..<8 where dst != column {
                let ds = state.start(dst), de = state.end(dst)
                if ds == de {
                    guard start > s else { continue }      // 열 전체를 빈 열로: 의미 없음
                    guard dst == firstEmptyColumn else { continue }
                    let capacity = (freeCells + 1) << max(0, emptyColumns.count - 1)
                    if runLength <= capacity {
                        result.append(.columnToColumn(src: column, index: start - s, dst: dst))
                    }
                } else {
                    let destTop = state.cards[de - 1]
                    guard isUp(destTop),
                          rank(destTop) == rank(first) + 1,
                          !sameColor(destTop, first) else { continue }
                    let capacity = (freeCells + 1) << emptyColumns.count
                    if runLength <= capacity {
                        result.append(.columnToColumn(src: column, index: start - s, dst: dst))
                    }
                }
            }
        }
    }

    for cell in 0..<4 {
        let card = state.cells[cell]
        guard card != 0 else { continue }
        if let slot = freeCellSlot(for: card, state) {
            result.append(.cellToFoundation(cell: cell, slot: slot))
        }
        for dst in 0..<8 {
            let ds = state.start(dst), de = state.end(dst)
            if ds == de {
                guard dst == firstEmptyColumn else { continue }
                result.append(.cellToColumn(cell: cell, dst: dst))
            } else {
                let destTop = state.cards[de - 1]
                guard isUp(destTop), rank(destTop) == rank(card) + 1,
                      !sameColor(destTop, card) else { continue }
                result.append(.cellToColumn(cell: cell, dst: dst))
            }
        }
    }

    // 프리셀에서는 파운데이션 카드를 다시 꺼내는 수를 쓰지 않는다.
    // (표준 해법에서 필요하지 않고, 탐색 가지만 크게 늘린다.)
    return result
}

private func freeCellApply(_ state: FreeCellSearchState,
                           _ move: FreeCellMove) -> FreeCellSearchState {
    var next = state
    switch move {
    case .columnToFoundation(let column, let slot):
        let s = next.start(column)
        let card = next.cards.remove(at: s + Int(next.lengths[column]) - 1)
        next.lengths[column] -= 1
        next.tops[slot] = UInt8(rank(card))
        next.suits[slot] = Int8(suit(card))
    case .cellToFoundation(let cell, let slot):
        let card = next.cells[cell]
        next.cells[cell] = 0
        next.tops[slot] = UInt8(rank(card))
        next.suits[slot] = Int8(suit(card))
    case .columnToColumn(let src, let index, let dst):
        let ss = next.start(src), se = next.end(src)
        let run = Array(next.cards[(ss + index)..<se])
        next.cards.removeSubrange((ss + index)..<se)
        next.lengths[src] = UInt8(index)
        let de = next.start(dst) + Int(next.lengths[dst])
        next.cards.insert(contentsOf: run, at: de)
        next.lengths[dst] += UInt8(run.count)
    case .cellToColumn(let cell, let dst):
        let card = next.cells[cell]
        next.cells[cell] = 0
        let de = next.start(dst) + Int(next.lengths[dst])
        next.cards.insert(card, at: de)
        next.lengths[dst] += 1
    case .columnToCell(let column, let cell):
        let s = next.start(column)
        let card = next.cards.remove(at: s + Int(next.lengths[column]) - 1)
        next.lengths[column] -= 1
        next.cells[cell] = card
    }
    return next
}

private func freeCellHint(_ state: FreeCellSearchState, _ move: FreeCellMove) -> Hint {
    switch move {
    case .columnToFoundation(let column, let slot):
        return .move(src: Ref(.tableau, column),
                     index: Int(state.lengths[column]) - 1,
                     dst: Ref(.foundation, slot))
    case .cellToFoundation(let cell, let slot):
        return .move(src: Ref(.freecell, cell), index: 0, dst: Ref(.foundation, slot))
    case .columnToColumn(let src, let index, let dst):
        return .move(src: Ref(.tableau, src), index: index, dst: Ref(.tableau, dst))
    case .cellToColumn(let cell, let dst):
        return .move(src: Ref(.freecell, cell), index: 0, dst: Ref(.tableau, dst))
    case .columnToCell(let column, let cell):
        return .move(src: Ref(.tableau, column),
                     index: Int(state.lengths[column]) - 1,
                     dst: Ref(.freecell, cell))
    }
}

private func solveFreeCell(_ snapshot: GameSnapshot,
                           timeLimit: TimeInterval,
                           nodeLimit: Int) -> HintSearchResult {
    let columns = tableColumns(snapshot.tableau, count: 8)
    var cells = [UInt8](repeating: 0, count: 4)
    for i in 0..<min(4, snapshot.freecells.count) {
        if let card = snapshot.freecells[i].last { cells[i] = pack(card) }
    }
    let foundations = foundationPiles(snapshot.foundations, count: 4)
    let state = FreeCellSearchState(lengths: columns.lengths, cards: columns.cards,
                                    cells: cells, tops: foundations.tops, suits: foundations.suits)

    // 프리셀은 해답이 깊고(보통 80~150수) 같은 모양이 자주 반복된다.
    // 안전한 파운데이션 정리는 탐색 전에 자동으로 해 두어 상태 수를 줄인다.
    return bestFirst(start: state,
                     key: freeCellKey,
                     normalize: freeCellNormalize,
                     isWin: { $0.isWin() },
                     heuristic: freeCellHeuristic,
                     moves: freeCellMoves,
                     apply: freeCellApply,
                     hint: freeCellHint,
                     timeLimit: timeLimit,
                     nodeLimit: nodeLimit)
}

// MARK: - 클론다이크

private enum KlondikeMove: Hashable {
    case draw
    case recycle
    case tableauToFoundation(column: Int, slot: Int)
    case wasteToFoundation(slot: Int)
    case tableauToTableau(src: Int, index: Int, dst: Int)
    case wasteToTableau(dst: Int)
    case foundationToTableau(slot: Int, dst: Int)
}

private struct KlondikeSearchState: Hashable {
    var lengths: [UInt8]
    var cards: [UInt8]
    var stock: [UInt8]
    var waste: [UInt8]
    var tops: [UInt8]
    var suits: [Int8]

    @inline(__always) func start(_ column: Int) -> Int {
        var offset = 0
        for i in 0..<column { offset += Int(lengths[i]) }
        return offset
    }

    @inline(__always) func end(_ column: Int) -> Int { start(column) + Int(lengths[column]) }

    func isWin() -> Bool { tops.reduce(0) { $0 + Int($1) } >= 52 }

    func canPlace(_ card: UInt8, in column: Int) -> Bool {
        let s = start(column), e = end(column)
        guard s < e else { return rank(card) == 13 }
        let top = cards[e - 1]
        guard isUp(top) else { return false }
        return rank(top) == rank(card) + 1 && !sameColor(top, card)
    }
}

/// 클론다이크도 태블로 열끼리는 자리를 바꿔도 같은 판이다.
private struct KlondikeKey: Hashable {
    let columns: [[UInt8]]
    let stock: [UInt8]
    let waste: [UInt8]
    let foundations: [UInt16]
}

private func klondikeKey(_ state: KlondikeSearchState) -> KlondikeKey {
    var columns: [[UInt8]] = []
    columns.reserveCapacity(7)
    for column in 0..<7 {
        columns.append(Array(state.cards[state.start(column)..<state.end(column)]))
    }
    columns.sort { $0.lexicographicallyPrecedes($1) }

    var foundations: [UInt16] = []
    foundations.reserveCapacity(4)
    for i in 0..<4 {
        let suitBits = UInt16(Int(state.suits[i]) + 1)
        foundations.append(UInt16(state.tops[i]) | (suitBits << 8))
    }
    foundations.sort()
    return KlondikeKey(columns: columns, stock: state.stock, waste: state.waste,
                       foundations: foundations)
}

private func klondikeSlot(for card: UInt8, _ state: KlondikeSearchState) -> Int? {
    let cardSuit = Int8(suit(card))
    let cardRank = UInt8(rank(card))
    for i in 0..<state.tops.count where state.suits[i] == cardSuit {
        return state.tops[i] + 1 == cardRank ? i : nil
    }
    if cardRank == 1, let empty = state.suits.firstIndex(of: -1) { return empty }
    return nil
}

private func klondikeHeuristic(_ state: KlondikeSearchState) -> Int {
    var value = 0
    for top in state.tops { value += Int(top) * 280 }
    var hidden = 0
    var emptyColumns = 0
    var runs = 0
    for column in 0..<7 {
        let s = state.start(column), e = state.end(column)
        if s == e { emptyColumns += 1; continue }
        for i in s..<e where !isUp(state.cards[i]) { hidden += 1 }
        if e - s >= 2 {
            for i in (s + 1)..<e where isUp(state.cards[i - 1]) && isUp(state.cards[i])
                && rank(state.cards[i - 1]) == rank(state.cards[i]) + 1
                && !sameColor(state.cards[i - 1], state.cards[i]) {
                runs += 1
            }
        }
    }
    value -= hidden * 24
    value += emptyColumns * 40
    value += runs * 7
    if let card = state.waste.last, klondikeSlot(for: card, state) != nil { value += 45 }
    for column in 0..<7 {
        if let card = state.cards[safe: state.end(column) - 1],
           klondikeSlot(for: card, state) != nil { value += 45 }
    }
    return value
}

private func klondikeMoves(_ state: KlondikeSearchState) -> [KlondikeMove] {
    var result: [KlondikeMove] = []
    if !state.stock.isEmpty {
        result.append(.draw)
    } else if !state.waste.isEmpty {
        result.append(.recycle)
    }

    let emptyColumns = (0..<7).filter { state.lengths[$0] == 0 }
    let firstEmptyColumn = emptyColumns.first

    if let card = state.waste.last, let slot = klondikeSlot(for: card, state) {
        result.append(.wasteToFoundation(slot: slot))
    }
    for column in 0..<7 {
        let s = state.start(column), e = state.end(column)
        guard s < e, let card = state.cards[safe: e - 1] else { continue }
        if let slot = klondikeSlot(for: card, state) {
            result.append(.tableauToFoundation(column: column, slot: slot))
        }
    }

    if let card = state.waste.last {
        for dst in 0..<7 where state.canPlace(card, in: dst) {
            if state.lengths[dst] == 0 && dst != firstEmptyColumn { continue }
            result.append(.wasteToTableau(dst: dst))
        }
    }

    for column in 0..<7 {
        let s = state.start(column), e = state.end(column)
        guard s < e else { continue }
        var starts = [e - 1]
        var i = e - 2
        while i >= s,
              isUp(state.cards[i]), isUp(state.cards[i + 1]),
              rank(state.cards[i]) == rank(state.cards[i + 1]) + 1,
              !sameColor(state.cards[i], state.cards[i + 1]) {
            starts.append(i)
            i -= 1
        }
        for start in starts {
            guard isUp(state.cards[start]) else { continue }
            let first = state.cards[start]
            for dst in 0..<7 where dst != column {
                let ds = state.start(dst), de = state.end(dst)
                if ds == de {
                    guard start > s else { continue }     // 열 전체를 빈 열로: 의미 없음
                    guard rank(first) == 13 else { continue }   // 빈 열에는 K만
                    guard dst == firstEmptyColumn else { continue }
                } else {
                    let top = state.cards[de - 1]
                    guard isUp(top), rank(top) == rank(first) + 1,
                          !sameColor(top, first) else { continue }
                }
                result.append(.tableauToTableau(src: column, index: start - s, dst: dst))
            }
        }
    }

    for slot in 0..<4 where state.tops[slot] > 0 {
        let card = UInt8(state.tops[slot]) | UInt8(Int(state.suits[slot]) << 4)
        for dst in 0..<7 where state.canPlace(card, in: dst) {
            if state.lengths[dst] == 0 && dst != firstEmptyColumn { continue }
            result.append(.foundationToTableau(slot: slot, dst: dst))
        }
    }
    return result
}

private func klondikeApply(_ state: KlondikeSearchState,
                           _ move: KlondikeMove,
                           drawCount: Int) -> KlondikeSearchState {
    var next = state
    switch move {
    case .draw:
        let count = min(max(1, drawCount), next.stock.count)
        for _ in 0..<count {
            let card = next.stock.removeLast()
            next.waste.append(up(card))
        }
    case .recycle:
        next.stock.append(contentsOf: next.waste.reversed().map { down($0) })
        next.waste.removeAll()
    case .tableauToFoundation(let column, let slot):
        let s = next.start(column)
        let card = next.cards.remove(at: s + Int(next.lengths[column]) - 1)
        next.lengths[column] -= 1
        next.tops[slot] = UInt8(rank(card))
        next.suits[slot] = Int8(suit(card))
        if next.lengths[column] > 0 {
            let top = next.end(column) - 1
            if !isUp(next.cards[top]) { next.cards[top] = up(next.cards[top]) }
        }
    case .wasteToFoundation(let slot):
        let card = next.waste.removeLast()
        next.tops[slot] = UInt8(rank(card))
        next.suits[slot] = Int8(suit(card))
    case .tableauToTableau(let src, let index, let dst):
        let ss = next.start(src), se = next.end(src)
        let run = Array(next.cards[(ss + index)..<se])
        next.cards.removeSubrange((ss + index)..<se)
        next.lengths[src] = UInt8(index)
        let de = next.start(dst) + Int(next.lengths[dst])
        next.cards.insert(contentsOf: run, at: de)
        next.lengths[dst] += UInt8(run.count)
        if next.lengths[src] > 0 {
            let top = next.end(src) - 1
            if !isUp(next.cards[top]) { next.cards[top] = up(next.cards[top]) }
        }
    case .wasteToTableau(let dst):
        let card = next.waste.removeLast()
        let de = next.start(dst) + Int(next.lengths[dst])
        next.cards.insert(up(card), at: de)
        next.lengths[dst] += 1
    case .foundationToTableau(let slot, let dst):
        let card = UInt8(next.tops[slot]) | UInt8(Int(next.suits[slot]) << 4)
        next.tops[slot] -= 1
        if next.tops[slot] == 0 { next.suits[slot] = -1 }
        let de = next.start(dst) + Int(next.lengths[dst])
        next.cards.insert(up(card), at: de)
        next.lengths[dst] += 1
    }
    return next
}

private func klondikeHint(_ state: KlondikeSearchState, _ move: KlondikeMove) -> Hint {
    switch move {
    case .draw: return .draw
    case .recycle: return .recycle
    case .tableauToFoundation(let column, let slot):
        return .move(src: Ref(.tableau, column),
                     index: Int(state.lengths[column]) - 1,
                     dst: Ref(.foundation, slot))
    case .wasteToFoundation(let slot):
        return .move(src: Ref(.waste, 0), index: state.waste.count - 1,
                     dst: Ref(.foundation, slot))
    case .tableauToTableau(let src, let index, let dst):
        return .move(src: Ref(.tableau, src), index: index, dst: Ref(.tableau, dst))
    case .wasteToTableau(let dst):
        return .move(src: Ref(.waste, 0), index: state.waste.count - 1,
                     dst: Ref(.tableau, dst))
    case .foundationToTableau(let slot, let dst):
        return .move(src: Ref(.foundation, slot), index: Int(state.tops[slot]) - 1,
                     dst: Ref(.tableau, dst))
    }
}

private func solveKlondike(_ snapshot: GameSnapshot, drawCount: Int,
                           timeLimit: TimeInterval,
                           nodeLimit: Int) -> HintSearchResult {
    let columns = tableColumns(snapshot.tableau, count: 7)
    let foundations = foundationPiles(snapshot.foundations, count: 4)
    var stock = snapshot.stock.map { pack($0, faceUp: false) }
    var waste = snapshot.waste.map { pack($0, faceUp: true) }
    if stock.count > 24 { stock = Array(stock.suffix(24)) }
    if waste.count > 24 { waste = Array(waste.suffix(24)) }
    let state = KlondikeSearchState(lengths: columns.lengths, cards: columns.cards,
                                    stock: stock, waste: waste,
                                    tops: foundations.tops, suits: foundations.suits)
    let draw = (drawCount == 1 || drawCount == 3) ? drawCount : 3
    return bestFirst(start: state,
                     key: klondikeKey,
                     normalize: { ($0, []) },
                     isWin: { $0.isWin() },
                     heuristic: klondikeHeuristic,
                     moves: klondikeMoves,
                     apply: { klondikeApply($0, $1, drawCount: draw) },
                     hint: klondikeHint,
                     timeLimit: timeLimit,
                     nodeLimit: nodeLimit)
}

// MARK: - 스파이더

private enum SpiderMove: Hashable {
    case move(src: Int, index: Int, dst: Int)
    case deal
}

private struct SpiderSearchState: Hashable {
    var lengths: [UInt8]
    var cards: [UInt8]
    var stock: [UInt8]
    var completed: Int

    @inline(__always) func start(_ column: Int) -> Int {
        var offset = 0
        for i in 0..<column { offset += Int(lengths[i]) }
        return offset
    }

    @inline(__always) func end(_ column: Int) -> Int { start(column) + Int(lengths[column]) }

    func isWin() -> Bool { completed >= 8 }
}

private func spiderHeuristic(_ state: SpiderSearchState, suitFree: Bool) -> Int {
    var value = state.completed * 10_000
    var faceUp = 0
    var rankRuns = 0
    var suitRuns = 0
    var emptyColumns = 0
    for column in 0..<10 {
        let s = state.start(column), e = state.end(column)
        if s == e { emptyColumns += 1; continue }
        for i in s..<e where isUp(state.cards[i]) { faceUp += 1 }
        if e - s >= 2 {
            for i in (s + 1)..<e where isUp(state.cards[i - 1]) && isUp(state.cards[i])
                && rank(state.cards[i - 1]) == rank(state.cards[i]) + 1 {
                rankRuns += 1
                if suit(state.cards[i - 1]) == suit(state.cards[i]) { suitRuns += 1 }
            }
        }
    }
    value += faceUp * 2
    value += rankRuns * 6
    if !suitFree { value += suitRuns * 4 }
    value += emptyColumns * 3
    value += state.stock.count / 10
    return value
}

private func spiderMoves(_ state: SpiderSearchState, suitFree: Bool) -> [SpiderMove] {
    var result: [SpiderMove] = []
    let emptyColumns = (0..<10).filter { state.lengths[$0] == 0 }
    let firstEmptyColumn = emptyColumns.first

    for src in 0..<10 {
        let s = state.start(src), e = state.end(src)
        guard s < e else { continue }
        var starts = [e - 1]
        var i = e - 2
        while i >= s,
              isUp(state.cards[i]), isUp(state.cards[i + 1]),
              rank(state.cards[i]) == rank(state.cards[i + 1]) + 1,
              suitFree || suit(state.cards[i]) == suit(state.cards[i + 1]) {
            starts.append(i)
            i -= 1
        }
        for start in starts {
            let first = state.cards[start]
            for dst in 0..<10 where dst != src {
                let ds = state.start(dst), de = state.end(dst)
                if ds == de {
                    guard start > s else { continue }
                    guard dst == firstEmptyColumn else { continue }
                } else {
                    let top = state.cards[de - 1]
                    guard isUp(top), rank(top) == rank(first) + 1 else { continue }
                }
                result.append(.move(src: src, index: start - s, dst: dst))
            }
        }
    }
    if !state.stock.isEmpty && emptyColumns.isEmpty {
        result.append(.deal)
    }
    return result
}

@discardableResult
private func spiderCollect(_ state: inout SpiderSearchState) -> Int {
    var gained = 0
    for column in 0..<10 {
        let s = state.start(column), e = state.end(column)
        guard e - s >= 13 else { continue }
        let setStart = e - 13
        guard (setStart..<e).allSatisfy({ isUp(state.cards[$0]) }) else { continue }
        let setSuit = suit(state.cards[setStart])
        guard (setStart..<e).allSatisfy({ suit(state.cards[$0]) == setSuit }) else { continue }
        var expected = 13
        var matches = true
        for i in setStart..<e {
            if rank(state.cards[i]) != expected { matches = false; break }
            expected -= 1
        }
        guard matches else { continue }
        state.cards.removeSubrange(setStart..<e)
        state.lengths[column] -= 13
        if state.lengths[column] > 0 {
            let top = state.end(column) - 1
            if !isUp(state.cards[top]) { state.cards[top] = up(state.cards[top]) }
        }
        state.completed += 1
        gained += 1
    }
    return gained
}

private func spiderApply(_ state: SpiderSearchState, _ move: SpiderMove) -> SpiderSearchState {
    var next = state
    switch move {
    case .move(let src, let index, let dst):
        let ss = next.start(src), se = next.end(src)
        let run = Array(next.cards[(ss + index)..<se])
        next.cards.removeSubrange((ss + index)..<se)
        next.lengths[src] = UInt8(index)
        let de = next.start(dst) + Int(next.lengths[dst])
        next.cards.insert(contentsOf: run.map { up($0) }, at: de)
        next.lengths[dst] += UInt8(run.count)
        if next.lengths[src] > 0 {
            let top = next.end(src) - 1
            if !isUp(next.cards[top]) { next.cards[top] = up(next.cards[top]) }
        }
        spiderCollect(&next)
    case .deal:
        let count = min(10, next.stock.count)
        for column in 0..<count {
            let card = up(next.stock.removeLast())
            let de = next.start(column) + Int(next.lengths[column])
            next.cards.insert(card, at: de)
            next.lengths[column] += 1
        }
        spiderCollect(&next)
    }
    return next
}

private func spiderHint(_ state: SpiderSearchState, _ move: SpiderMove) -> Hint {
    switch move {
    case .deal: return .draw
    case .move(let src, let index, let dst):
        return .move(src: Ref(.tableau, src), index: index, dst: Ref(.tableau, dst))
    }
}

private func solveSpider(_ snapshot: GameSnapshot, suits: Int, suitFree: Bool,
                         timeLimit: TimeInterval,
                         nodeLimit: Int) -> HintSearchResult {
    let columns = tableColumns(snapshot.tableau, count: 10)
    var stock = snapshot.stock.map { pack($0, faceUp: false) }
    if stock.count > 50 { stock = Array(stock.suffix(50)) }
    let state = SpiderSearchState(lengths: columns.lengths, cards: columns.cards,
                                  stock: stock, completed: snapshot.foundations.count)
    return bestFirst(start: state,
                     key: { $0 },
                     normalize: { ($0, []) },
                     isWin: { $0.isWin() },
                     heuristic: { spiderHeuristic($0, suitFree: suitFree) },
                     moves: { spiderMoves($0, suitFree: suitFree) },
                     apply: spiderApply,
                     hint: spiderHint,
                     timeLimit: timeLimit,
                     nodeLimit: nodeLimit)
}

// MARK: - 작은 도우미

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
