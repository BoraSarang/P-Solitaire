// Board.swift — 카드 자리 계산·마우스 위치 판정. solitaire.py 의 layout/hit_test/drop_target 이식.

import SwiftUI
import PSolitaireKit

/// 눌린/가리킨 자리.
///
/// `pile` 은 더미 번호(태블로 열 번호·프리셀 번호 등)이고, `index` 는 그 더미 안에서
/// 몇 번째 카드인가이다. 태블로에서는 둘이 다르므로 따로 들고 다닌다.
struct Hit {
    let kind: PileKind
    let pile: Int
    let index: Int
    let card: Card?

    var ref: Ref { Ref(kind, pile) }
}

/// 카드(uid)별 좌상단 위치와 더미별 "놓을 자리".
struct BoardLayout {
    var pos: [ObjectIdentifier: CGPoint] = [:]
    var slots: [Ref: CGPoint] = [:]
    var tabOffsets: [(CGFloat, CGFloat)] = []

    func point(_ card: Card) -> CGPoint? { pos[ObjectIdentifier(card)] }

    func slot(_ kind: PileKind, _ index: Int) -> CGPoint? { slots[Ref(kind, index)] }
}

/// 파운데이션에 보이는 카드(스파이더는 완성 세트의 K가 맨 위).
func foundationCard(_ game: BaseGame, _ fi: Int) -> Card? {
    guard fi >= 0, fi < game.foundations.count else { return nil }
    let pile = game.foundations[fi]
    guard !pile.isEmpty else { return nil }
    return game.kind == .spider ? pile[0] : pile[pile.count - 1]
}

/// 위 줄(스톡·웨이스트·프리셀·파운데이션)의 (자리, 열 번호) 목록.
/// 파운데이션은 태블로 오른쪽 끝에 맞춘다(창 밖으로 나가지 않게).
func topRefs(_ game: BaseGame) -> [(Ref, Int)] {
    var refs: [(Ref, Int)] = []
    var col = 0
    if game.hasStock {
        refs.append((Ref(.stock, 0), col))
        col += 1
    }
    if game.hasWaste {
        refs.append((Ref(.waste, 0), col))
        col += 1
    }
    for i in game.freecells.indices {
        refs.append((Ref(.freecell, i), col))
        col += 1
    }
    col = max(col, game.columns - game.foundationsCount)   // 오른쪽 정렬
    for i in 0..<game.foundationsCount {
        refs.append((Ref(.foundation, i), col + i))
    }
    return refs
}

/// 카드 위치와 더미 자리를 계산한다.
func computeLayout(_ game: BaseGame, style: GameStyle) -> BoardLayout {
    var layout = BoardLayout()
    let top = Metrics.topY

    for (ref, col) in topRefs(game) {
        layout.slots[ref] = CGPoint(x: Metrics.margin + CGFloat(col) * (Metrics.cardW + Metrics.gap),
                                    y: top)
    }

    if game.hasWaste, let base = layout.slots[Ref(.waste, 0)] {   // 웨이스트: 최근 1~3장을 펼쳐 보인다
        let visible = min(game.waste.count, game.kind == .klondike
                          ? ((game as? Klondike)?.drawCount ?? 3) == 3 ? 3 : 1
                          : 1)
        let start = game.waste.count - visible
        for (k, card) in game.waste[start...].enumerated() {
            layout.pos[ObjectIdentifier(card)] = CGPoint(x: base.x + CGFloat(k) * style.wasteFan,
                                                         y: top)
        }
    }

    for fi in 0..<game.foundationsCount {                          // 파운데이션: 맨 위 카드만
        if let card = foundationCard(game, fi), let slot = layout.slots[Ref(.foundation, fi)] {
            layout.pos[ObjectIdentifier(card)] = slot
        }
    }

    for (ci, cell) in game.freecells.enumerated() {                // 프리셀: 카드 한 장
        if let card = cell.last, let slot = layout.slots[Ref(.freecell, ci)] {
            layout.pos[ObjectIdentifier(card)] = slot
        }
    }

    // 태블로: 열이 길면 간격을 줄여 화면 안에 들어오게 한다
    for ti in 0..<game.columns {
        let pile = game.tableau[ti]
        let x = Metrics.margin + CGFloat(ti) * (Metrics.cardW + Metrics.gap)
        let down = pile.filter { !$0.faceup }.count
        let up = pile.count - down
        var dyDown = style.faceDownDY
        var dyUp = style.faceUpDY
        let need = CGFloat(down) * dyDown + CGFloat(max(0, up - 1)) * dyUp
        if need > Metrics.tableauAreaH {
            let scale = Metrics.tableauAreaH / need
            dyDown = max(3, (style.faceDownDY * scale).rounded(.down))
            dyUp = max(8, (style.faceUpDY * scale).rounded(.down))
        }
        layout.tabOffsets.append((dyDown, dyUp))
        var y = Metrics.tableauY
        var step = dyUp
        for card in pile {
            layout.pos[ObjectIdentifier(card)] = CGPoint(x: x, y: y)
            step = card.faceup ? dyUp : dyDown
            y += step
        }
        layout.slots[Ref(.tableau, ti)] = CGPoint(x: x, y: pile.isEmpty ? Metrics.tableauY : y - step)
    }
    return layout
}

