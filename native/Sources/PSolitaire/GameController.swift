// GameController.swift — 게임 진행·자동 기능·설정 저장·애니메이션을 맡는 두뇌.
// solitaire.py 의 SolitaireApp 을 SwiftUI 에 맞게 옮겼다(그리기만 View 가 한다).

import SwiftUI
import AppKit
import Darwin
import PSolitaireKit

/// 화면에 띄울 알림(우승·힌트 없음·자동 완성 안내 등).
struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var primaryTitle = "확인"
    var onDismiss: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
}

/// 진행 중인 판을 버리기 전에 띄우는 확인 요청.
struct ConfirmRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let action: () -> Void
}

/// 파일에 저장하는 진행 중인 판 한 판.
struct SavedGame: Codable {
    var version = 1
    var variant: String
    var snapshot: GameSnapshot
    var elapsed: Int
    var playedCounted: Bool
    var drawCount: Int?
    var spiderSuits: Int?
    var spiderGroup: String?
    /// 풀리는 판의 시작 배치(다시 시작해도 같은 판을 유지한다).
    var spiderStart: SpiderStartLayout?
}

/// 전적 창에서 한 줄로 보여 줄 기록.
struct GameRecord {
    let kind: GameKind
    let played: Int
    let won: Int
    let bestTime: Int?
    let bestScore: Int?

    var rate: Double { played > 0 ? Double(won) * 100.0 / Double(played) : 0 }
}

/// 카드가 쏟아지는 연출에 쓰는 카드 한 장.
struct BounceCard {
    let card: Card
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
}

/// 드래그 중인 묶음.
struct DragState {
    var cards: [Card]
    var src: Ref
    var index: Int
    var start: CGPoint
    var last: CGPoint
    var origin: [ObjectIdentifier: CGPoint]
    var moved: Bool
    var delta: CGSize
}

/// 놓은 카드가 새 자리로 짧게 날아가는 연출.
struct CardFlight {
    let card: Card
    let from: CGPoint
    let to: CGPoint
    let started: Date
    let duration: Double
}

@MainActor
final class GameController: ObservableObject {
    /// 전적·설정 파일 경로(자체 검사에서는 임시 파일로 바꾼다).
    static var statsPathOverride: String?
    static var statsPath: String {
        statsPathOverride ?? NSString(string: "~/.psolitaire-nat.json").expandingTildeInPath
    }

    // ── 화면에 알리는 상태 ─────────────────────────────────────────────────
    @Published private(set) var revision = 0              // 다시 그리기 신호
    @Published private(set) var statusLeft = ""
    @Published private(set) var statusRight = hintTextDefault
    @Published private(set) var showNotice = false
    @Published private(set) var lastDrawMS: Double = 0
    @Published private(set) var busy = false
    /// 풀리는 스파이더 판을 만드는 중인가(화면을 가리는 안내에 쓴다).
    @Published private(set) var preparingDeal = false
    @Published private(set) var bounceCards: [BounceCard] = []
    @Published private(set) var flashCards: Set<ObjectIdentifier> = []
    @Published private(set) var flashSlots: [Ref] = []
    @Published private(set) var flashOn = true
    @Published private(set) var flights: [CardFlight] = []
    @Published var alert: AlertInfo?
    @Published var confirm: ConfirmRequest?
    @Published var showSeedEntry = false
    @Published private(set) var statsRevision = 0
    @Published private(set) var zoomPct = 100
    @Published var showDebugPanel = false
    @Published var windowTitle = "P-Solitaire"

    static let zoomLevels = [100, 125, 150, 175, 200]

    // ── 게임 상태 ─────────────────────────────────────────────────────────
    private(set) var game: BaseGame
    private(set) var variant: GameKind
    private(set) var settings: [String: Any]
    private(set) var stats: [String: Any]
    private(set) var layout = BoardLayout()
    var drag: DragState?
    /// 지금 누르고 있는 중인가(드래그 시작 전 판단용).
    private(set) var pressActive = false
    private(set) var dropTarget: Ref?

    private var hintText = hintTextDefault
    private var noticeCode: String?
    private var noticeUntil = Date.distantPast
    private var hintTimer: Timer?
    /// 이기는 해답을 찾는 중인가(같은 힌트를 두 번 돌리지 않는다).
    private var hintSearching = false
    /// 힌트 탐색 결과가 지금 판의 것인지 가리는 표식.
    private var hintSearchToken = UUID()
    private var tickTimer: Timer?
    private var autocompleteTimer: Timer?
    private var bounceTimer: Timer?
    private var flashTimer: Timer?
    private var flightTimer: Timer?
    private var pressTime = Date()
    private var pressHit: Hit?
    private var lastClick: (key: String?, time: Date) = (nil, .distantPast)
    private var startTS: Date?
    private var elapsedBase = 0
    private var playedCounted = false
    private var autocompleting = false
    private var bounceQueue: [(Card, Ref)] = []
    private var bounceTicks = 0
    private var startError: String?
    /// 풀리는 판 생성 작업이 서로 섞이지 않게 하는 표식.
    private var dealToken = UUID()

    /// 배경음 재생기(설정값은 아래 music* 프로퍼티가 읽고 쓴다).
    let music = MusicPlayer()

    // ── 만들기 ────────────────────────────────────────────────────────────
    init() {
        stats = GameController.loadStats()
        settings = GameController.normalize(GameController.dict(stats["settings"]))

        // 저장된 판이 있으면 그 판을 이어서 연다. 없으면 설정의 게임을 새로 배분한다.
        let saved = GameController.savedGame(from: stats)
        let key = saved?.variant ?? (settings["variant"] as? String) ?? GameKind.klondike.rawValue
        variant = GameKind(rawValue: key) ?? .klondike
        game = GameController.makeGameObject(kind: variant, settings: settings,
                                             seed: saved?.snapshot.seed)
        startTimerTick()

        if let saved, saved.variant == variant.rawValue {
            applySavedGame(saved)
            Logger.shared.info("앱", "이어하기(\(gameLabel)·시드 \(game.seed)·이동 \(game.moves)"
                               + "·설정 \(GameController.statsPath))")
        } else {
            if saved != nil { stats.removeValue(forKey: "current") }
            resetRound()
            if variant == .spider && spiderWinnable {
                dealToken = UUID()
                generateWinnableDeal(seed: game.seed, suits: spiderSuits,
                                     exact: false, round: 0, token: dealToken)
            }
        }
        updateWindowTitle()
        music.onTrackChanged = { [weak self] id in self?.musicDidAdvance(to: id) }
        music.onError = { [weak self] code in self?.notify(code, seconds: 8) }
        applyMusicSettings()
        Logger.shared.info("앱", "시작(네이티브 \(ProcessInfo.processInfo.operatingSystemVersionString)"
                           + "·게임 \(gameLabel)·설정 \(GameController.statsPath))")
        if let code = startError { notify(code) }
    }

    private var loadErrorCode: String?

    // ── 설정 읽기/쓰기 ────────────────────────────────────────────────────
    private static func dict(_ value: Any?) -> [String: Any] {
        (value as? [String: Any]) ?? [:]
    }

    static func defaultSettings() -> [String: Any] {
        ["variant": GameKind.klondike.rawValue, "draw_count": 3, "spider_suits": 1,
         "spider_group": defaultSpiderGroup, "spider_winnable": true,
         "theme": defaultTheme, "auto": defaultAuto,
         "zoom": 100, "sound": true, "animations": true,
         "music": ["on": MusicDefaults.on, "track": MusicDefaults.trackID,
                   "repeat": MusicDefaults.repeatMode.rawValue,
                   "volume": MusicDefaults.volume]]
    }

    static func defaultStats() -> [String: Any] {
        var games: [String: Any] = [:]
        for kind in GameKind.allCases {
            games[kind.rawValue] = ["played": 0, "won": 0,
                                    "best_time": NSNull(), "best_score": NSNull()]
        }
        return ["version": 2, "settings": defaultSettings(), "games": games]
    }

