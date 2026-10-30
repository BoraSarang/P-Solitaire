// Rules.swift — 세 게임이 함께 쓰는 뼈대(점수·이동 수·실행 취소·묶음 규칙)
// solitaire_core.py 의 BaseGame + Card 헬퍼 이식.

import Foundation

// MARK: - 실행 취소용 스냅숏

/// 게임별 스냅숏(각 게임이 자기 구조체로 구현한다).
protocol GameState {}

/// 뒤집힘 여부까지 담은 카드 한 장(스냅숏·저장 파일용).
public struct PackedCard: Codable, Sendable, Equatable {
    public let rank: Int
    public let suit: Suit
    public let faceup: Bool

    public init(rank: Int, suit: Suit, faceup: Bool) {
        self.rank = rank
        self.suit = suit
        self.faceup = faceup
    }
}

/// 진행 중인 판 전체를 파일에 저장할 때 쓰는 중립 스냅숏.
///
/// 게임별 내부 상태(스냅숏 구조체)와 달리 카드 배열·점수·이동 수·시드만 담는다.
/// 클론다이크의 넘기기 장수, 스파이더의 무늬 수·묶음 규칙은 앱이 따로 저장한다.
public struct GameSnapshot: Codable, Sendable, Equatable {
    public var version: Int
    public var seed: Int
    public var score: Int
    public var moves: Int
    public var stock: [PackedCard]
    public var waste: [PackedCard]
    public var freecells: [[PackedCard]]
    public var foundations: [[PackedCard]]
    public var tableau: [[PackedCard]]

    public init(version: Int = 1, seed: Int, score: Int, moves: Int,
                stock: [PackedCard], waste: [PackedCard],
                freecells: [[PackedCard]], foundations: [[PackedCard]],
                tableau: [[PackedCard]]) {
        self.version = version
        self.seed = seed
        self.score = score
        self.moves = moves
        self.stock = stock
        self.waste = waste
        self.freecells = freecells
        self.foundations = foundations
        self.tableau = tableau
    }
}

func packPile(_ pile: [Card]) -> [PackedCard] {
    pile.map { PackedCard(rank: $0.rank, suit: $0.suit, faceup: $0.faceup) }
}

/// 되돌릴 때는 새 Card 를 만든다(파이썬과 같은 동작 — uid 는 달라진다).
func unpackPile(_ packed: [PackedCard]) -> [Card] {
    packed.map { Card(rank: $0.rank, suit: $0.suit, faceup: $0.faceup) }
}

// MARK: - 뼈대

public class BaseGame {
    public var score = 0
    public var moves = 0
    public var seed = 0

    public var stock: [Card] = []
    public var waste: [Card] = []
    public var freecells: [[Card]] = []
    public var foundations: [[Card]] = []
    public var tableau: [[Card]] = []

    private var undoStack: [GameState] = []
    private var redoStack: [GameState] = []
    private let undoLimit = 400           // 메모리 보호용 상한

    public init() {}

    // ── 게임별 값(서브클래스가 덮어쓴다) ────────────────────────────────────
    public var kind: GameKind { .klondike }
    public var name: String { "게임" }
    public var totalCards: Int { 52 }
    public var columns: Int { 7 }
    public var foundationsCount: Int { 4 }
    public var hasStock: Bool { true }
    public var hasWaste: Bool { false }
    public var hasFreecells: Bool { false }

    /// 집을 수 없을 때 이유 문구(게임별로 다르다).
    public var groupLimitText: String { "색이 다르면 한 묶음으로 옮기지 못합니다" }

    /// 위 카드가 이어지지 않아 집을 수 없을 때 문구.
    public var buriedText: String { "위에 덮인 카드부터 옮겨야 합니다" }

    // ── 실행 취소/복귀 ─────────────────────────────────────────────────────
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    func pushUndo() {
        undoStack.append(makeSnapshot())
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        // 새 수를 두면 예전에 되돌린 가지는 더 이상 유효하지 않다.
        redoStack.removeAll()
    }

    /// 새 판을 배분할 때처럼 되돌릴 필요가 없을 때 기록을 통째로 버린다.
    func clearUndo() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    @discardableResult
    public func undo() -> Bool {
        guard let state = undoStack.popLast() else { return false }
        redoStack.append(makeSnapshot())
        if redoStack.count > undoLimit { redoStack.removeFirst() }
        applySnapshot(state)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let state = redoStack.popLast() else { return false }
        undoStack.append(makeSnapshot())
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        applySnapshot(state)
        return true
    }

