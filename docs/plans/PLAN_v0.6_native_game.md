# PLAN v0.6 — 게임 화면 버튼 + 배경음 (native)

> 작성 2026-10-27 · 플랫폼 **macos (game)** · 작업 크기 **M**
> 지원 언어: 기존 앱과 동일하게 **한국어 UI 고정**(`AGENTS.local.md` §5). 이번 작업에서는 String Catalog 도입을 하지 않는다(앱 전체가 한국어 하드코딩인 기존 방식을 그대로 따른다).

## 1. 요청
1. 게임 도중 **새 게임·취소·힌트·확대**를 메뉴/단축키 없이 **화면 버튼**으로 직접 클릭한다.
2. **배경음**을 추가한다. 무료 음악 5곡을 구해 넣고, 설정에서 **배경음 사용·곡 선택·목록 반복**을 고른다.

## 2. 설계

### 2.1 화면 버튼 (`Views.swift`)
- 보드와 상태바 사이에 **높이 46px 컨트롤 바**를 둔다. 창 높이가 46px 늘어나고 보드 영역(540px)은 그대로다.
- 왼쪽: `새 게임` · `취소`(실행 취소) · `힌트`, 오른쪽: `− 100% +` 확대 그룹.
- 메뉴와 같은 `GameController` 메서드를 호출하므로 규칙·확인 대화상자·비활성 조건이 같다.
- 테마의 `statusBg` 를 배경으로 쓰고, 위에 1px 밝은 선을 둬 상태바와 구분한다. 버튼은 28px 높이·둥근 6px·hover 밝기 변화, `help`(툴팁)에 단축키를 적는다.
- 좌표계: 기존처럼 1x 논리 좌표를 유지하고 `.scaleEffect` 경계에서만 배율을 적용한다(버튼도 함께 확대).

### 2.2 배경음 (`MusicPlayer.swift`, `SettingsViews.swift`)
- **AVAudioPlayer** 로 재생한다(외부 패키지 없음). macOS 14 기본 프레임워크.
- 음악 5곡: Kevin MacLeod(incompetech.com) **CC BY 4.0** · 96kbps AAC(m4a)로 변환해 번들 크기를 줄인다. 출처·라이선스는 `native/Resources/Music/CREDITS.md`·`docs/ASSETS.md`·앱 정보/설정에 표시한다.
- 저장 형식(`~/.psolitaire-nat.json`):
  ```json
  "music": { "on": true, "track": "lobby_time", "repeat": "all", "volume": 0.35 }
  ```
  - `repeat`: `off`(반복 안 함) · `one`(한 곡 반복) · `all`(목록 반복, 기본)
  - 값이 깨졌으면 기본값으로 되돌린다(`normalize`).
- 설정 화면 **소리** 섹션: 효과음 · 배경음 사용 · 곡 선택(5곡) · 반복 방식 · 볼륨 · 출처 링크.
- 파일을 찾지 못하면 `E-MACOS-AUDIO-0001`, 재생 실패는 `E-MACOS-AUDIO-0002` 로그 + 상태바 안내. 무음 실패 금지.
- `--selftest`·`--shots` 에서는 소리를 내지 않는다(창 없는 검증).

### 2.3 파일·번들
- 음악 원본은 `native/Resources/Music/*.m4a`(저장소 포함). `build_native.sh package` 가 `Contents/Resources/Music/` 로 복사한다.
- `swift run`(개발)은 `#filePath` 기준 `native/Resources/Music` 을 폴백으로 찾는다.

