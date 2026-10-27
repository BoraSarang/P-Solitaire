// Drawing.swift — 카드 앞면·뒷면·자리 표시를 직접 그린다(이미지 파일 없음).
// solitaire.py 의 draw_suit / draw_card_back / draw_card_face / draw_slots 이식.

import SwiftUI
import PSolitaireKit

enum DrawFonts {
    static let corner = Font.system(size: 13, weight: .bold)
    static let court = Font.system(size: 30, weight: .bold)
    static let status = Font.system(size: 12)
    static let statusBold = Font.system(size: 12, weight: .bold)
}

// MARK: - 도형 도우미

/// 둥근 사각형 경로.
func cardPath(_ origin: CGPoint, inset: CGFloat = 0, radius: CGFloat = Metrics.cardRadius) -> Path {
    let rect = CGRect(x: origin.x + inset, y: origin.y + inset,
                      width: Metrics.cardW - inset * 2, height: Metrics.cardH - inset * 2)
    return Path(roundedRect: rect, cornerRadius: radius)
}

/// 주어진 꼭짓점을 지나는 부드러운 닫힌 곡선(Tk `smooth=True` 와 같은 방식).
///
/// 각 꼭짓점을 제어점으로 삼고 이웃 구간의 중점을 잇는 2차 곡선을 만든다.
func smoothClosedPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    let n = points.count
    guard n >= 3 else { return path }
    func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    path.move(to: mid(points[n - 1], points[0]))
    for i in 0..<n {
        let control = points[i]
        let end = mid(points[i], points[(i + 1) % n])
        path.addQuadCurve(to: end, control: control)
    }
    path.closeSubpath()
    return path
}