    // ── 저장/복원(앱이 진행 중인 판을 파일에 남길 때) ─────────────────────
    /// 현재 판 전체를 게임에 상관없는 중립 스냅숏으로 내보낸다.
    public func exportSnapshot() -> GameSnapshot {
        GameSnapshot(seed: seed, score: score, moves: moves,
                     stock: packPile(stock), waste: packPile(waste),
                     freecells: freecells.map(packPile),
                     foundations: foundations.map(packPile),
                     tableau: tableau.map(packPile))
    }

    /// 중립 스냅숏을 현재 판에 적용한다(새 카드 객체를 만든다).
    ///
    /// 파일이 손상되어 더미 수가 맞지 않으면 빈 더미로 보충한다.
    /// 복원 뒤에는 실행 취소/복귀 기록을 비운다(이전 앱 실행의 기록은 없다).
    public func restoreSnapshot(_ snapshot: GameSnapshot) {
        seed = snapshot.seed
        score = snapshot.score
        moves = snapshot.moves
        stock = unpackPile(snapshot.stock)
        waste = unpackPile(snapshot.waste)
        freecells = snapshot.freecells.map(unpackPile)
        foundations = snapshot.foundations.map(unpackPile)
        tableau = snapshot.tableau.map(unpackPile)

        while tableau.count < columns { tableau.append([]) }
        if tableau.count > columns { tableau = Array(tableau.prefix(columns)) }
        if kind == .spider && foundations.isEmpty {
            // 스파이더는 완성 세트만 foundations 에 쌓는다(빈 8칸을 미리 만들지 않는다).
            foundations = []
        } else {
            while foundations.count < foundationsCount { foundations.append([]) }
            if foundations.count > foundationsCount {
                foundations = Array(foundations.prefix(foundationsCount))
            }
        }
        if hasFreecells {
            while freecells.count < FreeCell.freeCellCount { freecells.append([]) }
            if freecells.count > FreeCell.freeCellCount {
                freecells = Array(freecells.prefix(FreeCell.freeCellCount))
            }
        } else {
            freecells = []
        }
        clearUndo()
    }

    func makeSnapshot() -> GameState { fatalError("서브클래스가 구현해야 합니다") }
    func applySnapshot(_ state: GameState) { fatalError("서브클래스가 구현해야 합니다") }

    // ── 공통 상태 조회 ─────────────────────────────────────────────────────
    /// 파운데이션(스파이더는 완성 세트)에 정리된 카드 수.
    public func sortedCards() -> Int { foundations.reduce(0) { $0 + $1.count } }

    public func cardsRemaining() -> Int { totalCards - sortedCards() }

    public func faceDownCount() -> Int {
        tableau.reduce(0) { $0 + $1.filter { !$0.faceup }.count }
    }

    public func freeCellsFree() -> Int { freecells.filter { $0.isEmpty }.count }

    public func isWon() -> Bool { sortedCards() >= totalCards }

    /// 이 카드를 올릴 수 있는 파운데이션 번호(없으면 nil).
    public func foundationSlotFor(_ card: Card) -> Int? {
        for fi in 0..<foundations.count where canDrop([card], Ref(.foundation, fi)) {
            return fi
        }
        return nil
    }

    // ── 묶음 집기(공통) ────────────────────────────────────────────────────
    /// 태블로 index 카드부터 이어지는 묶음(규칙이 끊기면 거기까지, 최소 1장).
    ///
    /// - 기본: 내림차순 + 색 교대(클론다이크·프리셀)
    /// - `sameSuit`: 내림차순 + 같은 무늬(스파이더 기본)
    /// - `rankOnly`: 숫자만 내림차순(스파이더 "무늬 상관없이")
    public func runFrom(_ ref: Ref, index: Int, sameSuit: Bool = false,
                        rankOnly: Bool = false) -> [Card]? {
        guard ref.index >= 0, ref.index < tableau.count else { return nil }
        let pile = tableau[ref.index]
        guard index >= 0, index < pile.count, pile[index].faceup else { return nil }

        var run = [pile[index]]
        for next in pile[(index + 1)...] {
            guard let prev = run.last else { break }
            if !next.faceup || prev.rank != next.rank + 1 { break }
            if !rankOnly {
                if sameSuit {
                    if prev.suit != next.suit { break }
                } else if prev.isRed == next.isRed {
                    break
                }
            }
            run.append(next)
        }
        return run
    }

    /// 이 게임의 묶음 규칙으로 이어지는 카드(기본: 내림차순 + 색 교대).
    ///
    /// 스파이더는 "같은 무늬"(또는 쉬움 설정이면 숫자만)로 덮어쓴다.
    public func groupRun(_ ref: Ref, index: Int) -> [Card]? {
        runFrom(ref, index: index)
    }