### 2.4 쉬는 카드 그림자 (2026-10-27 추가)
- 사용자 지적: "드래그 하지 않은 상태에서 카드에 드래그 한 것처럼 동그란 모양으로 표시되는 게 있다."
- 원인: 웨이스트·프리셀·파운데이션·태블로의 **맨 위 카드**에 항상 옅은 그림자(radius 2.5, opacity 0.22, y 1.5)를 줬다. 그림자가 아래 카드 위에 **둥근 그늘**로 떨어져, 집지 않았는데도 집은 카드처럼 보였다.
- 수정: 쉬는 카드는 `drawCardFace` 로 평평하게 그리고, 그림자는 **집은 카드·나는 카드·우승 연출(`drawRaisedCard`)에만** 준다.
- 회귀 검사: `checkRestingCardShadow` — 카드가 있는 상태와 빈 자리 상태를 같은 지점에서 렌더해 색이 같은지 확인(수정 전 `#017700` vs `#007b00` 실패). `checkCardShadow` 에는 "집은 카드만 그림자로 띄움" 대조를 추가.

## 3. 검증
- `swift test`(규칙) 그대로.
- `--selftest` 추가: 음악 5곡·파일 존재·설정 정규화/왕복, 컨트롤 바 렌더 크기, 창 높이 620·보드 영역 540, 버튼 동작(새 게임/취소/힌트/확대) 연결, 쉬는 카드 그림자 없음.
- `--shots`: 전체 창 PNG에 컨트롤 바가 포함되는지 눈으로 확인.
- 성능: 다시 그리기 예산 60ms·메모리 300MB 유지 확인(디버그 패널).

## 4. 위험·대응
- 창 높이 +46px → 150% 확대 시 화면 밖으로 나갈 수 있음 → 기존 `fitZoom` 이 `Metrics.windowH` 를 쓰므로 자동 축소된다. 100% 기준 620px.
- 음악 파일 12MB 안팎으로 번들 증가 → 96kbps AAC로 최소화, 5곡 고정.
- 저작자 표시(CC BY 4.0) 누락 금지 → 설정·정보·CREDITS·docs 4곳에 표기.
- 패키징은 `~/Applications/P-Solitaire.app` 를 덮어쓰므로 **사용자 확인 후** 실행한다. 2026-10-27 사용자 승인 후 실행 완료(앱 종료 → 패키징 → codesign 검증 → 설치본 `--selftest` → `open -g`).

## 5. 완료 정의(DoD)
- [x] 컨트롤 바 버튼 4종이 마우스로 동작하고 메뉴와 같은 결과
- [x] 배경음 5곡·사용/곡/반복/볼륨 설정 저장·복원
- [x] `swift test` **56/56** · `--selftest` **192/192** · `--shots` **46장** 확인
- [x] 쉬는 카드에 드래그 그림자가 남지 않음(회귀 검사 포함)
- [x] TODO·CHANGELOG·DESIGN·README·ASSETS 갱신, 세션 로그
- [x] `build_native.sh package` 로 `~/Applications/P-Solitaire.app` v0.6.0(빌드 8) 설치 — codesign·`--selftest` 192/192
- [x] 실제 창에서 버튼·배경음 확인 — 사용자가 설치본에서 곡/볼륨을 바꿔 재생하고 한 판을 완주
- [ ] 쉬는 카드 그림자 제거 육안 피드백 확인

## 6. 결과 (2026-10-27)

| 항목 | 결과 |
|---|---|
| 화면 버튼 | 46px 컨트롤 바 · 새 게임/취소/힌트/−·배율/+ · 창 620 · `checkControlBar` |
| 배경음 | 5곡 12.9MB · `MusicPlayer.swift` · 설정 소리 섹션 · `music` 저장/정규화 · `checkMusicSettings` |
| 쉬는 카드 그림자 | 위 카드 그림자 제거 · `checkRestingCardShadow`(수정 전 실패 확인) · `checkCardShadow` 대조 추가 |
| 검증 | `swift test` **56/56** · `--selftest` **192/192** · `--shots` **46장** |
| 패키징 | `build_native.sh` v0.6.0(빌드 8) + `Resources/Music` 복사 · `~/Applications/P-Solitaire.app` 설치 완료(codesign·`--selftest` 192/192) |
