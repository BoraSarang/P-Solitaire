// SpiderWinnable.swift — 풀리는 판 보장 배분.
//
// 1무늬 판을 솔버로 풀어 해답을 얻은 뒤, 해답에서 같은 묶음으로 움직인 카드들이
// 같은 무늬를 갖도록 무늬를 다시 배정한다. 이렇게 하면 2·4무늬 판도 같은 해답
// 순서로 반드시 풀린다. (1무늬는 모든 카드가 같은 무늬라 해답을 찾기 쉽다.)
//
// 새 판을 만들 때만 쓰이며, 저장 파일·규칙에는 관여하지 않는다.

import Foundation

// MARK: - 공개 결과

/// 풀리는 판의 해답 한 수(앱에서는 검증·힌트에 쓸 수 있다).
public enum SpiderSolutionMove: Sendable, Equatable, Codable {
    case move(src: Int, index: Int, dst: Int)
    case deal
}

/// 풀리는 판 한 판 — 배분 결과와 해답을 함께 담는다.
public struct SpiderWinnableDeal: Sendable {
    public let sourceSeed: Int          // 1무늬 해답을 찾은 씨앗(판 번호)
    public let suits: Int               // 1·2·4
    public let tableau: [[PackedCard]]
    public let stock: [PackedCard]
    public let solution: [SpiderSolutionMove]

    public init(sourceSeed: Int, suits: Int, tableau: [[PackedCard]],
                stock: [PackedCard], solution: [SpiderSolutionMove]) {
        self.sourceSeed = sourceSeed
        self.suits = suits
        self.tableau = tableau
        self.stock = stock
        self.solution = solution
    }
}

// MARK: - 생성기

public enum SpiderWinnable {
    /// 씨앗 하나로 풀리는 판을 만든다. 실패하면 nil.
    public static func makeDeal(sourceSeed: Int, suits: Int,
                                timeLimit: TimeInterval = 1.5,
                                nodeLimit: Int = 600_000) -> SpiderWinnableDeal? {
        let suitCount = (suits == 2 || suits == 4) ? suits : 1
        let one = Spider(seed: sourceSeed, suits: 1, suitFree: false)
        var solver = SolverState(one)
        guard let rawSolution = Solver.solve(&solver, nodeLimit: nodeLimit,
                                             timeLimit: timeLimit) else { return nil }
        let solution = rawSolution.map(\.publicMove)

        // 1무늬 판을 실제 규칙으로 다시 두며 카드 ID·완성 세트를 기록한다.
        let initial = one.tableau.map { pile in
            pile.map { (rank: $0.rank, id: $0.id, faceup: $0.faceup) }
        }
        let initialStock = one.stock.map { (rank: $0.rank, id: $0.id) }

        var runGroups: [[Int]] = []
        for move in solution {
            switch move {
            case .deal:
                guard one.drawFromStock().ok else { return nil }
            case .move(let src, let index, let dst):
                guard let run = one.pick(Ref(.tableau, src), index: index) else { return nil }
                runGroups.append(run.map(\.id))
                guard one.move(Ref(.tableau, src), index: index, Ref(.tableau, dst)).ok else {
                    return nil
                }
            }
        }
        guard one.isWon() else { return nil }

        var cardSet: [Int: Int] = [:]
        for (setIndex, pile) in one.foundations.enumerated() {
            for card in pile { cardSet[card.id] = setIndex }
        }
        guard cardSet.count == 104 else { return nil }

        // 해답에서 함께 움직인 세트들을 묶는다(같은 무늬가 되어야 한다).
        var parent = Array(0..<8)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }
        for run in runGroups {
            let sets = Set(run.compactMap { cardSet[$0] })
            guard let first = sets.first else { continue }
            for s in sets { union(first, s) }
        }
        var components: [Int: [Int]] = [:]
        for s in 0..<8 { components[find(s), default: []].append(s) }
        let comps = components.values.sorted { $0[0] < $1[0] }

        guard let setSuit = assignSuits(components: comps, suits: suitCount) else {
            return nil
        }

        // 무늬를 다시 칠한 배분.
        let tableau: [[PackedCard]] = initial.map { pile in
            pile.compactMap { card in
                guard let setIndex = cardSet[card.id], let suit = setSuit[setIndex] else {
                    return nil
                }
                return PackedCard(rank: card.rank, suit: suit, faceup: card.faceup)
            }
        }
        let stock: [PackedCard] = initialStock.compactMap { card in
            guard let setIndex = cardSet[card.id], let suit = setSuit[setIndex] else {
                return nil
            }
            return PackedCard(rank: card.rank, suit: suit, faceup: false)
        }
        guard stock.count == 50, tableau.reduce(0, { $0 + $1.count }) == 54 else {
            return nil
        }
        let deal = SpiderWinnableDeal(sourceSeed: sourceSeed, suits: suitCount,
                                      tableau: tableau, stock: stock, solution: solution)