    /// 태블로에서 집을 수 있는 묶음 — 열 맨 위 카드까지 이어져야 한다.
    ///
    /// MS 규칙: 카드 위에 덮인 카드가 한 묶음으로 이어지지 않으면 그 카드는
    /// 집을 수 없다(중간 카드만 쏙 빼내는 것은 허용하지 않는다).
    public func pickWhole(_ ref: Ref, index: Int) -> [Card]? {
        guard ref.kind == .tableau, ref.index >= 0, ref.index < tableau.count,
              let run = groupRun(ref, index: index),
              index + run.count == tableau[ref.index].count else { return nil }
        return run
    }

    /// 지금 이 카드를 집을 수 없는 이유 한 줄(집을 수 있으면 nil).
    ///
    /// UI가 카드를 눌렀는데 집히지 않을 때 상태줄에 보여 준다.
    /// - 숫자만으로는 열 맨 위까지 이어지는데 묶음 규칙(무늬·색)에서 끊기면
    ///   `groupLimitText`, 위 카드가 아예 이어지지 않으면 `buriedText`.
    public func groupLimitNote(_ ref: Ref, index: Int) -> String? {
        guard ref.kind == .tableau, ref.index >= 0, ref.index < tableau.count else { return nil }
        let pile = tableau[ref.index]
        guard index >= 0, index < pile.count, pile[index].faceup else { return nil }
        if let run = groupRun(ref, index: index), index + run.count == pile.count {
            return nil                                  // 지금 집을 수 있다
        }
        if let loose = runFrom(ref, index: index, rankOnly: true),
           index + loose.count == pile.count {
            return groupLimitText
        }
        return buriedText
    }

    // ── 서브클래스가 지원하지 않는 기능의 기본 동작 ─────────────────────────
    public func pick(_ ref: Ref, index: Int) -> [Card]? { nil }
    public func canDrop(_ cards: [Card], _ dst: Ref) -> Bool { false }
    public func move(_ src: Ref, index: Int, _ dst: Ref) -> MoveResult {
        MoveResult.fail("이 게임에서는 할 수 없는 동작입니다.")
    }
    public func deal(seed: Int? = nil) {}
    public func restart() { deal(seed: seed) }
    public func drawFromStock() -> MoveResult { MoveResult.fail("이 게임에는 스톡이 없습니다.") }
    public func flipTop(_ ref: Ref) -> Bool { false }
    public func autoMove(_ ref: Ref, index: Int) -> MoveResult? { nil }
    public func hint() -> Hint? { nil }
    public func findFoundationMove() -> (src: Ref, index: Int, dst: Ref)? { nil }
    public func canAutoComplete() -> Bool { false }

    /// 현재 판에서 이기는 해답을 찾는다(힌트용).
    ///
    /// `hint()` 는 "당장 둘 수 있는 한 수"만 고르는 빠른 휴리스틱이라
    /// 왕복 수를 반복할 수 있다. 이 메서드는 판 전체를 탐색해 이기는 줄의
    /// 첫 수를 돌려주고, 탐색을 끝까지 마쳤는데 해답이 없으면 `.impossible`,
    /// 시간·노드 한도에 걸리면 `.unknown` 을 돌려준다.
    ///
    /// 예산을 생략하면 게임별 기본값(`HintSolver.budget`)을 쓴다.
    public func searchHint(timeLimit: TimeInterval? = nil,
                           nodeLimit: Int? = nil) -> HintSearchResult {
        let drawCount = (self as? Klondike)?.drawCount ?? 3
        let spider = self as? Spider
        let suits = spider?.suits ?? 1
        let suitFree = spider?.suitFree ?? false
        // 풀리는 판으로 시작했고 해답 경로 위에 있으면 탐색 없이 바로 안내한다.
        if let planned = spider?.planHint() { return .solved([planned]) }
        let budget = HintSolver.budget(for: kind)
        return HintSolver.solve(kind: kind, snapshot: exportSnapshot(),
                                drawCount: drawCount, suits: suits, suitFree: suitFree,
                                timeLimit: timeLimit ?? budget.time,
                                nodeLimit: nodeLimit ?? budget.nodes)
    }

    /// 자동 완성 한 단계: 파운데이션에 올릴 수 있는 카드 하나를 옮긴다.
    public func autocompleteStep() -> MoveResult? {
        guard let found = findFoundationMove() else { return nil }
        return move(found.src, index: found.index, found.dst)
    }

    /// 상태바에 덧붙일 한 줄 요약.
    public func summary() -> String { "남은 카드 \(cardsRemaining())" }
}
