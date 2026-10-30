# AGENTS.local.md — P-Solitaire (macOS 네이티브)
> 위치: /Users/lee/Documents/Apps/P-Solitaire/AGENTS.local.md
> 공통 가이드(~/.config/opencode/AGENTS.md, rules/*)는 재작성하지 않는다. 이 프로젝트에서 **달라지는 것만** 기록한다.

## 0. 현재 방향 (2026-10-30)
- **활성 트랙: Swift 네이티브만** — `native/` · Swift 6 + SwiftUI `Canvas` + SwiftPM · macOS 14+ · 외부 런타임 의존 없음.
- **파이썬 판은 동결/아카이브**: v0.2.6(빌드 26) · 소스는 `archive/python/` · 설치 번들은 현재 `~/.Trash/P-Solitaire.app`에 기록 보존용으로 있다(이번 작업에서 이동·수정하지 않음).
  - **금지**: `archive/python/` 소스 수정, 버전 올리기, `build_and_run.sh package`(동결 설치본을 덮어쓴다).
  - 참고 검증만 허용: `cd archive/python && ./build_and_run.sh test game unit` (코어 51 + UI 94).
- 네이티브 설치본: `~/Applications/P-Solitaire.app` — 설치 **v0.7.0(빌드 9)** · 작업 트리와 동일 · 번들 ID `com.borasarang.P-Solitaire` · 실행 파일 `P-Solitaire`.
- **저장소**: <https://github.com/BoraSarang/P-Solitaire> (공개) · 기본 브랜치 `main` · 작업은 브랜치 + PR(squash)로 합친다 · `archive/`·`.build/`·`native/shots/`는 올리지 않는다.
- 설정·전적: `~/.psolitaire-nat.json` · 로그: `~/Library/Logs/P-Solitaire.log`.
- **최종 이름 교체 완료(T-021)**: `P-Solitaire Native` → `P-Solitaire`. 이전 v0.4.2 앱은 Applications에서 제거해 `~/.Trash/P-Solitaire Native (v0.4.2 235240).app`에 보관했다. Applications에는 `P-Solitaire.app`만 있다.

## 1. 프로젝트 정보
- **프로젝트명**: P-Solitaire
- **플랫폼**: macos (game) — `rules/platforms/AGENTS.macos.md` 계열 적용
- **게임**: 클론다이크 · 프리셀 · 스파이더(1·2·4무늬) — 규칙은 `native/Sources/PSolitaireKit`에만
- **design_profile**: custom — 클래식 MS 솔리테어 룩(초록 탁자·도형 카드) · 토큰은 `docs/DESIGN.md`·`native/Sources/PSolitaire/Theme.swift`
- **작업 모드 기본값**: 정식
- **현재 상태**: 작업 트리·설치본 v0.7.0(빌드 9) · `swift test` **64/64** · `--selftest` **200/200** · `--shots` **46장**
- **문서**: `docs/TODO.md`(다음 일) · `docs/plans/PLAN_v0.6_native_game.md`(화면 버튼·배경음) · `docs/plans/PLAN_v0.3_native_game.md`(계획/이력) · `docs/plans/NATIVE_REVIEW_2026-10-20.md`(개선 제안) · `docs/ASSETS.md`(음악 출처·라이선스)

## 2. 빌드·검증 (native)
```sh
cd native
./build_native.sh test       # swift test + swift run PSolitaire --selftest
./build_native.sh shots      # 게임 3종 × 테마 9조합 + 전체 창 + 150% + 전적 PNG 46장 (창 없이)
./build_native.sh package    # 릴리스 빌드 → ~/Applications/P-Solitaire.app
./build_native.sh run        # 설치본 실행
swift test                   # 규칙 테스트만
```
- **패키징은 파괴적**: `~/Applications/P-Solitaire.app`를 덮어쓴다. 실행 중인 앱이 있으면 먼저 알린다(진행 중인 판 소실). 이전 `P-Solitaire Native.app`는 Applications에서 제거해 Trash에 보관했다.
- **창을 띄우는 검증**: `open -g`로 포커스를 뺏지 않고, `screencapture -x -o -l <창ID>`로 창만 캡처한다. 사용자 판에 클릭을 합성하지 않는다(승인 필요).
- 창 ID는 `CGWindowListCopyWindowInfo`(Swift)로 얻는다. 캡처 이미지는 `docs/images/`에 날짜를 붙여 보관.
- **`--shots`**: 보드 27장 + 전체 창 9장 + 150% 9장 + 전적 1장 = **46장**. 상태줄·대화상자·메뉴는 실제 창 캡처로 확인한다(포커스는 사용자 승인 후).
- **포커스 금지**: 사용자가 맥을 쓰는 동안 `open`(앞으로 가져오기)·AppleScript 클릭/키 입력을 쓰지 않는다. 확인은 `open -g`(백그라운드)와 `screencapture -x -o -l <창ID>`만, 그것도 사용자 승인 후.

## 3. 번들·ID·아이콘
- 네이티브: 앱 이름 `P-Solitaire` · 번들 ID `com.borasarang.P-Solitaire` · 실행 파일 `P-Solitaire` · 로그 `~/Library/Logs/P-Solitaire.log` · 아이콘 `native/AppIcon.icns`(파이썬 `build/`와 독립)
- 동결 파이썬: 번들 ID `com.borasarang.P-Solitaire` · 앱 이름 `P-Solitaire`. **네이티브와 같은 ID이므로 복원/동시 실행 금지**
- 네이티브 번들은 `native/build_native.sh`가 `Info.plist`를 생성해 조립한다(Xcode 프로젝트 없음). `CFBundleShortVersionString`/`CFBundleVersion`은 스크립트 상단에서 올린다.

## 4. 성능 예산 Override
- budgets.json `game` 기본값 적용: 목표 60fps · 다시 그리기 **60ms 이하** · 메모리 **≤300MB** · Cold Start ≤1.5s.
- 2026-10-19 실측(네이티브, 3게임 × 테마 9조합): 다시 그리기 4.1~12.3ms · 메모리 ≈118MB → 여유.
- 우승 연출(카드 쏟아지기)은 45ms 간격(≈22fps)으로 의도적으로 느리게 둔다.
- 초과 시 WARN + `docs/TODO.md` ③에 기록(이 프로젝트는 bd 미사용).

## 5. 네이티브 구현 규칙
- **규칙은 Kit에만**: 새 게임·규칙·점수·힌트·자동 이동은 `native/Sources/PSolitaireKit`. 앱 타깃(`PSolitaire`)은 그리기·입력·메뉴·상태 표시.
- **좌표계**: 배치·히트테스트·드래그·드롭은 **1x 논리 좌표**로 유지한다. 줌을 추가해도 배율은 렌더 경계(예: `.scaleEffect`)에서만 적용하고, 규칙·레이아웃 계산에 섞지 않는다.
- **카드 식별**: 그리기·레이아웃 키는 `ObjectIdentifier(Card)`(스냅숏 복원 시 새 객체), 규칙 비교는 `(suit, rank)`.
- **저장**: `GameController.save()`를 거쳐 JSON을 atomic write. 파이썬 파일(`~/.solitaire_python_stats.json`)은 절대 건드리지 않는다.
- **UI 문구는 한국어**. 메뉴 체크는 문자열 `"✓ "` 대신 native `Toggle`/checkmark를 우선. 단축키는 메뉴에 보이게 둔다.
- **검증 추가**: 새 기능은 `swift test`(규칙) / `--selftest`(화면·상태) / `--shots`(시각) 중 해당 검증을 함께 추가한다.
- **파괴적 동작**: 새 게임·다시 시작·게임 전환 시 진행 중인 판(`moves > 0 && !isWon`)이면 확인을 받는다(구현됨). 창 닫기/종료는 자동 저장으로 보호한다.
- **디버그 패널**: `⌘⇧D`. 성능(다시 그리기 ms·메모리·오류 수) 확인용. 빨간 닫기 후에도 메뉴로 다시 열린다(상태 동기화 구현됨).

## 6. 디자인 토큰
- 색·폰트·간격·카드 도형은 `docs/DESIGN.md` + `native/Sources/PSolitaire/Theme.swift`·`Drawing.swift`.
- 카드 80×112 · 간격 13 · 여백 18 · 컨트롤 바 46 · 상태줄 34 · 창 674/767/953×620(100% 기준, v0.6.0).
- 배경 3종(클래식 초록·파란 탁자·어두운 탁자) × 카드 뒷면 3종(푸른 격자·붉은 햇살·청록 물방울) — 조합은 자유.

## 7. 다음 작업
- **v0.7.0 완료·설치·머지** — 힌트 해답 탐색기(T-026) · `swift test` 64/64 · `--selftest` 200/200 · PNG 46장 · `~/Applications/P-Solitaire.app` v0.7.0(빌드 9) · PR #6 squash 머지 완료(`main` 000187c).
- **남은 일**: 실제 창에서 힌트 체감 확인(사용자 미확인) · Spider 2·4무늬 힌트·Klondike 3장 넘기기 해결률 개선 여지 · 새 요청은 `docs/TODO.md`에 추가. 이전 PR #3은 squash 머지 완료(`main` 4fdb633).
- 이전 `P-Solitaire Native.app`(v0.4.2)는 Applications에서 제거해 Trash에 보관했다. 실행 중인 앱이 있으면 자동 종료/포커스 이동 금지.