        // 실제 2·4무늬 규칙으로 해답을 다시 두어 확인한다.
        let check = Spider(seed: sourceSeed, suits: suitCount, suitFree: false)
        check.applyDeal(deal)
        for move in solution {
            switch move {
            case .deal:
                guard check.drawFromStock().ok else { return nil }
            case .move(let src, let index, let dst):
                guard check.move(Ref(.tableau, src), index: index,
                                 Ref(.tableau, dst)).ok else { return nil }
            }
        }
        guard check.isWon() else { return nil }
        return deal
    }

    /// 씨앗을 조금씩 옮겨 가며 풀리는 판을 찾는다.
    public static func makeDeal(suits: Int, startingSeed: Int,
                                attempts: Int = 4,
                                timeLimit: TimeInterval = 1.5,
                                nodeLimit: Int = 600_000) -> SpiderWinnableDeal? {
        for i in 0..<max(1, attempts) {
            if let deal = makeDeal(sourceSeed: startingSeed &+ i, suits: suits,
                                   timeLimit: timeLimit, nodeLimit: nodeLimit) {
                return deal
            }
        }
        return nil
    }

    // MARK: 무늬 배정

    /// 8개 완성 세트를 1·2·4개 무늬에 나눈다.
    /// - 4무늬: 세트 2개씩. 해답에서 묶인 세트(2개)는 같은 무늬.
    /// - 2무늬: 세트 4개씩. 묶인 덩어리를 합쳐 4+4로 나눈다.
    static func assignSuits(components: [[Int]], suits: Int) -> [Int: Suit]? {
        if suits == 1 {
            return Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, Suit.spades) })
        }
        if suits == 2 {
            var groups: [[Int]] = []
            func pick(_ index: Int, _ a: [Int], _ b: [Int]) -> [[Int]]? {
                if index == components.count {
                    return (a.count == 4 && b.count == 4) ? [a, b] : nil
                }
                let c = components[index]
                if a.count + c.count <= 4, let r = pick(index + 1, a + c, b) { return r }
                if b.count + c.count <= 4, let r = pick(index + 1, a, b + c) { return r }
                return nil
            }
            guard let found = pick(0, [], []) else { return nil }
            groups = found
            var out: [Int: Suit] = [:]
            for (suitIndex, group) in groups.enumerated() {
                let suit: Suit = suitIndex == 0 ? .spades : .hearts
                for setIndex in group { out[setIndex] = suit }
            }
            return out
        }

        // 4무늬 — 2개씩. 크기 2 덩어리는 그대로 짝이 된다.
        // 크기 3 이상 덩어리는 한 무늬에 3세트가 되어 4무늬 규칙으로는 풀 수 없다.
        guard components.allSatisfy({ $0.count <= 2 }) else { return nil }
        var pairs: [(Int, Int)] = []
        var used = Set<Int>()
        for c in components where c.count == 2 {
            guard !used.contains(c[0]), !used.contains(c[1]) else { return nil }
            used.insert(c[0]); used.insert(c[1])
            pairs.append((c[0], c[1]))
        }
        let rest = (0..<8).filter { !used.contains($0) }
        guard rest.count % 2 == 0 else { return nil }
        var i = 0
        while i + 1 < rest.count {
            pairs.append((rest[i], rest[i + 1]))
            i += 2
        }
        guard pairs.count == 4 else { return nil }
        var out: [Int: Suit] = [:]
        for (suitIndex, pair) in pairs.enumerated() {
            let suit = Suit.allCases[suitIndex]
            out[pair.0] = suit
            out[pair.1] = suit
        }
        return out
    }
}

// MARK: - 1무늬 솔버(내부)

private struct SolverState {
    /// 열별 카드 수(합 104).
    var lengths: [UInt8]
    /// 열을 차례로 이어 붙인 카드(rank 1~13 | 앞면 0x80).
    var cards: [UInt8]
    /// 스톡(맨 끝이 다음에 돌릴 카드). 모두 뒷면.
    var stock: [UInt8]
    var sets: Int

    init(_ game: Spider) {
        lengths = game.tableau.map { UInt8($0.count) }
        cards = []
        cards.reserveCapacity(104)
        for pile in game.tableau {
            for card in pile {
                cards.append(UInt8(card.rank) | (card.faceup ? 0x80 : 0))
            }
        }
        stock = game.stock.map { UInt8($0.rank) }
        sets = game.foundations.count
    }

    var key: SolverKey {
        SolverKey(lengths: lengths, cards: cards, stock: stock, sets: sets)
    }

    @inline(__always) func offset(of column: Int) -> Int {
        var o = 0
        for i in 0..<column { o += Int(lengths[i]) }
        return o
    }

