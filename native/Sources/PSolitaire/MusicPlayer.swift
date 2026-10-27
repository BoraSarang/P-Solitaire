// MusicPlayer.swift — 배경음(무료 음악 5곡) 재생과 목록 반복.
//
// 음악: Kevin MacLeod (incompetech.com) · CC BY 4.0.
// 원본 mp3 를 96kbps AAC(m4a)로 변환해 번들 크기를 줄였다(자세한 출처는 Resources/Music/CREDITS.md).

import Foundation
import AVFoundation
import Combine

// MARK: - 음악 목록

struct MusicTrack: Identifiable, Equatable {
    let id: String
    let title: String
    /// 설정 화면에 보여 줄 한 줄 설명(분위기·악기).
    let detail: String
    /// 번들 안의 파일 이름(Contents/Resources/Music 아래).
    let file: String
}

/// 재생 순서 = 아래 순서. 다섯 곡 모두 차분한 재즈·라운지 계열이다.
let musicTracks: [MusicTrack] = [
    MusicTrack(id: "lobby_time", title: "Lobby Time",
               detail: "라운지 재즈 · 바이브라폰", file: "Lobby Time.m4a"),
    MusicTrack(id: "backbay_lounge", title: "Backbay Lounge",
               detail: "부드러운 재즈 · 피아노", file: "Backbay Lounge.m4a"),
    MusicTrack(id: "bossa_bossa", title: "BossaBossa",
               detail: "보사노바 · 기타", file: "BossaBossa.m4a"),
    MusicTrack(id: "night_in_venice", title: "Night in Venice",
               detail: "나이트 재즈 · 색소폰", file: "Night in Venice.m4a"),
    MusicTrack(id: "late_night_radio", title: "Late Night Radio",
               detail: "일렉트릭 피아노 · 나른한 밤", file: "Late Night Radio.m4a"),
]

enum MusicRepeatMode: String, CaseIterable, Identifiable {
    case off
    case one
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "반복 안 함"
        case .one: return "한 곡 반복"
        case .all: return "목록 반복"
        }
    }
}

enum MusicDefaults {
    static let on = true
    static let trackID = musicTracks[0].id
    static let repeatMode = MusicRepeatMode.all
    static let volume: Double = 0.35
}

// MARK: - 재생기

/// 배경음 하나만 재생한다. 설정 저장은 GameController 가 맡고, 여기서는 재생만 한다.
@MainActor
final class MusicPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var playingTrackID: String?
    @Published private(set) var lastErrorCode: String?

    /// 목록 반복으로 다음 곡이 시작될 때 GameController 가 선택값을 따라가게 한다.
    var onTrackChanged: ((String) -> Void)?
    /// 재생 실패를 상태바에 알린다.
    var onError: ((String) -> Void)?

    private var player: AVAudioPlayer?
    private var playingFile: String?
    private var enabled = false
    private var trackID = MusicDefaults.trackID
    private var repeatMode = MusicDefaults.repeatMode
    private var volume = MusicDefaults.volume

    /// 창 없는 검사(자체 검사·PNG 렌더)에서는 소리를 내지 않는다.
    static var isSuppressed: Bool {
        CommandLine.arguments.contains { $0 == "--selftest" || $0 == "--shots" }
    }

    var selectedTrack: MusicTrack {
        musicTracks.first { $0.id == trackID } ?? musicTracks[0]
    }

    /// 설정값을 반영한다. 곡이 바뀌면 새로 재생하고, 같으면 볼륨·반복만 갱신한다.
    func apply(on: Bool, trackID: String, repeatMode: MusicRepeatMode, volume: Double) {
        enabled = on
        self.trackID = musicTracks.contains { $0.id == trackID } ? trackID : MusicDefaults.trackID
        self.repeatMode = repeatMode
        self.volume = min(1, max(0, volume))

        guard !Self.isSuppressed else { return }
        guard on else {
            stop()
            return
        }
        let file = selectedTrack.file
        if playingFile == file, let player {
            player.volume = Float(self.volume)
            player.numberOfLoops = repeatMode == .one ? -1 : 0
            if !player.isPlaying {
                player.play()
                isPlaying = true
            }
            return
        }
        start(file: file)
    }

    func setVolume(_ value: Double) {
        volume = min(1, max(0, value))
        player?.volume = Float(volume)
    }

    func stop() {
        player?.stop()
        player = nil
        playingFile = nil
        playingTrackID = nil
        isPlaying = false
    }

    // MARK: 재생

    private func start(file: String) {
        stop()
        guard let url = Self.url(for: file) else {
            report("E-MACOS-AUDIO-0001", "음악 파일을 찾지 못했습니다: \(file)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = Float(volume)
            player.numberOfLoops = repeatMode == .one ? -1 : 0
            player.prepareToPlay()
            guard player.play() else {
                report("E-MACOS-AUDIO-0002", "재생을 시작하지 못했습니다: \(file)")
                return
            }
            self.player = player
            playingFile = file
            playingTrackID = trackID
            isPlaying = true
            lastErrorCode = nil
            Logger.shared.info("음악", "재생 \(selectedTrack.title) · \(repeatMode.title)"
                               + " · 볼륨 \(Int(volume * 100))%")
        } catch {
            report("E-MACOS-AUDIO-0002",
                   "음악을 열지 못했습니다(\(file)): \(error.localizedDescription)")
        }
    }

    private func report(_ code: String, _ message: String) {
        lastErrorCode = code
        isPlaying = false
        Logger.shared.error("음악", message, code: code)
        onError?(code)
    }

    private func handleFinished() {
        guard enabled, !Self.isSuppressed else { return }
        switch repeatMode {
        case .one:
            start(file: selectedTrack.file)         // numberOfLoops=-1 이라 보통 오지 않는다
        case .all:
            let index = musicTracks.firstIndex { $0.id == trackID } ?? 0
            let next = musicTracks[(index + 1) % musicTracks.count]
            trackID = next.id
            start(file: next.file)
            onTrackChanged?(next.id)
        case .off:
            stop()
            Logger.shared.info("음악", "재생 끝(반복 안 함)")
        }
    }

    // MARK: 파일 위치

    /// 앱 번들 → 개발용 소스 폴더 순으로 음악 파일을 찾는다.
    static func url(for file: String) -> URL? {
        let manager = FileManager.default
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Music/\(file)"))
            candidates.append(resources.appendingPathComponent(file))
        }
        // swift run(개발)은 번들 밖에서 실행되므로 소스 옆 Resources/Music 을 쓴다.
        let native = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // PSolitaire
            .deletingLastPathComponent()        // Sources
            .deletingLastPathComponent()        // native
        candidates.append(native.appendingPathComponent("Resources/Music/\(file)"))
        return candidates.first { manager.fileExists(atPath: $0.path) }
    }
}

// MARK: - AVAudioPlayerDelegate

extension MusicPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.handleFinished() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let reason = error?.localizedDescription ?? "알 수 없는 오류"
        Task { @MainActor in
            self.report("E-MACOS-AUDIO-0002", "음악을 재생하지 못했습니다: \(reason)")
        }
    }
}
