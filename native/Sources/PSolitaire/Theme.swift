// Theme.swift — 화면 치수·테마(배경·카드 뒷면)·카드 무늬 배치 상수.
// solitaire.py 의 "화면 배치 / 색상 / 테마" 부분을 그대로 옮겼다.

import SwiftUI
import PSolitaireKit

// MARK: - 화면 치수(파이썬과 같은 값 → 창 크기도 같다)

enum Metrics {
    static let cardW: CGFloat = 80
    static let cardH: CGFloat = 112
    static let gap: CGFloat = 13
    static let margin: CGFloat = 18
    static let topY: CGFloat = 18
    static let tableauY: CGFloat = topY + cardH + 24
    static let faceUpDY: CGFloat = 19
    static let faceDownDY: CGFloat = 6
    static let tableauAreaH: CGFloat = 6 * faceDownDY + 12 * faceUpDY
    /// 보드 아래 버튼 줄(새 게임·취소·힌트·확대).
    static let controlH: CGFloat = 46
    static let statusH: CGFloat = 34
    static let wasteFan: CGFloat = 24
    static let cardRadius: CGFloat = 7

    static let windowH: CGFloat = tableauY + tableauAreaH + cardH + controlH + statusH + 10

    static func windowWidth(columns: Int) -> CGFloat {
        margin * 2 + CGFloat(columns) * cardW + CGFloat(columns - 1) * gap
    }

    static var cardSize: CGSize { CGSize(width: cardW, height: cardH) }
}

// MARK: - 색

extension Color {
    /// "#rrggbb" 문자열로 색을 만든다(테마 표를 그대로 옮기기 위해).
    init(hex: String) {
        var value: UInt64 = 0
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        Scanner(string: text).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xff) / 255.0,
                  green: Double((value >> 8) & 0xff) / 255.0,
                  blue: Double(value & 0xff) / 255.0,
                  opacity: 1.0)
    }
}

enum Palette {
    static let cardLine = Color(hex: "#3a3a3a")
    static let red = Color(hex: "#d40000")
    static let black = Color(hex: "#141414")
    static let statusFG = Color(hex: "#d8f0d8")
    static let statusFGDim = Color(hex: "#9fd39f")
    static let noticeFG = Color(hex: "#ffd27a")
    static let panelBG = Color(hex: "#101010")
    static let panelFG = Color(hex: "#d8f0d8")
    static let panelHead = Color(hex: "#9fd39f")
    static let hilight = Color(hex: "#ffe14d")
    static let controlFG = Color(hex: "#f0fbf0")
    static let controlFGDisabled = Color(hex: "#b9d9b9")
}

// MARK: - 테마(배경·카드 뒷면)

struct TableTheme {
    let title: String
    let bg: Color
    let slotFill: Color
    let slotLine: Color
    let statusBg: Color
}

let tableThemes: [String: TableTheme] = [
    "green": TableTheme(title: "클래식 초록", bg: Color(hex: "#008000"),
                        slotFill: Color(hex: "#0a7a0a"), slotLine: Color(hex: "#16a016"),
                        statusBg: Color(hex: "#004d00")),
    "blue": TableTheme(title: "파란 탁자", bg: Color(hex: "#0f3f6e"),
                       slotFill: Color(hex: "#14497c"), slotLine: Color(hex: "#2a6fae"),
                       statusBg: Color(hex: "#08283f")),
    "dark": TableTheme(title: "어두운 탁자", bg: Color(hex: "#232326"),
                       slotFill: Color(hex: "#2d2d32"), slotLine: Color(hex: "#4d4d55"),
                       statusBg: Color(hex: "#141416")),
]
let backgroundKeys = ["green", "blue", "dark"]

struct BackTheme {
    let title: String
    let deep: Color
    let mid: Color
    let line: Color
    let edge: Color
    let hilite: Color
}

