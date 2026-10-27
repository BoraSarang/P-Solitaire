// SeededRandom.swift — 시드로 재현되는 난수(같은 시드 → 같은 판).

import Foundation

/// SplitMix64: 시드가 같으면 항상 같은 순서를 낸다(판 재현용).
public struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: Int) {
        var s = UInt64(bitPattern: Int64(seed))
        s = s &* 0x9E37_79B9_7F4A_7C15
        state = s | 1
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 새 시드(1 ~ 999,999,999) — 파이썬 `random.randrange(1, 10**9)` 과 같은 범위.
public func randomSeed() -> Int { Int.random(in: 1..<1_000_000_000) }