    func heuristic() -> Int {
        var value = sets * 1000
        var up = 0
        var adjacent = 0
        var empty = 0
        var off = 0
        for i in 0..<10 {
            let len = Int(lengths[i])
            if len == 0 { empty += 1 }
            for k in off..<(off + len) {
                let b = cards[k]
                if Self.isUp(b) { up += 1 }
                if k + 1 < off + len {
                    let n = cards[k + 1]
                    if Self.isUp(b), Self.isUp(n), Self.rank(b) == Self.rank(n) + 1 {
                        adjacent += 1
                    }
                }
            }
            off += len
        }
        value += up * 2 + adjacent * 6 + empty * 3 + stock.count / 10
        return value
    }

    @inline(__always) static func rank(_ b: UInt8) -> UInt8 { b & 0x0F }
    @inline(__always) static func isUp(_ b: UInt8) -> Bool { b & 0x80 != 0 }
    @inline(__always) static func makeUp(_ b: UInt8) -> UInt8 { b | 0x80 }

    /// 합법적인 수를 만든다.
    func legalMoves() -> [SolverMove] {
        var result: [SolverMove] = []
        // 열 시작 위치
        var offsets = [Int](repeating: 0, count: 10)
        var off = 0
        var emptyCount = 0
        for i in 0..<10 {
            offsets[i] = off
            off += Int(lengths[i])
            if lengths[i] == 0 { emptyCount += 1 }
        }
        for s in 0..<10 {
            let len = Int(lengths[s])
            guard len > 0 else { continue }
            let base = offsets[s]
            var starts = [len - 1]
            var i = len - 2
            while i >= 0 {
                let lower = cards[base + i]
                let upper = cards[base + i + 1]
                if !Self.isUp(lower) || !Self.isUp(upper) { break }
                if Self.rank(lower) != Self.rank(upper) + 1 { break }
                starts.append(i)
                i -= 1
            }
            for start in starts {
                let runRank = Self.rank(cards[base + start])
                for d in 0..<10 where d != s {
                    let dlen = Int(lengths[d])
                    if dlen == 0 {
                        // 빈 열로 열 전체를 통째로 옮기는 것은 의미가 없다.
                        if start == 0 { continue }
                        result.append(.move(src: s, index: start, dst: d))
                    } else {
                        let top = cards[offsets[d] + dlen - 1]
                        guard Self.isUp(top) else { continue }
                        if Self.rank(top) == runRank + 1 {
                            result.append(.move(src: s, index: start, dst: d))
                        }
                    }
                }
            }
        }
        if !stock.isEmpty && emptyCount == 0 {
            result.append(.deal)
        }
        return result
    }

    mutating func apply(_ move: SolverMove) {
        switch move {
        case .deal:
            applyDeal()
        case .move(let src, let index, let dst):
            applyMove(src: src, index: index, dst: dst)
        }
    }

    private mutating func applyMove(src: Int, index: Int, dst: Int) {
        let srcOff = offset(of: src)
        let srcLen = Int(lengths[src])
        let run = Array(cards[(srcOff + index)..<(srcOff + srcLen)])
        var newLengths = lengths
        var newCards: [UInt8] = []
        newCards.reserveCapacity(cards.count)
        var off = 0
        for i in 0..<10 {
            let len = Int(lengths[i])
            let start = off
            off += len
            let colStart = newCards.count
            if i == src {
                for k in start..<(start + index) {
                    newCards.append(cards[k])
                }
                if newCards.count > colStart, !Self.isUp(newCards[newCards.count - 1]) {
                    newCards[newCards.count - 1] = Self.makeUp(newCards[newCards.count - 1])
                }
            } else {
                for k in start..<(start + len) {
                    newCards.append(cards[k])
                }
            }
            if i == dst {
                newCards.append(contentsOf: run)
            }
            newLengths[i] = UInt8(newCards.count - colStart)
        }
        lengths = newLengths
        cards = newCards
        collectSets()
    }

    private mutating func applyDeal() {
        var newCards: [UInt8] = []
        newCards.reserveCapacity(cards.count + 10)
        var newLengths = lengths
        var off = 0
        for i in 0..<10 {
            let len = Int(lengths[i])
            let start = off
            off += len
            let colStart = newCards.count
            for k in start..<(start + len) {
                newCards.append(cards[k])
            }
            let next = stock.removeLast()
            newCards.append(Self.makeUp(next))
            newLengths[i] = UInt8(newCards.count - colStart)
        }
        lengths = newLengths
        cards = newCards
        collectSets()
    }