/// 무늬(♠♥♦♣)를 도형으로 그린다(글꼴에 없는 글자 문제를 피한다).
func drawSuit(_ ctx: inout GraphicsContext, suit: Suit, cx: CGFloat, cy: CGFloat,
              size: CGFloat, color: Color, tags: Int = 0) {
    let s = size
    switch suit {
    case .diamonds:
        let path = smoothClosedPath([
            CGPoint(x: cx, y: cy - s / 2), CGPoint(x: cx + s / 2, y: cy),
            CGPoint(x: cx, y: cy + s / 2), CGPoint(x: cx - s / 2, y: cy),
        ])
        ctx.fill(path, with: .color(color))

    case .hearts:
        let path = smoothClosedPath([
            CGPoint(x: cx, y: cy + s * 0.45),
            CGPoint(x: cx - s * 0.50, y: cy + s * 0.00), CGPoint(x: cx - s * 0.45, y: cy - s * 0.30),
            CGPoint(x: cx - s * 0.18, y: cy - s * 0.34), CGPoint(x: cx, y: cy - s * 0.12),
            CGPoint(x: cx + s * 0.18, y: cy - s * 0.34), CGPoint(x: cx + s * 0.45, y: cy - s * 0.30),
            CGPoint(x: cx + s * 0.50, y: cy + s * 0.00),
        ])
        ctx.fill(path, with: .color(color))

    case .spades:
        // 위는 뾰족하고 아래는 두 갈래로 갈라지는 스페이드 머리.
        var head = Path()
        head.move(to: CGPoint(x: cx, y: cy - s * 0.50))
        head.addCurve(to: CGPoint(x: cx + s * 0.46, y: cy + s * 0.03),
                      control1: CGPoint(x: cx + s * 0.12, y: cy - s * 0.34),
                      control2: CGPoint(x: cx + s * 0.46, y: cy - s * 0.13))
        head.addCurve(to: CGPoint(x: cx, y: cy + s * 0.11),
                      control1: CGPoint(x: cx + s * 0.46, y: cy + s * 0.24),
                      control2: CGPoint(x: cx + s * 0.18, y: cy + s * 0.22))
        head.addCurve(to: CGPoint(x: cx - s * 0.46, y: cy + s * 0.03),
                      control1: CGPoint(x: cx - s * 0.18, y: cy + s * 0.22),
                      control2: CGPoint(x: cx - s * 0.46, y: cy + s * 0.24))
        head.addCurve(to: CGPoint(x: cx, y: cy - s * 0.50),
                      control1: CGPoint(x: cx - s * 0.46, y: cy - s * 0.13),
                      control2: CGPoint(x: cx - s * 0.12, y: cy - s * 0.34))
        head.closeSubpath()
        ctx.fill(head, with: .color(color))

        var stem = Path()
        stem.move(to: CGPoint(x: cx - s * 0.10, y: cy + s * 0.04))
        stem.addLine(to: CGPoint(x: cx + s * 0.10, y: cy + s * 0.04))
        stem.addLine(to: CGPoint(x: cx + s * 0.20, y: cy + s * 0.48))
        stem.addQuadCurve(to: CGPoint(x: cx - s * 0.20, y: cy + s * 0.48),
                          control: CGPoint(x: cx, y: cy + s * 0.36))
        stem.closeSubpath()
        ctx.fill(stem, with: .color(color))

    case .clubs:
        // 세 잎이 너무 많이 겹치면 버섯처럼 보이므로 간격을 조금 넓힌다.
        let r = s * 0.23
        for (dx, dy) in [(0.0, -s * 0.21), (-s * 0.27, s * 0.10), (s * 0.27, s * 0.10)] {
            let rect = CGRect(x: cx + dx - r, y: cy + dy - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
        }
        var stem = Path()
        stem.move(to: CGPoint(x: cx - s * 0.10, y: cy + s * 0.06))
        stem.addLine(to: CGPoint(x: cx + s * 0.10, y: cy + s * 0.06))
        stem.addLine(to: CGPoint(x: cx + s * 0.19, y: cy + s * 0.48))
        stem.addQuadCurve(to: CGPoint(x: cx - s * 0.19, y: cy + s * 0.48),
                          control: CGPoint(x: cx, y: cy + s * 0.37))
        stem.closeSubpath()
        ctx.fill(stem, with: .color(color))
    }
}

// MARK: - 빈 자리

func drawSlot(_ ctx: inout GraphicsContext, origin: CGPoint, theme: TableTheme) {
    ctx.fill(cardPath(origin), with: .color(theme.slotFill))
    ctx.stroke(cardPath(origin), with: .color(theme.slotLine), lineWidth: 2)
}

/// 노란 테두리(드롭 자리·힌트 표시).
func drawHighlight(_ ctx: inout GraphicsContext, origin: CGPoint, color: Color = Palette.hilight,
                   lineWidth: CGFloat = 3) {
    let rect = CGRect(x: origin.x - 2, y: origin.y - 2,
                      width: Metrics.cardW + 4, height: Metrics.cardH + 4)
    ctx.stroke(Path(roundedRect: rect, cornerRadius: Metrics.cardRadius),
               with: .color(color), lineWidth: lineWidth)
}

// MARK: - 카드 앞면

func drawCardFace(_ ctx: inout GraphicsContext, card: Card, origin: CGPoint) {
    let color = card.isRed ? Palette.red : Palette.black
    let x = origin.x, y = origin.y

    ctx.fill(cardPath(origin), with: .color(.white))
    ctx.stroke(cardPath(origin), with: .color(Palette.cardLine), lineWidth: 1)

    // 코너 표시(왼쪽 위·오른쪽 아래)는 좁은 기둥으로 두어 가운데 무늬 자리를 비운다
    ctx.draw(Text(rankChar(card.rank)).font(DrawFonts.corner).foregroundStyle(color),
             at: CGPoint(x: x + 7, y: y + 4), anchor: .topLeading)
    drawSuit(&ctx, suit: card.suit, cx: x + 12, cy: y + 28, size: 12, color: color)
    ctx.draw(Text(rankChar(card.rank)).font(DrawFonts.corner).foregroundStyle(color),
             at: CGPoint(x: x + Metrics.cardW - 7, y: y + Metrics.cardH - 4), anchor: .bottomTrailing)
    drawSuit(&ctx, suit: card.suit, cx: x + Metrics.cardW - 12, cy: y + Metrics.cardH - 28,
             size: 12, color: color)

    if card.rank <= 10 {
        let size = pipSize[card.rank] ?? 20
        // 9·10은 두 자리 코너 숫자("10")와 부딪히지 않도록 핍 영역을 조금 더 안쪽으로 둔다
        let inset: CGFloat = card.rank >= 9 ? 30 : 26
        let insetY: CGFloat = card.rank >= 9 ? 29 : 26
        let ax0 = x + inset, ay0 = y + insetY
        let ax1 = x + Metrics.cardW - inset, ay1 = y + Metrics.cardH - insetY
        for (fx, fy) in pips[card.rank] ?? [] {
            drawSuit(&ctx, suit: card.suit, cx: ax0 + (ax1 - ax0) * fx,
                     cy: ay0 + (ay1 - ay0) * fy, size: size, color: color)
        }
    } else {
        let inner = CGRect(x: x + 14, y: y + 16,
                           width: Metrics.cardW - 28, height: Metrics.cardH - 32)
        ctx.stroke(Path(roundedRect: inner, cornerRadius: 5), with: .color(color), lineWidth: 1)
        ctx.draw(Text(rankChar(card.rank)).font(DrawFonts.court).foregroundStyle(color),
                 at: CGPoint(x: x + Metrics.cardW / 2, y: y + Metrics.cardH / 2 - 14), anchor: .center)
        drawSuit(&ctx, suit: card.suit, cx: x + Metrics.cardW / 2, cy: y + Metrics.cardH / 2 + 26,
                 size: 20, color: color)
    }
}

// MARK: - 카드 뒷면

func drawCardBack(_ ctx: inout GraphicsContext, origin: CGPoint, style: String, theme: BackTheme) {
    let x = origin.x, y = origin.y
    ctx.fill(cardPath(origin), with: .color(theme.deep))
    ctx.stroke(cardPath(origin), with: .color(theme.edge), lineWidth: 1)
    ctx.fill(cardPath(origin, inset: 5, radius: 4), with: .color(theme.mid))

    let x0 = x + 8, y0 = y + 8, x1 = x + Metrics.cardW - 8, y1 = y + Metrics.cardH - 8
    let cx = x + Metrics.cardW / 2, cy = y + Metrics.cardH / 2

    switch style {
    case "rays":
        drawBackRays(&ctx, x0: x0, y0: y0, x1: x1, y1: y1, cx: cx, cy: cy, color: theme.line)
    case "dots":
        drawBackDots(&ctx, x0: x0, y0: y0, x1: x1, y1: y1,
                     line: theme.line, hilite: theme.hilite)
    default:
        drawBackLattice(&ctx, x0: x0, y0: y0, x1: x1, y1: y1, color: theme.line)
    }

    let inner = CGRect(x: x + 17, y: y + 17,
                       width: Metrics.cardW - 34, height: Metrics.cardH - 34)
    ctx.stroke(Path(roundedRect: inner, cornerRadius: 4), with: .color(theme.hilite), lineWidth: 1)

    if style == "rays" {
        let rect = CGRect(x: cx - 16, y: cy - 16, width: 32, height: 32)
        ctx.fill(Path(ellipseIn: rect), with: .color(theme.deep))
        ctx.stroke(Path(ellipseIn: rect), with: .color(theme.hilite), lineWidth: 1)
    } else {
        let center = smoothClosedPath([
            CGPoint(x: cx, y: cy - 19), CGPoint(x: cx + 19, y: cy),
            CGPoint(x: cx, y: cy + 19), CGPoint(x: cx - 19, y: cy),
        ])
        ctx.fill(center, with: .color(theme.deep))
        ctx.stroke(center, with: .color(theme.hilite), lineWidth: 1)
    }
}

/// 비스듬한 격자 무늬(안쪽 사각형에 맞게 잘라 그린다).
func drawBackLattice(_ ctx: inout GraphicsContext, x0: CGFloat, y0: CGFloat,
                     x1: CGFloat, y1: CGFloat, color: Color) {
    let step: CGFloat = 11
    let width = x1 - x0, height = y1 - y0

    func clip(_ px: CGFloat, _ py: CGFloat, _ dx: CGFloat, _ dy: CGFloat)
        -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        var t0: CGFloat = 0.0, t1: CGFloat = 1.0
        for (p, q) in [(-dx, px - x0), (dx, x1 - px), (-dy, py - y0), (dy, y1 - py)] {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let r = q / p
                if p < 0 {
                    if r > t1 { return nil }
                    t0 = max(t0, r)
                } else {
                    if r < t0 { return nil }
                    t1 = min(t1, r)
                }
            }
        }
        return (px + t0 * dx, py + t0 * dy, px + t1 * dx, py + t1 * dy)
    }

    var path = Path()
    let count = Int((width + height) / step) + 2
    for d in 0..<count {
        for dy in [CGFloat(1), CGFloat(-1)] {
            let start = x0 + CGFloat(d) * step - height
            guard let seg = clip(start, dy == 1 ? y0 : y1, width + height, dy * (width + height))
            else { continue }
            path.move(to: CGPoint(x: seg.0, y: seg.1))
            path.addLine(to: CGPoint(x: seg.2, y: seg.3))
        }
    }
    ctx.stroke(path, with: .color(color), lineWidth: 1)
}