/// 화면 좌표 아래에 있는 카드/더미를 찾는다(맨 위 카드 우선).
func hitTest(_ game: BaseGame, _ layout: BoardLayout, at point: CGPoint) -> Hit? {
    func inside(_ spot: CGPoint) -> Bool {
        point.x >= spot.x && point.x <= spot.x + Metrics.cardW
            && point.y >= spot.y && point.y <= spot.y + Metrics.cardH
    }

    for ti in 0..<game.columns {
        let pile = game.tableau[ti]
        for i in stride(from: pile.count - 1, through: 0, by: -1) {
            if let spot = layout.point(pile[i]), inside(spot) {
                return Hit(kind: .tableau, pile: ti, index: i, card: pile[i])
            }
        }
    }
    if game.hasWaste, let top = game.waste.last {
        // 3장 넘기기에서는 웨이스트가 부채꼴로 펼쳐진다. 어느 장을 눌러도 맨 위 카드를 집는다.
        let visible = min(game.waste.count, game.kind == .klondike
                          ? ((game as? Klondike)?.drawCount ?? 3) == 3 ? 3 : 1
                          : 1)
        for card in game.waste.suffix(visible).reversed() {
            if let spot = layout.point(card), inside(spot) {
                return Hit(kind: .waste, pile: 0, index: game.waste.count - 1, card: top)
            }
        }
    }
    for (ci, cell) in game.freecells.enumerated() {
        guard let card = cell.last, let spot = layout.point(card), inside(spot) else { continue }
        return Hit(kind: .freecell, pile: ci, index: cell.count - 1, card: card)
    }
    for fi in 0..<game.foundationsCount {
        guard let card = foundationCard(game, fi), let spot = layout.point(card), inside(spot)
        else { continue }
        let index = game.kind == .spider ? 0 : game.foundations[fi].count - 1
        return Hit(kind: .foundation, pile: fi, index: index, card: card)
    }
    if game.hasStock, let spot = layout.slot(.stock, 0), inside(spot) {
        return Hit(kind: .stock, pile: 0, index: 0, card: nil)
    }
    return nil
}

/// 두 사각형이 겹치는 넓이.
func rectOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let dx = min(a.maxX, b.maxX) - max(a.minX, b.minX)
    let dy = min(a.maxY, b.maxY) - max(a.minY, b.minY)
    return (dx > 0 && dy > 0) ? dx * dy : 0
}

/// 카드 하나가 차지하는 사각형.
func cardRect(_ origin: CGPoint) -> CGRect {
    CGRect(x: origin.x, y: origin.y, width: Metrics.cardW, height: Metrics.cardH)
}
