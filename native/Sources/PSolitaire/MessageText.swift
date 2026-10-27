// Logger.swift — 실행 로그(debuglog.py 상당). 실패해도 게임 진행을 막지 않는다.

import Foundation
import PSolitaireKit

final class Logger {
    static let shared = Logger()

    static let logPath = NSString(string: "~/Library/Logs/P-Solitaire.log").expandingTildeInPath

    private let queue = DispatchQueue(label: "com.borasarang.PSolitaire.log")
    private let formatter: DateFormatter
    private(set) var errorCount = 0

    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    func info(_ category: String, _ message: String) { write("INFO", category, message) }
    func cache(_ category: String, _ message: String) { write("CACHE", category, message) }
    func perf(_ category: String, _ message: String) { write("PERF", category, message) }

    func error(_ category: String, _ message: String, code: String) {
        write("ERROR", category, "\(message) [\(code)]")
        queue.sync { errorCount += 1 }
    }

    func resetErrors() { queue.sync { errorCount = 0 } }

    private func write(_ level: String, _ category: String, _ message: String) {
        let line = "\(formatter.string(from: Date())) [\(level)] [\(category)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = URL(fileURLWithPath: Logger.logPath)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}

// MARK: - 한국어 문구(오류·도움말·정보)

enum MessageText {
    /// 오류 코드 → 사용자에게 보여 줄 문구.
    static func userMessage(_ code: String) -> String {
        switch code {
        case "E-MACOS-GAME-0001":
            return "전적 파일을 읽지 못했습니다. 기록은 처음부터 다시 시작합니다."
        case "E-MACOS-GAME-0002":
            return "전적을 저장하지 못했습니다. 이번 판 기록이 남지 않을 수 있습니다."
        case "E-MACOS-GAME-0003":
            return "오류 메시지 표를 읽지 못했습니다."
        case "E-MACOS-AUDIO-0001":
            return "배경음 파일을 찾지 못했습니다. 설정에서 다른 곡을 골라 주세요."
        case "E-MACOS-AUDIO-0002":
            return "배경음을 재생하지 못했습니다. 설정에서 다시 시도해 주세요."
        default:
            return "알 수 없는 문제가 생겼습니다(\(code))."
        }
    }

    static let keysKlondike = """
    [키보드]
    · ⌘N 새 게임              · ⌘R 같은 판 다시 시작
    · ⌘Z 실행 취소            · ⇧⌘Z 실행 복귀
    · Space 카드 넘기기        · ⇧⌘H 힌트
    · ⌥⌘A 자동 완성           · D 1장/3장 전환
    · ⌘= / ⌘- / ⌘0 확대·축소·100%
    · ⌘1/2/3 게임 바꾸기       · ⌘, 설정
    · ⇧⌘A 자동 기능 모두 켜기/끄기
    · 화면 아래 버튼: 새 게임 · 취소 · 힌트 · 확대
    · ? / F1 이 도움말
    """

    static let keysFreeCell = """
    [키보드]
    · ⌘N 새 게임              · ⌘R 같은 판 다시 시작
    · ⌘Z 실행 취소            · ⇧⌘Z 실행 복귀
    · ⇧⌘H 힌트                · ⌥⌘A 자동 완성
    · ⌘= / ⌘- / ⌘0 확대·축소·100%
    · ⌘1/2/3 게임 바꾸기       · ⌘, 설정
    · ⇧⌘A 자동 기능 모두 켜기/끄기
    · 화면 아래 버튼: 새 게임 · 취소 · 힌트 · 확대
    · ? / F1 이 도움말
    """

    static let keysSpider = """
    [키보드]
    · ⌘N 새 게임              · ⌘R 같은 판 다시 시작
    · ⌘Z 실행 취소            · ⇧⌘Z 실행 복귀
    · Space 스톡 돌리기        · ⇧⌘H 힌트
    · ⌘= / ⌘- / ⌘0 확대·축소·100%
    · ⌘1/2/3 게임 바꾸기       · ⌘, 설정
    · ⇧⌘A 자동 기능 모두 켜기/끄기
    · 화면 아래 버튼: 새 게임 · 취소 · 힌트 · 확대
    · ? / F1 이 도움말
    """

    static let auto = """
    [자동 기능] (메뉴 "게임 → 자동 기능", ⇧⌘A 로 모두 켜기/끄기)
    · 더블클릭 자동 이동        : 더블클릭하면 갈 곳을 찾아 옮깁니다.
    · 이동 뒤 파운데이션 자동 올리기 : 내가 옮긴 뒤 올릴 수 있는 카드는 저절로 올라갑니다.
    · 게임 끝나면 자동 완성     : 남은 카드를 다 올릴 수 있게 되면 스스로 정리합니다.
    · 켜짐/꺼짐 상태는 저장되어 다음 실행에도 그대로입니다.
    """

    static let helpKlondike = """
    [목표]
    네 칸의 파운데이션(오른쪽 위)에 A부터 K까지 무늬별로 차곡차곡 쌓으면 이깁니다.

    [마우스]
    · 스톡(왼쪽 위 더미) 클릭 : 카드를 1장(또는 3장)씩 뒤집어 넘깁니다.
    · 카드 끌어놓기        : 카드를 집어 옮깁니다. 놓을 수 있는 자리는 노란 테두리로 표시됩니다.
    · 더블클릭             : 파운데이션에 올릴 수 있으면 자동으로 올립니다.
    · 뒤집힌 카드 클릭      : 맨 위 카드가 뒤집혀 있으면 클릭해서 공개합니다(+5점).

    """ + keysKlondike + "\n" + auto + """
    [쌓는 규칙]
    · 태블로(아래쪽 7줄): 빨강/검정을 번갈아, 숫자는 내림차순으로만 놓습니다.
    · 빈 줄에는 K만 놓을 수 있습니다.
    · 파운데이션: 같은 무늬, A → K 오름차순으로만 올립니다.

    [테마] 메뉴 "보기"에서 배경(3종)과 카드 뒷면(3종)을 고를 수 있고, 고른 값은 저장됩니다.

    [점수(표준 점수)]
    · 웨이스트 → 태블로 +5      · 태블로/웨이스트 → 파운데이션 +10
    · 뒤집힌 카드 공개 +5       · 파운데이션 → 태블로 -15
    · 스톡 재활용(3장 넘기기) -100
    · 우승 보너스 = 700000 ÷ 걸린 시간(초), 빠를수록 높습니다.
    """

    static let helpFreeCell = """
    [목표]
    네 칸의 파운데이션(오른쪽 위)에 A부터 K까지 무늬별로 쌓으면 이깁니다.
    모든 카드가 처음부터 앞면이라 운보다 실력이 중요합니다.

    [마우스]
    · 카드 끌어놓기        : 아래 8줄(태블로)과 프리셀 사이로 카드를 옮깁니다.
    · 왼쪽 위 4칸(프리셀)   : 카드 한 장을 잠시 놓아 두는 자리입니다.
    · 더블클릭             : 파운데이션 → 태블로 → 빈 프리셀 순으로 자동 이동합니다.

    """ + keysFreeCell + "\n" + auto + """
    [쌓는 규칙]
    · 태블로: 빨강/검정을 번갈아, 숫자는 내림차순으로만 놓습니다. 빈 열에는 아무 카드나.
    · 파운데이션: 같은 무늬, A → K 오름차순. 올린 카드도 다시 꺼낼 수 있습니다.
    · 여러 장 옮기기: (빈 프리셀+1) × 2^(다른 빈 열 수) 장까지 한 번에 옮길 수 있습니다.
      (예: 프리셀 4칸이 비어 있고 빈 열이 없으면 5장까지)

    [테마] 메뉴 "보기"에서 배경(3종)과 카드 뒷면(3종)을 고를 수 있고, 고른 값은 저장됩니다.

    [점수]
    · 프리셀은 점수를 매기지 않습니다. 이동 횟수와 시간으로 겨룹니다.
    · 우승 보너스 = 700000 ÷ 걸린 시간(초).
    """

    static let helpSpider = """
    [목표]
    같은 무늬 K→A 13장을 모아 8세트를 완성하면 이깁니다. 모인 세트는 저절로 빠집니다.
    카드 두 벌(104장)을 쓰며, 난이도에 따라 무늬 수가 1·2·4개입니다.

    [마우스]
    · 같은 무늬로 이어진 내림차순 묶음만 통째로 옮길 수 있습니다.
      여러 장을 한 번에 옮기려면 그 묶음의 맨 위 카드(겹쳐진 위쪽 띠)를 잡으세요.
      무늬가 섞인 자리에서 잡으면 그 위 카드까지(같은 무늬인 만큼)만 집힙니다.
      한 장만 집히면 상태줄에 왜 그런지(무늬가 다름) 잠깐 나옵니다.
    · 무늬가 섞여도 통째로 옮기고 싶으면 메뉴 "게임 → 스파이더 묶음 이동"에서
      "무늬 상관없이 (쉬움)"을 고르세요. 기본값은 MS 규칙과 같은 "같은 무늬만"입니다.
    · 스톡(왼쪽 위) 클릭   : 열마다 한 장씩 10장을 돌립니다(빈 열이 있으면 못 돌립니다).
    · 더블클릭             : 같은 무늬로 이어지거나 카드를 드러내는 자리로 옮깁니다.

    """ + keysSpider + "\n" + auto + """
    [쌓는 규칙]
    · 태블로: 숫자는 내림차순이면 되고 무늬는 상관없습니다(묶음 이동은 같은 무늬만).
    · 빈 열에는 아무 카드나 놓을 수 있습니다.
    · 앞 4줄은 6장, 나머지 6줄은 5장으로 시작합니다(맨 위 한 장만 앞면).

    [난이도]
    · 1무늬(쉬움) / 2무늬(보통) / 4무늬(어려움) — 메뉴 "게임 → 스파이더 난이도"

    [테마] 메뉴 "보기"에서 배경(3종)과 카드 뒷면(3종)을 고를 수 있고, 고른 값은 저장됩니다.

    [점수]
    · 500점에서 시작해 이동마다 -1, 세트마다 +100.
    · 우승 보너스 = 700000 ÷ 걸린 시간(초).
    """

    static func help(_ kind: GameKind) -> String {
        switch kind {
        case .klondike: return helpKlondike
        case .freecell: return helpFreeCell
        case .spider: return helpSpider
        }
    }

    static let aboutCommon = """
    · 게임 규칙: PSolitaireKit (창 없이 테스트 가능)
    · 화면/조작 : SwiftUI (네이티브, 파이썬 의존 없음)
    · 카드 그림은 이미지 파일 없이 도형으로 직접 그립니다.
    · 게임 바꾸기: 메뉴 "게임" 또는 Cmd+1(클론다이크)·2(프리셀)·3(스파이더)
    · 자동 기능: 메뉴 "게임 → 자동 기능" 또는 ⇧⌘A
    · 테마(배경·카드 뒷면): 메뉴 "보기" 또는 설정(⌘,)
    · 확대/축소: ⌘= · ⌘- · ⌘0 (100~200%, 화면에 맞게 제한)
    · 화면 아래 버튼: 새 게임 · 취소 · 힌트 · 확대
    · 배경음: 설정(⌘,) → 소리 · 5곡 · Kevin MacLeod (incompetech.com) · CC BY 4.0
    · 이어하기: 앱을 꺼도 진행 중인 판을 자동 저장하고 다음 실행 때 이어서 엽니다.
    · 전적·설정은 ~/.psolitaire-nat.json 에 저장됩니다.
    """

    static func about(_ kind: GameKind) -> String {
        let head: String
        switch kind {
        case .klondike: head = "클론다이크(마이크로소프트 클래식 솔리테어)"
        case .freecell: head = "프리셀(FreeCell)"
        case .spider: head = "스파이더(Spider, 2벌 104장)"
        }
        return head + "\n\n" + aboutCommon
    }
}