/// 가운데에서 사방으로 뻗는 햇살 무늬.
func drawBackRays(_ ctx: inout GraphicsContext, x0: CGFloat, y0: CGFloat,
                  x1: CGFloat, y1: CGFloat, cx: CGFloat, cy: CGFloat, color: Color) {
    var path = Path()
    for deg in stride(from: 0, to: 360, by: 12) {
        let rad = CGFloat(deg) * .pi / 180
        let dx = cos(rad), dy = sin(rad)
        let tx = dx > 1e-9 ? (x1 - cx) / dx : (dx < -1e-9 ? (x0 - cx) / dx : 1e9)
        let ty = dy > 1e-9 ? (y1 - cy) / dy : (dy < -1e-9 ? (y0 - cy) / dy : 1e9)
        let t = min(abs(tx), abs(ty))
        path.move(to: CGPoint(x: cx, y: cy))
        path.addLine(to: CGPoint(x: cx + dx * t, y: cy + dy * t))
    }
    ctx.stroke(path, with: .color(color), lineWidth: 1)
}

/// 작은 마름모를 촘촘히 놓은 물방울 무늬(두 색을 번갈아).
func drawBackDots(_ ctx: inout GraphicsContext, x0: CGFloat, y0: CGFloat,
                  x1: CGFloat, y1: CGFloat, line: Color, hilite: Color) {
    let stepX: CGFloat = 13, stepY: CGFloat = 10, s: CGFloat = 5
    var row = 0
    var y = y0 + stepY
    while y <= y1 - 3 {
        var x = x0 + 6 + (row % 2 == 1 ? stepX / 2 : 0)
        var col = 0
        while x <= x1 - 4 {
            if x - s >= x0 && x + s <= x1 && y - s >= y0 && y + s <= y1 {
                let fill = (row + col) % 2 == 0 ? hilite : line
                let diamond = smoothClosedPath([
                    CGPoint(x: x, y: y - s), CGPoint(x: x + s, y: y),
                    CGPoint(x: x, y: y + s), CGPoint(x: x - s, y: y),
                ])
                ctx.fill(diamond, with: .color(fill))
            }
            x += stepX
            col += 1
        }
        y += stepY
        row += 1
    }
}