    /// 설정값을 안전한 범위로 맞춘다(옛 파일·손으로 고친 값 대비).
    static func normalize(_ raw: [String: Any]) -> [String: Any] {
        var s = defaultSettings()
        for (key, value) in raw where value is String || value is Int || value is Bool {
            s[key] = value
        }
        if GameKind(rawValue: (s["variant"] as? String) ?? "") == nil {
            s["variant"] = GameKind.klondike.rawValue
        }
        if ![1, 3].contains((s["draw_count"] as? Int) ?? 3) { s["draw_count"] = 3 }
        if ![1, 2, 4].contains((s["spider_suits"] as? Int) ?? 1) { s["spider_suits"] = 1 }
        if spiderGroups[(s["spider_group"] as? String) ?? ""] == nil {
            s["spider_group"] = defaultSpiderGroup
        }
        s["spider_winnable"] = (s["spider_winnable"] as? Bool) ?? true
        let theme = dict(raw["theme"])
        s["theme"] = [
            "background": backgroundKeys.contains((theme["background"] as? String) ?? "")
                ? theme["background"]! : defaultTheme["background"]!,
            "back": backKeys.contains((theme["back"] as? String) ?? "")
                ? theme["back"]! : defaultTheme["back"]!,
        ]
        let auto = dict(raw["auto"])
        var fixed: [String: Bool] = [:]
        for feature in AutoFeature.allCases {
            fixed[feature.rawValue] = (auto[feature.rawValue] as? Bool)
                ?? defaultAuto[feature.rawValue] ?? false
        }
        s["auto"] = fixed

        let music = dict(raw["music"])
        let track = (music["track"] as? String) ?? ""
        let repeatKey = (music["repeat"] as? String) ?? ""
        let volume = (music["volume"] as? NSNumber)?.doubleValue ?? MusicDefaults.volume
        s["music"] = [
            "on": (music["on"] as? Bool) ?? MusicDefaults.on,
            "track": musicTracks.contains { $0.id == track } ? track : MusicDefaults.trackID,
            "repeat": MusicRepeatMode(rawValue: repeatKey)?.rawValue
                ?? MusicDefaults.repeatMode.rawValue,
            "volume": min(1, max(0, volume)),
        ]

        let rawZoom = (s["zoom"] as? Int) ?? 100
        let nearest = GameController.zoomLevels.min {
            abs($0 - rawZoom) < abs($1 - rawZoom)
        } ?? 100
        s["zoom"] = nearest
        s["sound"] = (s["sound"] as? Bool) ?? true
        s["animations"] = (s["animations"] as? Bool) ?? true
        return s
    }

    private static func loadStats() -> [String: Any] {
        var stats = defaultStats()
        guard let data = FileManager.default.contents(atPath: statsPath),
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let root = parsed as? [String: Any] else {
            return stats
        }
        if let saved = root["settings"] as? [String: Any] {
            var merged = dict(stats["settings"])
            for (key, value) in saved where !(value is NSNull) { merged[key] = value }
            stats["settings"] = normalize(merged)
        } else {
            stats["settings"] = normalize(dict(stats["settings"]))
        }
        if let games = root["games"] as? [String: Any] {
            var merged = dict(stats["games"])
            for kind in GameKind.allCases {
                guard let record = games[kind.rawValue] as? [String: Any] else { continue }
                var current = dict(merged[kind.rawValue])
                for field in ["played", "won", "best_time", "best_score"]
                    where record[field] != nil && !(record[field] is NSNull) {
                    current[field] = record[field]
                }
                merged[kind.rawValue] = current
            }
            stats["games"] = merged
        }
        // 진행 중인 판은 설정·전적과 같은 파일에 보관한다(앱을 껐다 켜도 이어서).
        if let current = root["current"] as? [String: Any] {
            stats["current"] = current
        }
        return stats
    }

    /// 저장된 진행 중인 판을 읽는다. 형식이 깨졌으면 nil.
    private static func savedGame(from stats: [String: Any]) -> SavedGame? {
        guard let raw = stats["current"] as? [String: Any],
              JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let saved = try? JSONDecoder().decode(SavedGame.self, from: data),
              GameKind(rawValue: saved.variant) != nil else { return nil }
        return saved
    }

    func save() {
        stats["settings"] = settings              // 설정 변경분을 전적과 함께 저장한다
        do {
            let data = try JSONSerialization.data(withJSONObject: stats,
                                                  options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: URL(fileURLWithPath: GameController.statsPath), options: .atomic)
        } catch {
            Logger.shared.error("전적", "전적 저장 실패: \(error.localizedDescription)",
                                code: "E-MACOS-GAME-0002")
            notify("E-MACOS-GAME-0002")
        }
    }

    /// 자체 검사용: 판을 빈 상태로 만든다.
    func clearBoard() {
        game.tableau = Array(repeating: [], count: game.columns)
        game.foundations = Array(repeating: [], count: game.foundationsCount)
        game.freecells = Array(repeating: [], count: game.freecells.count)
        game.stock = []
        game.waste = []
        game.score = 0
        game.moves = 0
        redraw()
    }

