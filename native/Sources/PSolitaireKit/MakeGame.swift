// MakeGame.swift — 게임 종류 이름으로 게임을 만든다(설정 파일의 variant 문자열과 1:1).

import Foundation

public enum GameKind: String, CaseIterable, Sendable {
    case klondike
    case freecell
    case spider

    /// 메뉴·제목에 쓰는 한국어 이름.
    public var nameKo: String {
        switch self {
        case .klondike: return "클론다이크"
        case .freecell: return "프리셀"
        case .spider: return "스파이더"
        }
    }
}

/// 설정에 저장된 문자열(없거나 이상하면 클론다이크)을 게임 종류로 바꾼다.
public let defaultGameKind = GameKind.klondike

/// 게임별 옵션 — 해당 게임에 없는 옵션은 무시한다(파이썬 `make_game` 과 같은 동작).
public struct GameOptions {
    public var seed: Int?
    public var drawCount: Int?          // 클론다이크: 1 또는 3
    public var suits: Int?              // 스파이더: 1·2·4
    public var suitFree: Bool?          // 스파이더: 묶음 이동에서 무늬 무시(쉬움)

    public init(seed: Int? = nil, drawCount: Int? = nil, suits: Int? = nil, suitFree: Bool? = nil) {
        self.seed = seed
        self.drawCount = drawCount
        self.suits = suits
        self.suitFree = suitFree
    }
}

/// `kind` 는 "klondike" / "freecell" / "spider" (모르는 값이면 클론다이크).
public func makeGame(kind: String, options: GameOptions = GameOptions()) -> BaseGame {
    switch kind {
    case GameKind.freecell.rawValue:
        return FreeCell(seed: options.seed)
    case GameKind.spider.rawValue:
        return Spider(seed: options.seed, suits: options.suits ?? 1,
                      suitFree: options.suitFree ?? false)
    default:
        return Klondike(seed: options.seed, drawCount: options.drawCount ?? 3)
    }
}

public func makeGame(kind: GameKind, options: GameOptions = GameOptions()) -> BaseGame {
    makeGame(kind: kind.rawValue, options: options)
}
