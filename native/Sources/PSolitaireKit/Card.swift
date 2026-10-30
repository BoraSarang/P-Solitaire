// Card.swift — 카드·무늬·더미 참조·결과 타입 (solitaire_core.py 상단 이식)

import Foundation

// MARK: - 무늬

public enum Suit: Int, CaseIterable, Codable, Sendable {
    case spades = 0
    case hearts = 1
    case diamonds = 2
    case clubs = 3

    public var isRed: Bool { self == .hearts || self == .diamonds }
    public var char: String { ["♠", "♥", "♦", "♣"][rawValue] }
    public var nameKo: String { ["스페이드", "하트", "다이아몬드", "클럽"][rawValue] }
}

/// A→K 표기(0번 자리는 쓰지 않는다).
public let rankChars: [String] = ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]

public func rankChar(_ rank: Int) -> String {
    (rank >= 1 && rank <= 13) ? rankChars[rank] : "?"
}

// MARK: - 카드

/// 카드 일련번호(화면에서 같은 무늬·숫자 카드를 구분하려면 필요하다).
/// 풀리는 판을 백그라운드에서 만들 때 여러 스레드가 카드를 동시에 만들어도
/// 번호가 겹치지 않도록 잠금으로 보호한다.
private enum CardSerial {
    private static let lock = NSLock()
    private static var next = 1

    static func makeID() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let id = next
        next += 1
        return id
    }
}

public final class Card: Identifiable, CustomStringConvertible {
    public let rank: Int          // 1(A) ~ 13(K)
    public let suit: Suit
    public var faceup: Bool
    public let id: Int            // 카드마다 다른 일련번호

    public init(rank: Int, suit: Suit, faceup: Bool = false) {
        self.rank = rank
        self.suit = suit
        self.faceup = faceup
        self.id = CardSerial.makeID()
    }

    public var isRed: Bool { suit.isRed }
    /// 화면·드래그에서 카드를 구분하는 키(무늬-숫자-일련번호).
    public var uid: String { "\(suit.rawValue)-\(rank)-\(id)" }
    public var label: String { rankChar(rank) + suit.char }
    public var description: String { (faceup ? "+" : "-") + label }
}

/// 52장 덱(copies벌) 생성 — 모두 뒤집힌 상태.
public func makeDeck(copies: Int = 1) -> [Card] {
    var deck: [Card] = []
    for _ in 0..<copies {
        for suit in Suit.allCases {
            for rank in 1...13 { deck.append(Card(rank: rank, suit: suit)) }
        }
    }
    return deck
}

// MARK: - 자리(더미) 참조

public enum PileKind: String, Sendable {
    case stock, waste, foundation, tableau, freecell
}

public struct Ref: Hashable, Sendable {
    public var kind: PileKind
    public var index: Int
    public init(_ kind: PileKind, _ index: Int) {
        self.kind = kind
        self.index = index
    }
}

// MARK: - 결과 타입

public struct MoveResult {
    public var ok: Bool
    public var points: Int = 0
    public var flipped: Bool = false
    public var count: Int = 0
    public var sets: Int = 0
    public var action: String?
    public var reason: String?

    public static func fail(_ reason: String) -> MoveResult {
        MoveResult(ok: false, reason: reason)
    }
}

public enum Hint: Equatable, Sendable {
    case move(src: Ref, index: Int, dst: Ref)
    case draw
    case recycle
}

// MARK: - 점수 상수(마이크로소프트 "표준 점수")

public let scoreWasteToTableau = 5          // 웨이스트 → 태블로
public let scoreToFoundation = 10           // 태블로/웨이스트 → 파운데이션
public let scoreFlip = 5                    // 뒤집힌 카드 공개
public let scoreFoundationToTableau = -15   // 파운데이션 → 태블로
public let scoreRecycleDrawThree = -100     // 스톡 재활용(3장 넘기기 모드)
public let winBonusNumerator = 700_000      // 우승 보너스 = 700000 ÷ 경과 초

public let spiderBaseScore = 500
public let spiderScorePerMove = -1
public let spiderScorePerSet = 100

/// 표준 점수의 우승 보너스(빠를수록 큼).
public func winBonus(seconds: Double) -> Int {
    Int(Double(winBonusNumerator) / max(1.0, seconds))
}