    /// 자체 검사용: 설정 파일을 원하는 값으로 직접 써 둔다.
    static func writeSettingsForTest(_ settings: [String: Any]) {
        var stats = defaultStats()
        stats["settings"] = normalize(settings)
        if let data = try? JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: statsPath), options: .atomic)
        }
    }

    // ── 게임 만들기 ───────────────────────────────────────────────────────
    static func makeGameObject(kind: GameKind, settings: [String: Any], seed: Int? = nil,
                               suits: Int? = nil) -> BaseGame {
        let spiderSuits = suits ?? (settings["spider_suits"] as? Int) ?? 1
        let suitFree = (settings["spider_group"] as? String) == "any_suit"
        let options = GameOptions(seed: seed,
                                  drawCount: (settings["draw_count"] as? Int) ?? 3,
                                  suits: spiderSuits, suitFree: suitFree)
        return makeGame(kind: kind, options: options)
    }

    var style: GameStyle { gameStyles[variant.rawValue] ?? GameStyle(faceUpDY: 19, faceDownDY: 6, wasteFan: 24) }
    var tableTheme: TableTheme { tableThemes[backgroundKey] ?? tableThemes["green"]! }
    var backTheme: BackTheme { backThemes[backKey] ?? backThemes["lattice"]! }
    var backgroundKey: String { (GameController.dict(settings["theme"])["background"] as? String) ?? "green" }
    var backKey: String { (GameController.dict(settings["theme"])["back"] as? String) ?? "lattice" }
    var autoSettings: [String: Bool] { GameController.dict(settings["auto"]) as? [String: Bool] ?? defaultAuto }

    func autoOn(_ feature: AutoFeature) -> Bool { autoSettings[feature.rawValue] ?? false }
    func autoAllOn() -> Bool { AutoFeature.allCases.allSatisfy { autoOn($0) } }

    var spiderSuits: Int { (settings["spider_suits"] as? Int) ?? 1 }
    var spiderGroup: String { (settings["spider_group"] as? String) ?? defaultSpiderGroup }
    var spiderWinnable: Bool { (settings["spider_winnable"] as? Bool) ?? true }
    var drawCount: Int { (settings["draw_count"] as? Int) ?? 3 }

    /// 상태바·제목에 쓸 게임 이름(스파이더는 난이도 포함).
    var gameLabel: String {
        if variant == .spider, let spider = game as? Spider {
            return "스파이더(\(spider.suits)무늬)"
        }
        return variant.nameKo
    }

    var windowWidth: CGFloat { Metrics.windowWidth(columns: game.columns) }
    var windowHeight: CGFloat { Metrics.windowH }
    var zoomScale: CGFloat { CGFloat(zoomPct) / 100.0 }
    var preferredZoomPct: Int { (settings["zoom"] as? Int) ?? 100 }
    var soundOn: Bool { (settings["sound"] as? Bool) ?? true }
    var animationsOn: Bool { (settings["animations"] as? Bool) ?? true }

    // ── 배경음 ────────────────────────────────────────────────────────────
    private var musicSettings: [String: Any] { GameController.dict(settings["music"]) }
    var musicOn: Bool { (musicSettings["on"] as? Bool) ?? MusicDefaults.on }
    var musicTrackID: String {
        let key = (musicSettings["track"] as? String) ?? MusicDefaults.trackID
        return musicTracks.contains { $0.id == key } ? key : MusicDefaults.trackID
    }
    var musicRepeatMode: MusicRepeatMode {
        MusicRepeatMode(rawValue: (musicSettings["repeat"] as? String) ?? "")
            ?? MusicDefaults.repeatMode
    }
    var musicVolume: Double {
        min(1, max(0, (musicSettings["volume"] as? NSNumber)?.doubleValue
            ?? MusicDefaults.volume))
    }

    var musicTrack: MusicTrack {
        musicTracks.first { $0.id == musicTrackID } ?? musicTracks[0]
    }

    func updateWindowTitle() {
        windowTitle = "P-Solitaire — \(gameLabel) · #\(game.seed)"
    }

    /// 이 게임 창이 화면(메뉴 막대·독 제외) 안에 들어가는 가장 큰 단계.
    private func fitZoom(_ requested: Int, kind: GameKind? = nil) -> Int {
        let target = GameController.zoomLevels.min {
            abs($0 - requested) < abs($1 - requested)
        } ?? 100
        let columns: Int
        switch kind ?? variant {
        case .klondike: columns = 7
        case .freecell: columns = 8
        case .spider: columns = 10
        }
        let width = Metrics.windowWidth(columns: columns)
        let height = Metrics.windowH + 28          // 제목 표시줄 포함
        let visible = (NSApplication.shared.keyWindow?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var result = target
        while result > 100 {
            let scale = CGFloat(result) / 100.0
            if width * scale <= visible.width - 24 && height * scale <= visible.height - 24 {
                break
            }
            result -= 25
        }
        return result
    }

    /// 현재 판에 맞춰 유효 확대/축소를 다시 계산한다(설정값은 유지).
    @discardableResult
    func applyZoomForCurrentGame(showHint: Bool = false) -> Bool {
        let fitted = fitZoom(preferredZoomPct)
        let changed = fitted != zoomPct
        zoomPct = fitted
        if showHint && fitted < preferredZoomPct {
            setHint("화면에 맞추어 \(fitted)%로 표시합니다")
        }
        return changed
    }

    func setZoom(_ requested: Int) {
        let target = GameController.zoomLevels.min {
            abs($0 - requested) < abs($1 - requested)
        } ?? 100
        settings["zoom"] = target
        let fitted = fitZoom(target)
        zoomPct = fitted
        save()
        if fitted < target {
            setHint("이 화면에서는 \(fitted)%까지만 표시됩니다")
        } else {
            setHint("확대 \(fitted)%")
        }
        adjustWindowForZoom()
    }

    func zoomIn() {
        let next = GameController.zoomLevels.first { $0 > preferredZoomPct } ?? 200
        setZoom(next)
    }

    func zoomOut() {
        let previous = GameController.zoomLevels.last { $0 < preferredZoomPct } ?? 100
        setZoom(previous)
    }

    func zoomReset() { setZoom(100) }

    /// 확대/축소 뒤 창이 화면 밖으로 나가지 않도록 위치를 다듬는다.
    func adjustWindowForZoom() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            let windows = NSApplication.shared.windows
            guard let window = windows.first(where: { $0.title.hasPrefix("P-Solitaire —") })
                    ?? NSApplication.shared.keyWindow
                    ?? windows.first(where: { $0.isVisible }) else {
                return
            }
            guard let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
            var frame = window.frame
            if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
            if frame.minX < screen.minX { frame.origin.x = screen.minX }
            if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
            if frame.minY < screen.minY { frame.origin.y = screen.minY }
            if frame != window.frame { window.setFrame(frame, display: true) }
        }
    }

    private func playSound(_ name: String) {
        guard soundOn else { return }
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.stop()
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    // ── 다시 그리기 ───────────────────────────────────────────────────────
    func redraw() {
        let started = DispatchTime.now().uptimeNanoseconds
        layout = computeLayout(game, style: style)
        revision &+= 1
        lastDrawMS = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000.0
        if lastDrawMS > 60 {
            Logger.shared.perf("그리기", String(format: "다시 그리기 %.0fms", lastDrawMS))
        }
    }

    private func startTimerTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatus() }
        }
    }

    // ── 카드 이동 애니메이션 ──────────────────────────────────────────────
    private func clearFlights() {
        flightTimer?.invalidate()
        flightTimer = nil
        flights = []
    }

    func beginFlights(_ cards: [Card], origins: [ObjectIdentifier: CGPoint]) {
        guard animationsOn, !game.isWon() else { return }
        flights = cards.compactMap { card in
            guard let from = origins[ObjectIdentifier(card)],
                  let to = layout.point(card),
                  from != to else { return nil }
            return CardFlight(card: card, from: from, to: to, started: Date(), duration: 0.14)
        }
        guard !flights.isEmpty else { return }
        flightTimer?.invalidate()
        flightTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickFlights() }
        }
        revision &+= 1
    }

    private func tickFlights() {
        let now = Date()
        let before = flights.count
        flights.removeAll { now.timeIntervalSince($0.started) >= $0.duration }
        revision &+= 1
        if flights.isEmpty {
            flightTimer?.invalidate()
            flightTimer = nil
        } else if before != flights.count {
            revision &+= 1
        }
    }

    func isFlying(_ card: Card) -> Bool {
        flights.contains { $0.card === card }
    }

    func flightPosition(_ flight: CardFlight) -> CGPoint {
        let raw = Date().timeIntervalSince(flight.started) / flight.duration
        let t = CGFloat(min(1, max(0, raw)))
        let eased = 1 - (1 - t) * (1 - t)          // 빠르게 출발해 부드럽게 도착
        return CGPoint(x: flight.from.x + (flight.to.x - flight.from.x) * eased,
                       y: flight.from.y + (flight.to.y - flight.from.y) * eased)
    }

    // ── 상태바 ────────────────────────────────────────────────────────────
    func updateStatus() {
        let total = elapsedSeconds()
        let minutes = total / 60, seconds = total % 60
        if variant == .freecell {
            statusLeft = String(format: "%@ · 시간 %02d:%02d · 이동 %d · 빈 프리셀 %d칸 · 남은 카드 %d",
                                gameLabel, minutes, seconds, game.moves, game.freeCellsFree(),
                                game.cardsRemaining())
        } else {
            let extra: String
            if variant == .spider {
                extra = "완성 \(game.foundations.count)/\(game.foundationsCount) · 스톡 \((game as? Spider)?.dealsLeft() ?? 0)번"
            } else {
                extra = "\((game as? Klondike)?.drawCount ?? 3)장 넘기기 · 스톡 \(game.stock.count)장"
            }
            statusLeft = "\(gameLabel) · 점수 \(game.score) · " + String(
                format: "시간 %02d:%02d · 이동 %d · %@", minutes, seconds, game.moves, extra)
        }
        if Date() < noticeUntil, let code = noticeCode {
            statusRight = "⚠ " + MessageText.userMessage(code)
            showNotice = true
        } else {
            statusRight = hintText
            showNotice = false
        }
    }

    func startTimer() {
        if startTS == nil && !game.isWon() { startTS = Date() }
    }

    func elapsedSeconds() -> Int {
        guard let start = startTS else { return elapsedBase }
        return elapsedBase + Int(Date().timeIntervalSince(start))
    }

    /// 오류 문구를 상태바에 잠깐 보여 준다.
    func notify(_ code: String, seconds: Double = noticeSeconds) {
        noticeCode = code
        noticeUntil = Date().addingTimeInterval(seconds)
        updateStatus()
    }

    /// 상태바 오른쪽에 안내 문구를 잠깐 보여 준다.
    func setHint(_ text: String, seconds: Double = 3.0) {
        hintTimer?.invalidate()
        hintText = text
        updateStatus()
        hintTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restoreHint() }
        }
    }

    func restoreHint() {
        hintTimer = nil
        hintText = hintTextDefault
        updateStatus()
    }

    // ── 게임 바꾸기/새 판 ─────────────────────────────────────────────────
    func switchGame(_ kind: GameKind, seed: Int? = nil, suits: Int? = nil) {
        confirm = nil
        if let suits { settings["spider_suits"] = suits }
        settings["variant"] = kind.rawValue
        cancelAnimations()
        dealToken = UUID()
        preparingDeal = false
        busy = false
        variant = kind
        game = GameController.makeGameObject(kind: kind, settings: settings, seed: seed, suits: suits)
        applyZoomForCurrentGame()
        updateWindowTitle()
        Logger.shared.info("게임", "\(gameLabel)로 전환(시드 \(game.seed))")
        if kind == .spider && spiderWinnable {
            generateWinnableDeal(seed: seed ?? game.seed,
                                 suits: (game as? Spider)?.suits ?? spiderSuits,
                                 exact: seed != nil, round: 0, token: dealToken)
            return
        }
        resetRound()
    }

    func newGame(seed: Int? = nil) {
        confirm = nil
        cancelAnimations()
        let exact = seed != nil
        let target = seed ?? randomSeed()
        if variant == .spider && spiderWinnable {
            dealToken = UUID()
            generateWinnableDeal(seed: target, suits: spiderSuits,
                                 exact: exact, round: 0, token: dealToken)
            return
        }
        game.deal(seed: target)
        let extra = variant == .klondike ? "·\((game as? Klondike)?.drawCount ?? 3)장 넘기기" : ""
        Logger.shared.info("게임", "\(gameLabel) 새 게임(시드 \(game.seed)\(extra))")
        resetRound()
    }

    func restartGame() {
        guard !preparingDeal else { return }
        confirm = nil
        cancelAnimations()
        game.restart()
        Logger.shared.info("게임", "같은 판 다시 시작(시드 \(game.seed))")
        resetRound()
    }

    // ── 풀리는 스파이더 판 만들기 ─────────────────────────────────────────
    /// 1무늬 판을 풀어 해답을 찾은 뒤 무늬를 다시 배정해, 1·2·4무늬 모두
    /// 반드시 풀리는 판을 만든다. 만드는 동안에는 입력을 막고 안내를 보여 준다.
    private func generateWinnableDeal(seed: Int, suits: Int, exact: Bool,
                                      round: Int, token: UUID) {
        preparingDeal = true
        busy = true
        hintTimer?.invalidate()
        hintText = "풀리는 판을 만드는 중…"
        updateStatus()
        revision &+= 1
        // 만드는 도중 앱을 끄면 일반 배분이 이어하기로 남지 않게 지운다.
        stats.removeValue(forKey: "current")
        save()

        let attempts = exact ? 1 : 4
        let timeLimit: TimeInterval = exact ? 3.0 : 1.5
        Task.detached(priority: .userInitiated) {
            var found = SpiderWinnable.makeDeal(suits: suits, startingSeed: seed,
                                                attempts: attempts,
                                                timeLimit: timeLimit,
                                                nodeLimit: 1_000_000)
            // 여러 번 시도해도 못 찾으면, 이미 검증된 번호에서 마지막으로 한 번 더 찾는다.
            if found == nil, !exact, round >= 2 {
                found = SpiderWinnable.makeDeal(suits: suits, startingSeed: 1000,
                                                attempts: 2, timeLimit: 5.0,
                                                nodeLimit: 1_500_000)
            }
            let deal = found
            await MainActor.run { [weak self] in
                guard let self, token == self.dealToken else { return }
                if deal == nil, !exact, round < 2 {
                    self.generateWinnableDeal(seed: randomSeed(), suits: suits,
                                              exact: false, round: round + 1, token: token)
                    return
                }
                self.finishWinnableDeal(deal, requestedSeed: seed, exact: exact)
            }
        }
    }

    private func finishWinnableDeal(_ deal: SpiderWinnableDeal?, requestedSeed: Int,
                                    exact: Bool) {
        preparingDeal = false
        busy = false
        guard let deal else {
            if exact {
                alert = AlertInfo(title: "풀리는 판",
                                  message: "판 번호 \(requestedSeed)로는 풀리는 판을 찾지 못했습니다.\n"
                                    + "다른 판 번호를 넣어 주세요.")
            } else {
                alert = AlertInfo(title: "풀리는 판",
                                  message: "풀리는 판을 만들지 못했습니다.\n새 게임을 다시 시작해 주세요.")
            }
            // 진행 중이던 판은 그대로 둔다(시간·이동 수를 되돌리지 않는다).
            restoreHint()
            saveCurrentGame()
            redraw()
            return
        }
        let spider = Spider(seed: deal.sourceSeed, suits: deal.suits)
        spider.applyDeal(deal)
        game = spider
        variant = .spider
        applyZoomForCurrentGame()
        updateWindowTitle()
        Logger.shared.info("게임", "풀리는 판 배분(시드 \(deal.sourceSeed)·\(deal.suits)무늬"
                           + "·해답 \(deal.solution.count)수)")
        resetRound()
        if deal.sourceSeed != requestedSeed {
            setHint("이 번호로는 풀리는 판이 없어 #\(deal.sourceSeed)로 시작합니다", seconds: 5)
        }
    }

    /// 진행 중인 판이 있으면 확인을 받고 새 게임을 시작한다.
    func requestNewGame(seed: Int? = nil) {
        if preparingDeal { return }
        requestDiscard(title: "새 게임",
                       message: "진행 중인 판을 버리고 새 게임을 시작할까요?\n현재 판은 이어하기 기록에서 지워집니다.",
                       confirmTitle: "새 게임") { [weak self] in self?.newGame(seed: seed) }
    }

    func requestRestartGame() {
        if preparingDeal { return }
        requestDiscard(title: "같은 판 다시 시작",
                       message: "지금까지 둔 수를 모두 되돌리고 같은 판을 처음부터 시작할까요?",
                       confirmTitle: "다시 시작") { [weak self] in self?.restartGame() }
    }

    func requestSwitchGame(_ kind: GameKind, suits: Int? = nil) {
        if preparingDeal { return }
        guard kind != variant || suits != nil else {
            requestNewGame()
            return
        }
        requestDiscard(title: "\(kind.nameKo)로 바꾸기",
                       message: "진행 중인 \(gameLabel) 판을 버리고 \(kind.nameKo)를 시작할까요?",
                       confirmTitle: "바꾸기") { [weak self] in
            self?.switchGame(kind, suits: suits)
        }
    }

    private func requestDiscard(title: String, message: String, confirmTitle: String,
                                action: @escaping () -> Void) {
        if !busy && game.moves > 0 && !game.isWon() {
            confirm = ConfirmRequest(title: title, message: message,
                                     confirmTitle: confirmTitle, action: action)
        } else {
            action()
        }
    }

    func resetRound() {
        resetRoundUI()
        elapsedBase = 0
        startTS = nil
        playedCounted = false
        saveCurrentGame()
        redraw()
        updateStatus()
    }

    /// 판을 바꾼 뒤 화면·입력 상태만 초기화한다(시간·저장은 호출자가 정한다).
    private func resetRoundUI() {
        drag = nil
        dropTarget = nil
        pressActive = false
        lastClick = (nil, .distantPast)
        busy = false
        autocompleting = false
        if hintSearching { cancelHintSearch() }
        zoomPct = fitZoom(preferredZoomPct)
        updateWindowTitle()
    }

    // ── 진행 중인 판 저장/이어하기 ───────────────────────────────────────
    /// 현재 판을 설정·전적 파일에 저장한다(매 수 뒤 자동 호출).
    func saveCurrentGame() {
        // 풀리는 판을 만드는 중에는 일반 배분을 저장하지 않는다.
        guard !preparingDeal else { return }
        guard !game.isWon() else {
            stats.removeValue(forKey: "current")
            save()
            return
        }
        let kind = variant
        let saved = SavedGame(
            variant: kind.rawValue,
            snapshot: game.exportSnapshot(),
            elapsed: elapsedSeconds(),
            playedCounted: playedCounted,
            drawCount: kind == .klondike ? drawCount : nil,
            spiderSuits: kind == .spider ? spiderSuits : nil,
            spiderGroup: kind == .spider ? spiderGroup : nil,
            spiderStart: kind == .spider ? (game as? Spider)?.startLayout : nil)
        do {
            let data = try JSONEncoder().encode(saved)
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                stats["current"] = object
            }
        } catch {
            Logger.shared.error("저장", "진행 중인 판 인코딩 실패: \(error.localizedDescription)",
                                code: "E-MACOS-GAME-0002")
            return
        }
        save()
    }

    private func applySavedGame(_ saved: SavedGame) {
        let kind = GameKind(rawValue: saved.variant) ?? .klondike
        variant = kind
        settings["variant"] = kind.rawValue
        if let drawCount = saved.drawCount { settings["draw_count"] = drawCount }
        if let suits = saved.spiderSuits { settings["spider_suits"] = suits }
        if let group = saved.spiderGroup { settings["spider_group"] = group }

        game = GameController.makeGameObject(kind: kind, settings: settings,
                                             seed: saved.snapshot.seed)
        if let drawCount = saved.drawCount {
            (game as? Klondike)?.setDrawCount(drawCount)
        }
        if let spider = game as? Spider {
            spider.setSuitFree((saved.spiderGroup ?? spiderGroup) == "any_suit")
        }
        game.restoreSnapshot(saved.snapshot)
        if let spider = game as? Spider, let start = saved.spiderStart {
            spider.setStartLayout(start)
        }
        elapsedBase = max(0, saved.elapsed)
        startTS = (game.moves > 0 && !game.isWon()) ? Date() : nil
        playedCounted = saved.playedCounted
        resetRoundUI()
        // 복원 직후에는 저장하지 않는다(읽은 그대로 유지).
        redraw()
        updateStatus()
    }

    /// 실제로 첫 수를 둔 뒤에만 "판 수"를 센다(앱 실행만으로는 늘지 않는다).
    private func markPlayedIfNeeded() {
        guard !playedCounted else { return }
        playedCounted = true
        if var games = stats["games"] as? [String: Any],
           var record = games[variant.rawValue] as? [String: Any] {
            record["played"] = ((record["played"] as? Int) ?? 0) + 1
            games[variant.rawValue] = record
            stats["games"] = games
            statsRevision &+= 1
        }
    }

    // ── 조작 ──────────────────────────────────────────────────────────────
    func undo() {
        if busy { return }
        clearFlights()
        autocompleting = false
        autocompleteTimer?.invalidate()
        if game.undo() {
            playSound("Tink")
            redraw()
            updateStatus()
            saveCurrentGame()
        } else {
            playSound("Funk")
        }
    }

    func redo() {
        if busy { return }
        clearFlights()
        autocompleting = false
        autocompleteTimer?.invalidate()
        if game.redo() {
            playSound("Tink")
            redraw()
            afterMove()
        } else {
            playSound("Funk")
        }
    }

    func clickStock() {
        if busy { return }
        if !game.hasStock {
            playSound("Funk")
            return
        }
        startTimer()
        let res = game.drawFromStock()
        if !res.ok {
            Logger.shared.info("카드넘기기", "넘길 카드 없음: \(res.reason ?? "")")
            if let reason = res.reason { setHint(reason) }
            playSound("Funk")
            return
        }
        switch res.action {
        case "recycle":
            Logger.shared.info("카드넘기기", "웨이스트 재활용 \(res.count)장(점수 \(res.points))")
        case "deal":
            Logger.shared.info("카드넘기기", "스톡에서 열마다 한 장씩 \(res.count)장(점수 \(res.points))")
        default:
            Logger.shared.info("카드넘기기", "스톡에서 \(res.count)장 넘김")
        }
        playSound("Pop")
        redraw()
        afterMove()
        if res.sets > 0 {
            setHint("세트 완성! \(game.foundations.count)/\(game.foundationsCount)")
        }
    }

    func press(at point: CGPoint) {
        if busy {
            stopBounce()
            return
        }
        flightTimer?.invalidate()
        flightTimer = nil
        flights = []
        pressActive = true
        pressTime = Date()
        let hit = hitTest(game, layout, at: point)
        pressHit = hit
        drag = nil
        guard let hit, hit.kind != .stock, let card = hit.card, card.faceup else { return }
        guard let run = game.pick(hit.ref, index: hit.index), !run.isEmpty else {
            if let note = game.groupLimitNote(hit.ref, index: hit.index) {
                setHint(note, seconds: 4.0)          // 왜 못 집는지 알려 준다
            } else {
                playSound("Funk")
            }
            return
        }
        if run.count > 1 {
            setHint("묶음 \(run.count)장", seconds: 1.5)
        }
        var origin: [ObjectIdentifier: CGPoint] = [:]
        for card in run {
            if let spot = layout.point(card) { origin[ObjectIdentifier(card)] = spot }
        }
        drag = DragState(cards: run, src: hit.ref, index: hit.index, start: point, last: point,
                         origin: origin, moved: false, delta: .zero)
        revision &+= 1
    }

    func dragTo(_ point: CGPoint) {
        guard var state = drag else { return }
        let dx = point.x - state.last.x, dy = point.y - state.last.y
        if dx == 0 && dy == 0 { return }
        state.last = point
        if !state.moved {
            state.moved = abs(point.x - state.start.x) + abs(point.y - state.start.y) > 4
        }
        state.delta = CGSize(width: state.delta.width + dx, height: state.delta.height + dy)
        drag = state
        if state.moved {
            updateDropHighlight()
        } else {
            revision &+= 1
        }
    }

    /// 지금 놓으면 되는 더미(규칙에 맞을 때만).
    func dropTargetRef() -> Ref? {
        guard let drag, let top = drag.cards.first, let origin = drag.origin[ObjectIdentifier(top)]
        else { return nil }
        let rect = cardRect(CGPoint(x: origin.x + drag.delta.width, y: origin.y + drag.delta.height))
        var best: Ref?
        var bestArea: CGFloat = 0
        for (ref, spot) in layout.slots where ref.kind != .stock && ref.kind != .waste {
            let area = rectOverlap(rect, cardRect(spot))
            if area > bestArea {
                best = ref
                bestArea = area
            }
        }
        guard let best, bestArea >= 0.30 * Metrics.cardW * Metrics.cardH else { return nil }
        return game.canDrop(drag.cards, best) ? best : nil
    }

    private func updateDropHighlight() {
        dropTarget = dropTargetRef()
        revision &+= 1
    }

    func release(at point: CGPoint) {
        pressActive = false
        if busy { return }
        guard let state = drag else {
            handleClick(pressHit)
            return
        }
        if !state.moved && Date().timeIntervalSince(pressTime) < 0.6 {
            drag = nil
            dropTarget = nil
            revision &+= 1
            handleClick(pressHit)
            return
        }
        if let dst = dropTargetRef() {
            let res = game.move(state.src, index: state.index, dst)
            if res.ok {
                drag = nil
                dropTarget = nil
                playSound(res.flipped ? "Pop" : "Tink")
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                // 직접 끌어 옮긴 카드는 손가락을 따라 이미 목적지에 있다.
                // 여기서 비행 연출을 시작하면 원래 자리에서 다시 날아가는 것처럼 보인다.
                redraw()
                afterMove()
                return
            }
        }
        playSound("Funk")
        snapBack()
    }

    /// 놓을 수 없는 위치에서 손을 뗐을 때 제자리로 되돌린다.
    private func snapBack() {
        guard let state = drag else {
            drag = nil
            dropTarget = nil
            redraw()
            return
        }
        if !animationsOn {
            drag = nil
            dropTarget = nil
            redraw()
            return
        }
        let steps = 6
        var step = 0
        func advance() {
            step += 1
            guard var current = drag else { return }
            let factor = CGFloat(steps - step) / CGFloat(steps)
            current.delta = CGSize(width: state.delta.width * factor,
                                   height: state.delta.height * factor)
            drag = current
            revision &+= 1
            if step < steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.014) { advance() }
            } else {
                drag = nil
                dropTarget = nil
                redraw()
            }
        }
        advance()
    }

    /// 드래그 없이 눌렀다 뗀 경우: 스톡 넘기기, 카드 공개, 더블클릭 자동 이동.
    private func handleClick(_ hit: Hit?) {
        guard let hit else { return }
        if hit.kind == .stock {
            lastClick = (nil, .distantPast)
            clickStock()
            return
        }
        guard let card = hit.card else { return }
        let key = card.uid
        let now = Date()
        let double = lastClick.key == key && now.timeIntervalSince(lastClick.time) < 0.45
        lastClick = (key, now)

        if !card.faceup {
            if double { return }
            if game.flipTop(hit.ref) {
                playSound("Pop")
                redraw()
                afterMove()
            }
            return
        }
        if double {
            lastClick = (nil, .distantPast)
            if autoOn(.double) {
                tryAutoMove(hit)
            } else {
                setHint("더블클릭 자동 이동이 꺼져 있습니다 (게임 → 자동 기능)")
            }
        }
    }

    private func tryAutoMove(_ hit: Hit) {
        let run = game.pick(hit.ref, index: hit.index) ?? []
        var origins: [ObjectIdentifier: CGPoint] = [:]
        for card in run {
            if let spot = layout.point(card) { origins[ObjectIdentifier(card)] = spot }
        }
        if let res = game.autoMove(hit.ref, index: hit.index), res.ok {
            playSound(res.flipped ? "Pop" : "Tink")
            redraw()
            afterMove()
            beginFlights(run, origins: origins)
        } else {
            playSound("Funk")
        }
    }

    /// 이동 뒤 공통 처리: 타이머·자동 올리기·자동 완성·승리 확인.
    func afterMove() {
        if hintSearching { cancelHintSearch() }
        startTimer()
        markPlayedIfNeeded()
        if autoOn(.collect) && !game.foundations.isEmpty {
            if autoCollectFoundations() > 0 { redraw() }
        }
        updateStatus()
        if game.isWon() {
            onWin()
            return
        }
        saveCurrentGame()
        if autoOn(.finish) && game.canAutoComplete() {
            maybeAutoFinish()
        }
        // 둘 수 있는 수가 하나도 없으면 상태줄에서 바로 알려 준다.
        if !busy, game.hint() == nil {
            setHint("둘 수 있는 수가 없습니다. ⌘Z로 되돌리거나 ⌘N으로 새 게임을 시작하세요.",
                    seconds: 6)
        }
    }

    /// 파운데이션에 올릴 수 있는 카드를 자동으로 올린다(옮긴 장수 반환).
    @discardableResult
    func autoCollectFoundations(limit: Int = 60) -> Int {
        var moved = 0
        while moved < limit {
            guard let found = game.findFoundationMove() else { break }
            if !game.move(found.src, index: found.index, found.dst).ok { break }
            moved += 1
        }
        if moved > 0 {
            Logger.shared.info("자동", "파운데이션 자동 올리기 \(moved)장")
        }
        return moved
    }

    private func maybeAutoFinish() {
        if busy || autocompleting { return }
        guard autoOn(.finish), game.canAutoComplete() else { return }
        setHint("자동 완성을 시작합니다")
        Logger.shared.info("자동", "게임 끝 → 자동 완성 시작")
        startAutoComplete()
    }

    // ── 힌트 ──────────────────────────────────────────────────────────────
    /// 이기는 해답을 찾아 첫 수를 보여 준다.
    ///
    /// 예전 힌트는 "지금 둘 수 있는 한 수"를 점수로만 골라 A→B, B→A 같은
    /// 왕복 수를 계속 권했다. 지금은 판 전체를 탐색해 이기는 줄의 첫 수만
    /// 보여 주고, 풀 수 없음(증명)과 판단 불가(시간 초과)를 구분해 알린다.
    func showHint() {
        if busy || preparingDeal || hintSearching { return }
        // 풀리는 스파이더 판은 배분할 때 찾아 둔 해답이 있어 바로 안내한다.
        if let spider = game as? Spider, let planned = spider.planHint() {
            presentHint(planned, solvedCount: nil, planned: true)
            return
        }
        let snapshot = game.exportSnapshot()
        let kind = variant
        let drawCount = (game as? Klondike)?.drawCount ?? 3
        let suits = (game as? Spider)?.suits ?? 1
        let suitFree = (game as? Spider)?.suitFree ?? false
        let budget = HintSolver.budget(for: kind)
        hintSearching = true
        setHint("이기는 해답을 찾는 중…", seconds: 30)
        Logger.shared.info("힌트", "탐색 시작(\(kind.rawValue), \(budget.time)초)")
        let token = UUID()
        hintSearchToken = token
        Task.detached(priority: .userInitiated) {
            let result = HintSolver.solve(kind: kind, snapshot: snapshot,
                                          drawCount: drawCount, suits: suits,
                                          suitFree: suitFree,
                                          timeLimit: budget.time,
                                          nodeLimit: budget.nodes)
            await MainActor.run { [weak self] in
                self?.finishHintSearch(result, snapshot: snapshot, token: token)
            }
        }
    }

    /// 판이 바뀌면 진행 중인 힌트 탐색 결과를 버린다.
    private func cancelHintSearch() {
        hintSearchToken = UUID()
        hintSearching = false
        restoreHint()
    }

    private func finishHintSearch(_ result: HintSearchResult, snapshot: GameSnapshot,
                                  token: UUID) {
        guard token == hintSearchToken else { return }
        hintSearching = false
        // 탐색하는 동안 판이 바뀌었으면 결과를 버린다(다른 판에 힌트를 주지 않는다).
        guard !busy, game.exportSnapshot() == snapshot else {
            restoreHint()
            return
        }
        switch result {
        case .solved(let line):
            guard let hint = line.first else { restoreHint(); return }
            presentHint(hint, solvedCount: line.count, planned: false)
        case .impossible:
            restoreHint()
            Logger.shared.info("힌트", "이길 수 없는 판으로 판정")
            alert = AlertInfo(title: "힌트",
                              message: "이 판은 지금 상태에서 더는 이길 수 없습니다.\n"
                                + "되돌리기(⌘Z)로 이전 수를 취소하거나 새 게임을 시작하세요.",
                              primaryTitle: "닫기",
                              secondaryTitle: "새 게임",
                              secondaryAction: { [weak self] in self?.requestNewGame() })
        case .unknown:
            restoreHint()
            Logger.shared.info("힌트", "시간 안에 해답을 찾지 못함")
            alert = AlertInfo(title: "힌트",
                              message: "제한 시간 안에 확실한 해답을 찾지 못했습니다.\n"
                                + "이 판이 풀린다고 단정할 수 없어 아무 수도 권하지 않습니다.\n"
                                + "되돌리기(⌘Z)로 이전 수를 취소하거나 새 게임을 시작해 보세요.",
                              primaryTitle: "닫기",
                              secondaryTitle: "새 게임",
                              secondaryAction: { [weak self] in self?.requestNewGame() })
        }
    }

    private func presentHint(_ hint: Hint, solvedCount: Int?, planned: Bool) {
        switch hint {
        case .draw, .recycle:
            let text = hint == .draw
                ? (variant == .spider ? "스톡을 클릭하면 열마다 한 장씩 돌립니다."
                                      : "스톡을 클릭하면 카드를 넘깁니다.")
                : "스톡이 비었습니다. 클릭하면 웨이스트를 다시 씁니다."
            flash(slots: [Ref(.stock, 0)])
            setHint(text)
            Logger.shared.info("힌트", text)
        case .move(let src, let index, let dst):
            let cards = game.pick(src, index: index) ?? []
            flash(cards: cards, slots: [dst])
            let label: String
            if planned {
                label = "해답의 다음 수입니다"
            } else if let count = solvedCount, count > 1 {
                label = "이기는 해답 \(count)수 중 첫 수입니다"
            } else {
                label = "이기는 수를 찾았습니다"
            }
            setHint(label, seconds: 5)
            Logger.shared.info("힌트", "\(src.kind.rawValue) \(src.index) → \(dst.kind.rawValue) \(dst.index)")
        }
    }

    private func flash(cards: [Card] = [], slots: [Ref] = []) {
        flashTimer?.invalidate()
        flashCards = Set(cards.map { ObjectIdentifier($0) })
        flashSlots = slots
        flashOn = true
        var remaining = 6
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { return }
                remaining -= 1
                self.flashOn.toggle()
                self.revision &+= 1
                if remaining <= 0 {
                    timer.invalidate()
                    self.flashTimer = nil
                    self.flashCards = []
                    self.flashSlots = []
                    self.revision &+= 1
                }
            }
        }
    }

    // ── 자동 완성 ─────────────────────────────────────────────────────────
    func startAutoComplete() {
        if busy { return }
        if !game.canAutoComplete() {
            playSound("Funk")
            let why: String
            switch variant {
            case .spider:
                why = "스파이더는 자동 완성을 쓰지 않습니다.\n같은 무늬 K→A 13장을 모으면 세트가 저절로 빠집니다."
            case .freecell:
                why = "프리셀을 모두 비우고 열을 내림차순으로 정리해야 자동 완성을 쓸 수 있습니다."
            default:
                why = "뒤집힌 카드가 남아 있어 자동 완성을 쓸 수 없습니다.\n모든 카드가 공개되면 사용할 수 있습니다."
            }
            alert = AlertInfo(title: "자동 완성", message: why)
            return
        }
        autocompleting = true
        Logger.shared.info("자동완성", "시작(남은 카드 정리)")
        stepAutoComplete()
    }

    private func stepAutoComplete() {
        if !autocompleting || busy {
            autocompleting = false
            return
        }
        if game.autocompleteStep() == nil {
            autocompleting = false
            Logger.shared.info("자동완성", "끝(더 옮길 카드 없음)")
            updateStatus()
            playSound("Funk")
            return
        }
        redraw()
        updateStatus()
        if game.isWon() {
            autocompleting = false
            onWin()
            return
        }
        autocompleteTimer = Timer.scheduledTimer(withTimeInterval: 0.11, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stepAutoComplete() }
        }
    }

    // ── 우승 ──────────────────────────────────────────────────────────────
    func onWin() {
        if busy { return }
        busy = true
        autocompleting = false
        markPlayedIfNeeded()
        playSound("Glass")
        let seconds = max(1, elapsedSeconds())
        let bonus = winBonus(seconds: Double(seconds))
        let final = game.score + bonus
        elapsedBase = seconds
        startTS = nil

        if var games = stats["games"] as? [String: Any],
           var record = games[variant.rawValue] as? [String: Any] {
            record["won"] = ((record["won"] as? Int) ?? 0) + 1
            var newRecord = false
            if let best = record["best_time"] as? Int {
                if seconds < best { record["best_time"] = seconds }
            } else {
                record["best_time"] = seconds
            }
            if let bestScore = record["best_score"] as? Int {
                if final > bestScore {
                    record["best_score"] = final
                    newRecord = true
                }
            } else {
                record["best_score"] = final
                newRecord = true
            }
            games[variant.rawValue] = record
            stats["games"] = games
            stats.removeValue(forKey: "current")
            statsRevision &+= 1
            save()
            updateStatus()
            Logger.shared.info("우승", "\(gameLabel) 최종 점수 \(final)(시간 \(seconds)초·보너스 \(bonus)"
                               + (newRecord ? "·신기록" : "") + ")")
        }

        let minutes = seconds / 60, sec = seconds % 60
        var body: String
        if variant == .freecell {
            body = String(format: "걸린 시간: %d분 %02d초\n이동 횟수: %d\n최종 점수: %d%@\n\n확인을 누르면 카드가 쏟아집니다.",
                          minutes, sec, game.moves, final, newRecordText())
        } else {
            body = String(format: "걸린 시간: %d분 %02d초\n이동 횟수: %d\n점수: %d\n시간 보너스: %d\n최종 점수: %d%@\n\n확인을 누르면 카드가 쏟아집니다.",
                          minutes, sec, game.moves, game.score, bonus, final, newRecordText())
        }
        alert = AlertInfo(title: "우승",
                          message: "축하합니다! \(gameLabel)를 모두 정리했습니다.\n\n" + body,
                          primaryTitle: "카드 쏟아지기",
                          onDismiss: { [weak self] in self?.startBounce() },
                          secondaryTitle: "새 게임",
                          secondaryAction: { [weak self] in self?.requestNewGame() })
    }

    private var newRecordMark = false

    private func newRecordText() -> String {
        // 신기록 표시는 방금 갱신했는지로 판단한다(문구는 파이썬과 동일).
        let record = (stats["games"] as? [String: Any])?[variant.rawValue] as? [String: Any]
        let best = record?["best_score"] as? Int
        return (best != nil && best == game.score + winBonus(seconds: Double(max(1, elapsedSeconds()))))
            ? "  (신기록!)" : ""
    }

    // ── 우승 연출(카드 쏟아지기) ───────────────────────────────────────────
    func startBounce() {
        cleanupBounce()
        if !animationsOn {
            finishBounce()
            return
        }
        bounceQueue = []
        for (fi, pile) in game.foundations.enumerated() {
            for card in pile { bounceQueue.append((card, Ref(.foundation, fi))) }
        }
        bounceTicks = 0
        bounceTimer = Timer.scheduledTimer(withTimeInterval: 0.045, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bounceTick() }
        }
    }

    private func bounceTick() {
        let width = max(windowWidth, Metrics.windowWidth(columns: game.columns))
        let height = Metrics.windowH - Metrics.statusH

        if !bounceQueue.isEmpty && bounceTicks % 2 == 0 {
            let (card, ref) = bounceQueue.removeFirst()
            if let spot = layout.slot(ref.kind, ref.index) {
                bounceCards.append(BounceCard(
                    card: card, x: spot.x, y: spot.y,
                    vx: Bool.random() ? CGFloat.random(in: 3.5...8.0) : -CGFloat.random(in: 3.5...8.0),
                    vy: -CGFloat.random(in: 7.0...12.0)))
            }
        }

        for index in bounceCards.indices {
            bounceCards[index].vy += 0.55
            bounceCards[index].x += bounceCards[index].vx
            bounceCards[index].y += bounceCards[index].vy
            if bounceCards[index].y > height - Metrics.cardH {
                bounceCards[index].y = height - Metrics.cardH
                bounceCards[index].vy = -abs(bounceCards[index].vy) * 0.78
            }
        }
        bounceCards.removeAll { $0.x < -Metrics.cardW - 30 || $0.x > width + 30 }

        bounceTicks += 1
        revision &+= 1
        if bounceCards.isEmpty && bounceQueue.isEmpty {
            finishBounce()
        }
    }

    func finishBounce() {
        bounceTimer?.invalidate()
        bounceTimer = nil
        if bounceTicks > 0 {
            Logger.shared.perf("애니메이션", "카드 쏟아지기 \(bounceTicks)프레임(카드 \(game.sortedCards())장)")
        }
        cleanupBounce()
        busy = false
        redraw()
        updateStatus()
    }

    func stopBounce() {
        if !busy { return }
        finishBounce()
    }

    private func cleanupBounce() {
        bounceTimer?.invalidate()
        bounceTimer = nil
        bounceCards = []
        bounceQueue = []
    }

    var bounceTicksCount: Int { bounceTicks }

    /// 새 게임/다시 시작 전에 진행 중인 애니메이션을 정리한다.
    func cancelAnimations() {
        autocompleting = false
        autocompleteTimer?.invalidate()
        autocompleteTimer = nil
        hintTimer?.invalidate()
        hintTimer = nil
        if hintText != hintTextDefault {
            hintText = hintTextDefault
        }
        cleanupBounce()
        flashTimer?.invalidate()
        flashTimer = nil
        flashCards = []
        flashSlots = []
        flightTimer?.invalidate()
        flightTimer = nil
        flights = []
        busy = false
        drag = nil
        dropTarget = nil
        pressActive = false
    }

    // ── 테마·자동 기능·난이도 ─────────────────────────────────────────────
    func setTheme(background: String? = nil, back: String? = nil) {
        var theme = GameController.dict(settings["theme"])
        if let background, tableThemes[background] != nil { theme["background"] = background }
        if let back, backThemes[back] != nil { theme["back"] = back }
        settings["theme"] = theme
        save()
        redraw()
        let bgTitle = tableThemes[backgroundKey]?.title ?? ""
        let backTitle = backThemes[backKey]?.title ?? ""
        Logger.shared.info("테마", "배경 \(bgTitle) · 카드 뒷면 \(backTitle)")
        if let background { setHint("배경 \(tableThemes[background]?.title ?? "")") }
        if let back { setHint("카드 뒷면 \(backThemes[back]?.title ?? "")") }
    }

    func setAuto(_ feature: AutoFeature, on: Bool) {
        var auto = GameController.dict(settings["auto"])
        auto[feature.rawValue] = on
        settings["auto"] = auto
        save()
        let state = AutoFeature.allCases.map {
            "\($0.title) \(autoOn($0) ? "켬" : "끔")"
        }.joined(separator: ", ")
        Logger.shared.info("자동", state)
        setHint(state)
        revision &+= 1
    }

    func toggleAutoAll() {
        let on = !autoAllOn()
        var auto: [String: Any] = [:]
        for feature in AutoFeature.allCases { auto[feature.rawValue] = on }
        settings["auto"] = auto
        save()
        Logger.shared.info("자동", "자동 기능 \(on ? "모두 켬" : "모두 끔")(단축키)")
        setHint("자동 기능 \(on ? "켬" : "끔")")
        revision &+= 1
    }

    func setSound(on: Bool) {
        settings["sound"] = on
        save()
        if on { playSound("Tink") }
        setHint("효과음 \(on ? "켬" : "끔")")
        revision &+= 1
    }

    func setAnimations(on: Bool) {
        settings["animations"] = on
        save()
        setHint("애니메이션 \(on ? "켬" : "끔")")
        revision &+= 1
    }

    // ── 배경음 설정 ───────────────────────────────────────────────────────
    private func setMusicSetting(_ key: String, _ value: Any) {
        var music = musicSettings
        music[key] = value
        settings["music"] = music
    }

    /// 설정값을 재생기에 반영하고, 실패하면 상태바에 알린다.
    private func applyMusicSettings() {
        music.apply(on: musicOn, trackID: musicTrackID,
                    repeatMode: musicRepeatMode, volume: musicVolume)
        if let code = music.lastErrorCode { notify(code, seconds: 8) }
    }

    func setMusic(on: Bool) {
        setMusicSetting("on", on)
        save()
        applyMusicSettings()
        Logger.shared.info("음악", "배경음 \(on ? "켬" : "끔")")
        setHint("배경음 \(on ? "켬" : "끔")")
        revision &+= 1
    }

    func setMusicTrack(_ id: String) {
        guard musicTracks.contains(where: { $0.id == id }), id != musicTrackID else { return }
        setMusicSetting("track", id)
        save()
        applyMusicSettings()
        Logger.shared.info("음악", "곡 선택 \(musicTrack.title)")
        setHint("배경음: \(musicTrack.title)")
        revision &+= 1
    }

    func setMusicRepeat(_ mode: MusicRepeatMode) {
        guard mode != musicRepeatMode else { return }
        setMusicSetting("repeat", mode.rawValue)
        save()
        applyMusicSettings()
        Logger.shared.info("음악", "반복 \(mode.title)")
        setHint("배경음 반복: \(mode.title)")
        revision &+= 1
    }

    /// 볼륨은 드래그 중 자주 바뀌므로 저장은 손을 뗄 때만 한다.
    func setMusicVolume(_ value: Double, save persist: Bool = true) {
        let clamped = min(1, max(0, value))
        setMusicSetting("volume", clamped)
        music.setVolume(clamped)
        if persist {
            save()
            revision &+= 1
        }
    }

    /// 목록 반복으로 다음 곡이 시작되면 선택값도 따라간다(다시 재생하지 않는다).
    func musicDidAdvance(to id: String) {
        guard musicTracks.contains(where: { $0.id == id }) else { return }
        setMusicSetting("track", id)
        save()
        revision &+= 1
    }

    func setDrawCount(_ count: Int) {
        guard variant == .klondike else { return }
        settings["draw_count"] = (count == 1 ? 1 : 3)
        (game as? Klondike)?.setDrawCount(count)
        saveCurrentGame()
        redraw()
        updateStatus()
        revision &+= 1
    }

    func setSpiderSuits(_ suits: Int) {
        guard variant == .spider else { return }
        settings["spider_suits"] = suits
        switchGame(.spider, suits: suits)
    }

    func setSpiderGroup(_ key: String) {
        let group = spiderGroups[key] != nil ? key : defaultSpiderGroup
        settings["spider_group"] = group
        save()
        if variant == .spider {
            (game as? Spider)?.setSuitFree(group == "any_suit")
            saveCurrentGame()
            redraw()
        }
        Logger.shared.info("게임", "스파이더 묶음 이동 설정: \(spiderGroups[group] ?? "")")
        setHint("묶음 이동: \(spiderGroups[group] ?? "")")
        revision &+= 1
    }

    /// 스파이더 새 판을 항상 풀리는 판으로 만들지 정한다.
    func setSpiderWinnable(_ on: Bool) {
        settings["spider_winnable"] = on
        save()
        Logger.shared.info("게임", "스파이더 풀리는 판만: \(on ? "켬" : "끔")")
        if variant == .spider {
            if on {
                // 지금 판이 풀리는 판이 아닐 수 있으므로 새로 만든다(진행 중이면 확인).
                requestNewGame()
            } else {
                setHint("풀리는 판 보장을 껐습니다")
            }
        } else {
            setHint("스파이더 풀리는 판만: \(on ? "켬" : "끔")")
        }
        revision &+= 1
    }

    // ── 통계/도움말 문구 ──────────────────────────────────────────────────
    func record(for kind: GameKind) -> GameRecord {
        let record = (stats["games"] as? [String: Any])?[kind.rawValue] as? [String: Any] ?? [:]
        return GameRecord(kind: kind,
                          played: (record["played"] as? Int) ?? 0,
                          won: (record["won"] as? Int) ?? 0,
                          bestTime: record["best_time"] as? Int,
                          bestScore: record["best_score"] as? Int)
    }

    var allRecords: [GameRecord] { GameKind.allCases.map { record(for: $0) } }

    func resetStats() {
        stats["games"] = GameController.defaultStats()["games"]
        statsRevision &+= 1
        save()
        Logger.shared.info("전적", "게임별 전적 초기화")
        setHint("전적을 초기화했습니다")
    }

    func statsText() -> String {
        var lines: [String] = []
        for record in allRecords {
            let mark = record.kind == variant ? "▶ " : "   "
            let bestTime = record.bestTime.map { "\($0)초" } ?? "-"
            let bestScore = record.bestScore.map { "\($0)점" } ?? "-"
            lines.append(String(format: "%@%@ : %d판 · %d승 (%.1f%%) · 최고 %@ · 최고 %@",
                                mark, record.kind.nameKo, record.played, record.won,
                                record.rate, bestTime, bestScore))
        }
        let suits = (settings["spider_suits"] as? Int) ?? 1
        let path = GameController.statsPath.replacingOccurrences(
            of: NSHomeDirectory(), with: "~")
        return "게임별 전적(▶ = 지금 하는 게임)\n\n\(lines.joined(separator: "\n"))\n\n스파이더 난이도: \(suits)무늬\n저장 위치: \(path)"
    }

    func showStats() {
        statsRevision &+= 1
    }

    // ── 판 번호 ───────────────────────────────────────────────────────────
    func copySeed() {
        let text = "\(game.seed)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        setHint("판 번호 \(text)를 복사했습니다")
        Logger.shared.info("게임", "판 번호 복사: \(text)")
    }

    func startGame(withSeedText text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seed = Int(trimmed) else {
            alert = AlertInfo(title: "판 번호", message: "숫자로 된 판 번호를 입력하세요.")
            return
        }
        showSeedEntry = false
        requestNewGame(seed: seed)
    }

    func showHelp() {
        alert = AlertInfo(title: "사용 방법 — \(variant.nameKo)", message: MessageText.help(variant))
    }

    func showAbout() {
        alert = AlertInfo(title: "정보",
                          message: MessageText.about(variant)
                            + "\n\n현재 판 번호: \(game.seed)\n확대: \(zoomPct)%")
    }

    func showDebugPanelToggle() {
        showDebugPanel.toggle()
    }

    // ── 키 입력(파이썬과 같은 단축키) ─────────────────────────────────────
    /// true를 돌려주면 이 키를 소비한다(메뉴 단축키에 넘기지 않는다).
    func handleKey(characters: String?, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        // 알림·확인 창이 떠 있으면 게임 단축키가 뒤에서 실행되지 않게 한다.
        if alert != nil || confirm != nil || showSeedEntry { return false }
        if modifiers == .control, characters?.lowercased() == "z" {    // Ctrl+Z
            undo()
            return true
        }
        if modifiers == [.control, .shift], characters?.lowercased() == "z" {   // Ctrl+Shift+Z
            redo()
            return true
        }
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return false
        }
        let key = characters?.lowercased() ?? ""
        switch keyCode {
        case 120:                        // F2
            requestNewGame()
            return true
        case 122:                        // F1
            showHelp()
            return true
        default:
            break
        }
        switch key {
        case "n": requestNewGame()
        case "r": requestRestartGame()
        case "u": undo()
        case " ": clickStock()
        case "d" where variant == .klondike: setDrawCount(((game as? Klondike)?.drawCount ?? 3) == 1 ? 3 : 1)
        case "h": showHint()
        case "a": startAutoComplete()
        case "?": showHelp()
        case "\u{1b}" where busy: stopBounce()
        default: return false
        }
        return true
    }

    // ── 디버그 패널용 수치 ────────────────────────────────────────────────
    var cardsInPlay: Int { game.totalCards }
    var redrawCountInWindow: Int { revision }

    func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size
                                           / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / (1024 * 1024) : 0
    }
}