    private mutating func collectSets() {
        var newCards: [UInt8] = []
        newCards.reserveCapacity(cards.count)
        var newLengths = lengths
        var off = 0
        for i in 0..<10 {
            let len = Int(lengths[i])
            let start = off
            off += len
            var collected = false
            if len >= 13 {
                let setStart = start + len - 13
                var ok = true
                for k in 0..<13 {
                    let b = cards[setStart + k]
                    if !Self.isUp(b) || Self.rank(b) != UInt8(13 - k) {
                        ok = false
                        break
                    }
                }
                if ok {
                    let colStart = newCards.count
                    for k in start..<setStart {
                        newCards.append(cards[k])
                    }
                    if newCards.count > colStart, !Self.isUp(newCards[newCards.count - 1]) {
                        newCards[newCards.count - 1] = Self.makeUp(newCards[newCards.count - 1])
                    }
                    newLengths[i] = UInt8(newCards.count - colStart)
                    sets += 1
                    collected = true
                }
            }
            if !collected {
                let colStart = newCards.count
                for k in start..<(start + len) {
                    newCards.append(cards[k])
                }
                newLengths[i] = UInt8(newCards.count - colStart)
            }
        }
        cards = newCards
        lengths = newLengths
    }
}

private struct SolverKey: Hashable {
    let lengths: [UInt8]
    let cards: [UInt8]
    let stock: [UInt8]
    let sets: Int
}

private enum SolverMove: Hashable {
    case move(src: Int, index: Int, dst: Int)
    case deal

    var publicMove: SpiderSolutionMove {
        switch self {
        case .deal: return .deal
        case .move(let src, let index, let dst):
            return .move(src: src, index: index, dst: dst)
        }
    }
}

private enum Solver {
    private struct Node {
        let parent: Int?
        let move: SolverMove?
        let depth: Int
        let state: SolverState
    }

    struct HeapItem {
        let order: Int      // 작을수록 먼저
        let depth: Int      // 같은 order면 얕은 쪽 먼저
        let seq: Int        // 그다음 먼저 만든 것
        let index: Int
    }

    struct Heap {
        private var items: [HeapItem] = []

        mutating func push(_ item: HeapItem) {
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

        mutating func pop() -> HeapItem? {
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

        private func less(_ a: HeapItem, _ b: HeapItem) -> Bool {
            if a.order != b.order { return a.order < b.order }
            if a.depth != b.depth { return a.depth < b.depth }
            return a.seq < b.seq
        }
    }

    static func solve(_ start: inout SolverState, nodeLimit: Int,
                      timeLimit: TimeInterval) -> [SolverMove]? {
        let deadline = Date().addingTimeInterval(timeLimit)
        var seen = Set<SolverKey>()
        seen.reserveCapacity(min(nodeLimit, 200_000))
        seen.insert(start.key)
        var nodes: [Node] = []
        nodes.reserveCapacity(min(nodeLimit, 200_000))
        nodes.append(Node(parent: nil, move: nil, depth: 0, state: start))
        var heap = Heap()
        heap.push(HeapItem(order: -(start.heuristic() * 2), depth: 0, seq: 0, index: 0))
        var seq = 1
        var tick = 0

        while let item = heap.pop() {
            let index = item.index
            let node = nodes[index]
            if node.state.sets >= 8 {
                return reconstruct(nodes: nodes, index: index)
            }
            if nodes.count >= nodeLimit { break }
            tick += 1
            if tick & 127 == 0, Date() >= deadline { break }

            for move in node.state.legalMoves() {
                var child = node.state
                child.apply(move)
                let key = child.key
                guard seen.insert(key).inserted else { continue }
                let depth = node.depth + 1
                let priority = child.heuristic() * 2 - depth
                nodes.append(Node(parent: index, move: move, depth: depth, state: child))
                heap.push(HeapItem(order: -priority, depth: depth, seq: seq, index: nodes.count - 1))
                seq += 1
            }
        }
        return nil
    }

    private static func reconstruct(nodes: [Node], index: Int) -> [SolverMove] {
        var path: [SolverMove] = []
        var cur = index
        while let parent = nodes[cur].parent {
            if let move = nodes[cur].move { path.append(move) }
            cur = parent
        }
        path.reverse()
        return path
    }
}

// MARK: - Spider 에 배분 적용

public extension Spider {
    /// 풀리는 판 배분을 그대로 적용한다(점수·이동·되돌리기 초기화).
    func applyDeal(_ deal: SpiderWinnableDeal) {
        seed = deal.sourceSeed
        updateSuits(deal.suits)
        tableau = deal.tableau.map { pile in
            pile.map { Card(rank: $0.rank, suit: $0.suit, faceup: $0.faceup) }
        }
        stock = deal.stock.map { Card(rank: $0.rank, suit: $0.suit, faceup: false) }
        foundations = []
        freecells = []
        waste = []
        score = spiderBaseScore
        moves = 0
        clearUndo()
        captureStartLayout()
        startLayout?.solution = deal.solution
    }
}
