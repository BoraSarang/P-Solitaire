// SettingsViews.swift — 설정·전적·판 번호 입력 창(모두 네이티브 SwiftUI).

import SwiftUI
import AppKit
import PSolitaireKit

// MARK: - 설정

struct SettingsView: View {
    @ObservedObject var controller: GameController
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            Form {
                Section("모양") {
                    Picker("배경", selection: Binding(
                        get: { controller.backgroundKey },
                        set: { controller.setTheme(background: $0) })) {
                        ForEach(backgroundKeys, id: \.self) { key in
                            Text(tableThemes[key]?.title ?? key).tag(key)
                        }
                    }
                    Picker("카드 뒷면", selection: Binding(
                        get: { controller.backKey },
                        set: { controller.setTheme(back: $0) })) {
                        ForEach(backKeys, id: \.self) { key in
                            Text(backThemes[key]?.title ?? key).tag(key)
                        }
                    }
                    Picker("확대", selection: Binding(
                        get: { controller.preferredZoomPct },
                        set: { controller.setZoom($0) })) {
                        ForEach(GameController.zoomLevels, id: \.self) { level in
                            Text("\(level)%").tag(level)
                        }
                    }
                    Toggle("효과음", isOn: Binding(
                        get: { controller.soundOn },
                        set: { controller.setSound(on: $0) }))
                    Toggle("애니메이션", isOn: Binding(
                        get: { controller.animationsOn },
                        set: { controller.setAnimations(on: $0) }))
                }

                Section("게임") {
                    Picker("클론다이크 카드 넘기기", selection: Binding(
                        get: { controller.drawCount },
                        set: { controller.setDrawCount($0) })) {
                        Text("1장").tag(1)
                        Text("3장").tag(3)
                    }
                    .disabled(controller.variant != .klondike)

                    Picker("스파이더 난이도", selection: Binding(
                        get: { controller.spiderSuits },
                        set: { controller.setSpiderSuits($0) })) {
                        Text("1무늬 (쉬움)").tag(1)
                        Text("2무늬 (보통)").tag(2)
                        Text("4무늬 (어려움)").tag(4)
                    }
                    .disabled(controller.variant != .spider)

                    Picker("스파이더 묶음 이동", selection: Binding(
                        get: { controller.spiderGroup },
                        set: { controller.setSpiderGroup($0) })) {
                        Text("같은 무늬만 (MS 규칙)").tag("same_suit")
                        Text("무늬 상관없이 (쉬움)").tag("any_suit")
                    }
                    .disabled(controller.variant != .spider)

                    Toggle("스파이더 풀리는 판만", isOn: Binding(
                        get: { controller.spiderWinnable },
                        set: { controller.setSpiderWinnable($0) }))
                        .disabled(controller.variant != .spider || controller.preparingDeal)
                    Text("켜 두면 새 스파이더 판은 항상 이길 수 있는 배분으로 나옵니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("자동 기능") {
                    ForEach(AutoFeature.allCases, id: \.rawValue) { feature in
                        Toggle(feature.title, isOn: Binding(
                            get: { controller.autoOn(feature) },
                            set: { controller.setAuto(feature, on: $0) }))
                    }
                }

                Section("데이터") {
                    HStack {
                        Text("전적·설정 파일")
                        Spacer()
                        Text(GameController.statsPath.replacingOccurrences(
                            of: NSHomeDirectory(), with: "~"))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("진행 중인 판은 자동으로 저장되어 다음 실행 때 이어집니다.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("전적 초기화…") { confirmReset = true }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 10)
        }
        .frame(width: 520, height: 740)
        .navigationTitle("P-Solitaire 설정")
        .alert("전적 초기화", isPresented: $confirmReset) {
            Button("취소", role: .cancel) {}
            Button("초기화", role: .destructive) { controller.resetStats() }
        } message: {
            Text("모든 게임의 판 수·승리·최고 기록을 지웁니다. 진행 중인 판과 설정은 그대로 둡니다.")
        }
    }
}

// MARK: - 전적

struct StatsView: View {
    @ObservedObject var controller: GameController
    @State private var confirmReset = false

    var body: some View {
        StatsContent(records: controller.allRecords,
                     currentKind: controller.variant,
                     statsPath: GameController.statsPath,
                     onReset: { confirmReset = true })
            .alert("전적 초기화", isPresented: $confirmReset) {
                Button("취소", role: .cancel) {}
                Button("초기화", role: .destructive) { controller.resetStats() }
            } message: {
                Text("모든 게임의 판 수·승리·최고 기록을 지웁니다. 진행 중인 판과 설정은 그대로 둡니다.")
            }
    }
}

/// 창 제목과 겹치지 않도록 큰 "전적" 제목은 두지 않는다.
/// 게임 이름은 왼쪽, 숫자는 모두 오른쪽 정렬해 머리글과 값을 같은 선에 맞춘다.
struct StatsContent: View {
    let records: [GameRecord]
    let currentKind: GameKind
    let statsPath: String
    let onReset: () -> Void

    private let columnSpacing: CGFloat = 14
    private let playedWidth: CGFloat = 46
    private let wonWidth: CGFloat = 42
    private let rateWidth: CGFloat = 62
    private let timeWidth: CGFloat = 76
    private let scoreWidth: CGFloat = 76

    private var totalPlayed: Int { records.reduce(0) { $0 + $1.played } }
    private var totalWon: Int { records.reduce(0) { $0 + $1.won } }
    private var totalRate: String {
        guard totalPlayed > 0 else { return "–" }
        return String(format: "%.1f%%", Double(totalWon) * 100.0 / Double(totalPlayed))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("게임별 기록")
                        .font(.system(size: 18, weight: .semibold))
                    Text("이 Mac에 저장된 플레이만 집계합니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                HStack(spacing: 16) {
                    metric("총 판", "\(totalPlayed)")
                    Divider().frame(height: 26)
                    metric("승리", "\(totalWon)")
                    Divider().frame(height: 26)
                    metric("전체 승률", totalRate)
                }
            }

            VStack(spacing: 0) {
                headerRow
                Divider()
                ForEach(Array(records.enumerated()), id: \.element.kind.rawValue) { index, record in
                    if index > 0 { Divider().padding(.leading, 14) }
                    recordRow(record, index: index)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }

            HStack(spacing: 12) {
                Text("저장 위치: " + statsPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(statsPath)
                Spacer(minLength: 8)
                Button(action: onReset) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("전적 초기화…")
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("모든 게임의 전적을 초기화합니다")
            }
        }
        .padding(20)
        .frame(width: 620)
    }

    private var headerRow: some View {
        HStack(spacing: columnSpacing) {
            HStack(spacing: 0) {
                // 행의 현재 게임 막대(3pt)+간격(6pt)과 이름 시작선을 맞춘다.
                Color.clear.frame(width: 9, height: 1)
                Text("게임")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            headerNumber("판", width: playedWidth)
            headerNumber("승", width: wonWidth)
            headerNumber("승률", width: rateWidth)
            headerNumber("최고 시간", width: timeWidth)
            headerNumber("최고 점수", width: scoreWidth)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color.primary.opacity(0.035))
    }

    private func headerNumber(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .frame(width: width, alignment: .trailing)
    }

    private func recordRow(_ record: GameRecord, index: Int) -> some View {
        let isCurrent = record.kind == currentKind
        let rate = record.played > 0 ? String(format: "%.1f%%", record.rate) : "–"
        let time = record.bestTime.map { "\($0)초" } ?? "–"
        let score = record.bestScore.map { "\($0)점" } ?? "–"

        return HStack(spacing: columnSpacing) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 16)
                    .opacity(isCurrent ? 1 : 0)
                Text(record.kind.nameKo)
                    .fontWeight(isCurrent ? .semibold : .regular)
                if isCurrent {
                    Text("현재")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            number("\(record.played)", width: playedWidth)
            number("\(record.won)", width: wonWidth)
            number(rate, width: rateWidth)
            number(time, width: timeWidth)
            number(score, width: scoreWidth)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.018) : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.kind.nameKo)\(isCurrent ? ", 현재 게임" : "")")
        .accessibilityValue("\(record.played)판, \(record.won)승, 승률 \(rate), 최고 시간 \(time), 최고 점수 \(score)")
    }

    private func number(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .monospacedDigit()
            .frame(width: width, alignment: .trailing)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
        }
    }
}

// MARK: - 판 번호 입력

struct SeedEntryView: View {
    @ObservedObject var controller: GameController
    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("판 번호로 새 게임")
                .font(.headline)
            Text("같은 번호를 입력하면 같은 카드 배분으로 시작합니다.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("판 번호", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { start() }

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Button("현재 번호 사용") { text = "\(controller.game.seed)" }
                Spacer()
                Button("취소") { controller.showSeedEntry = false }
                    .keyboardShortcut(.cancelAction)
                Button("시작") { start() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            text = "\(controller.game.seed)"
            focused = true
        }
    }

    private func start() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Int(trimmed) != nil else {
            error = "숫자로 된 판 번호를 입력하세요."
            return
        }
        error = nil
        controller.startGame(withSeedText: trimmed)
    }
}

// MARK: - 창 제목 표시줄 색 맞추기

struct WindowAppearanceAccessor: NSViewRepresentable {
    let backgroundKey: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { apply(to: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: view) }
    }

    private func apply(to view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = false
        window.appearance = NSAppearance(named: backgroundKey == "dark" ? .darkAqua : .aqua)
    }
}