let backThemes: [String: BackTheme] = [
    "lattice": BackTheme(title: "푸른 격자", deep: Color(hex: "#123a72"),
                         mid: Color(hex: "#2a5ea8"), line: Color(hex: "#5d92d8"),
                         edge: Color(hex: "#0b1f3d"), hilite: Color(hex: "#cfe3ff")),
    "rays": BackTheme(title: "붉은 햇살", deep: Color(hex: "#7a1220"),
                      mid: Color(hex: "#b32438"), line: Color(hex: "#e08b96"),
                      edge: Color(hex: "#4d0a14"), hilite: Color(hex: "#ffd9de")),
    "dots": BackTheme(title: "청록 물방울", deep: Color(hex: "#0d5a55"),
                      mid: Color(hex: "#128a80"), line: Color(hex: "#8fd8d0"),
                      edge: Color(hex: "#07332f"), hilite: Color(hex: "#dcfffb")),
]
let backKeys = ["lattice", "rays", "dots"]

let defaultTheme = ["background": "green", "back": "lattice"]

// MARK: - 게임별 화면 스타일

struct GameStyle {
    let faceUpDY: CGFloat
    let faceDownDY: CGFloat
    let wasteFan: CGFloat
}

let gameStyles: [String: GameStyle] = [
    GameKind.klondike.rawValue: GameStyle(faceUpDY: Metrics.faceUpDY,
                                          faceDownDY: Metrics.faceDownDY,
                                          wasteFan: Metrics.wasteFan),
    GameKind.freecell.rawValue: GameStyle(faceUpDY: 24, faceDownDY: 24, wasteFan: 0),
    GameKind.spider.rawValue: GameStyle(faceUpDY: 24, faceDownDY: 7, wasteFan: 0),
]

// MARK: - 자동 기능

enum AutoFeature: String, CaseIterable {
    case double
    case collect
    case finish

    var title: String {
        switch self {
        case .double: return "더블클릭 자동 이동"
        case .collect: return "이동 뒤 파운데이션 자동 올리기"
        case .finish: return "게임 끝나면 자동 완성"
        }
    }
}

let defaultAuto: [String: Bool] = ["double": true, "collect": true, "finish": false]

// MARK: - 스파이더 묶음 이동 규칙

let spiderGroups: [String: String] = [
    "same_suit": "같은 무늬만 (MS 규칙)",
    "any_suit": "무늬 상관없이 (쉬움)",
]
let defaultSpiderGroup = "same_suit"

// MARK: - 카드 가운데 무늬 배치(가로 0=왼쪽, 1=오른쪽 / 세로 0=위, 1=아래)

let pips: [Int: [(CGFloat, CGFloat)]] = [
    1: [(0.5, 0.5)],
    2: [(0.5, 0.0), (0.5, 1.0)],
    3: [(0.5, 0.0), (0.5, 0.5), (0.5, 1.0)],
    4: [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)],
    5: [(0.0, 0.0), (1.0, 0.0), (0.5, 0.5), (0.0, 1.0), (1.0, 1.0)],
    6: [(0.0, 0.0), (1.0, 0.0), (0.0, 0.5), (1.0, 0.5), (0.0, 1.0), (1.0, 1.0)],
    7: [(0.0, 0.0), (1.0, 0.0), (0.5, 0.25), (0.0, 0.5), (1.0, 0.5), (0.0, 1.0), (1.0, 1.0)],
    8: [(0.0, 0.0), (1.0, 0.0), (0.5, 0.25), (0.0, 0.5), (1.0, 0.5), (0.5, 0.75),
        (0.0, 1.0), (1.0, 1.0)],
    9: [(0.0, 0.00), (1.0, 0.00), (0.0, 0.34), (1.0, 0.34), (0.5, 0.50),
        (0.0, 0.66), (1.0, 0.66), (0.0, 1.00), (1.0, 1.00)],
    10: [(0.0, 0.00), (1.0, 0.00), (0.5, 0.17), (0.0, 0.34), (1.0, 0.34),
         (0.0, 0.66), (1.0, 0.66), (0.5, 0.83), (0.0, 1.00), (1.0, 1.00)],
]

/// 9·10은 두 자리 숫자(코너 글자)와 부딪히지 않도록 작게 그린다.
let pipSize: [Int: CGFloat] = [1: 40, 2: 28, 3: 28, 4: 22, 5: 22, 6: 22,
                               7: 20, 8: 20, 9: 16, 10: 16]

/// 상태바 오른쪽 기본 안내.
let hintTextDefault = "⌘N 새 게임 · ⌘Z 취소 · ⇧⌘H 힌트 · ⌘= 확대"
let noticeSeconds: Double = 6.0
