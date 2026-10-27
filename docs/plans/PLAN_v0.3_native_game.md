# PLAN_v0.3_native_game.md
> 생성일: 2026-10-19 | 플랫폼: macos(game) | 작성자: OpenCode

## 1. 목표 (1줄)
지금의 **Python + Tkinter** 앱(런처 스텁이 Homebrew 파이썬 프레임워크 78MB 에 의존)을
**Swift 네이티브(SwiftUI + Canvas, 필요 시 AppKit)** 로 전면 재작성해
클론다이크·프리셀·스파이더 3종을 그대로 즐길 수 있게 한다 — 의존성 없는 자가 완결 앱.

## 2. 범위
- **포함**
  1. `native/` SwiftPM 패키지: **`PSolitaireKit`**(규칙·저장, 테스트 가능) + **`PSolitaire`**(SwiftUI 앱 실행 파일)
  2. **규칙 엔진 이식**(`solitaire_core.py` 1,072줄 → Swift): 카드·더미·묶음 계산(`run_from`)·점수·실행 취소·힌트·자동 이동·자동 완성, 클론다이크/프리셀(슈퍼무브)/스파이더(1·2·4무늬, 세트 수거, `suit_free` 옵션)
  3. **코어 테스트 이식**: `test_core.py` 51개 → Swift 테스트(`swift test`). 규칙 이식의 유일한 방어선
  4. **화면 재작성**(SwiftUI `Canvas`, 필요 시 AppKit 브리지): 카드 앞면(코너 숫자·핍 배치 9·10 겹침 방지)·뒷면 3종·배경 3종 테마, 3종 배치(`STYLE`/`top_refs` 이식), 상태줄, 메뉴·단축키(`Cmd+1/2/3`·`F2`·`Cmd+Z`·`H`·`A`·`D`·`Cmd+Shift+A`·`Cmd+Shift+D`), 대화상자(전적·도움말·우승·힌트 없음), 우승 연출(카드 쏟아지기)·`Esc` 중단, 디버그 패널(다시 그리기 ms·메모리·ERROR 수)
  5. **저장**: 설정·전적을 **별도 파일**(`~/.psolitaire-nat.json`, 스키마는 현행과 호환)에 저장 → 현행 앱 데이터 보호
  6. **검증 루프**: ① `swift test`(규칙) ② 앱 내 `--selftest`(UI 계층: 배치·히트테스트·드래그·테마·자동 기능, 창 없이) ③ **오프스크린 PNG 렌더**(`cacheDisplay`)로 캡처 → 창을 띄우지 않고 화면 검증 ④ 실기기 확인(사용자)
  7. `build_native.sh`(빌드→번들 조립→`~/Applications/P-Solitaire Native.app` 설치) · 문서 갱신(PLAN·README·DESIGN·TODO·CHANGELOG·api·AGENTS.local·세션)
- **제외(이번 단계)**
  - **현행 Python 앱 삭제·교체 없음** — 네이티브가 완성·확인된 뒤 별도 승인으로 교체(그때까지 `P-Solitaire.app` 유지)
  - 소리·창 크기 조절·이어하기(별도 TODO 후보) — 단, 창 크기 조절은 SwiftUI에서 자연스러우면 허용
  - 게임 규칙 변경 없음(현행과 100% 동일하게 이식; 스파이더 기본은 `same_suit`)

## 3. 설계 결정
| 결정 | 이유 |
|---|---|
| SwiftUI + `Canvas` 로 그린다 | 플랫폼 규칙(§macos)이 SwiftUI 기본. 카드 그림은 `GraphicsContext` 로 충분하고, 메뉴·대화상자·단축키가 native 로 공짜 |
| 엔진을 `PSolitaireKit` 으로 분리 | 규칙을 창 없이 테스트할 수 있어야 이식 실수를 잡는다(`swift test`). 앱 타깃은 그리기·입력만 |
| 코어 테스트 51개를 **그대로** 옮긴다 | 이식의 유일한 안전장치. 이름·의미를 유지해 실패 시 대응이 쉽다 |
| 설정·전적은 별도 파일 | 스키마는 같지만 파일을 나눠 현행 앱의 기록(클론다이크 33판 등)을 건드리지 않는다 |
| 번들 조립은 스크립트(`build_native.sh`) | `swift build -c release` 로 만든 실행 파일 + `Info.plist` + 아이콘(기존 `icns` 재사용)로 `.app` 을 조립 — Xcode 프로젝트 파일 없이 재현 가능. `xcodebuild` 지원 여부는 스캐폴딩 때 확인해 되면 그 경로를 쓴다 |
| 앱 이름은 잠정 `P-Solitaire Native` | 현행 앱과 병행 실행·비교가 목적. 최종 교체는 사용자 확인 후 |
| 렌더링 검증은 오프스크린 PNG | 사용자가 게임 중일 때 창을 띄우면 포커스를 뺏는다 → `cacheDisplay` 로 그려 파일로 확인 |

## 4. 마일스톤 · 검증
1. **M1 엔진**: `PSolitaireKit` + 테스트 51개(현재 53개) → `swift test` **53/53**, ERROR 0
2. **M2 화면(클론다이크)**: 그림·배치·드래그·클릭·상태줄·메뉴·실행 취소 → `--selftest` 통과 + 오프스크린 PNG
3. **M3 3종 + 기능**: 프리셀·스파이더(난이도·묶음 옵션)·테마 3+3·자동 기능 3종·힌트·우승 연출·대화상자·디버그 패널
4. **M4 번들·설치·문서**: `build_native.sh` → `~/Applications/P-Solitaire Native.app`, Cold Start·메모리 실측, 캡처, 문서 갱신

## 4-1. 진행 기록
| 날짜 | 내용 | 검증 |
|---|---|---|
| 2026-10-19 | M1~M4 1차 완료 — 엔진 이식·화면 작성·번들(v0.3.0 빌드 1)·캡처 27장 | `swift test` 50/50 · `--selftest` 80/80 |
| 2026-10-19 | 새 코드 버그 3건 수정(`Hit` 의 열/카드 위치 분리 · `save()` 설정 반영 · 검사 판 고정) | `--selftest` 80/80 |
| 2026-10-19 | **T-013 규칙 반영**(python v0.2.5 와 동일): `groupRun`·`pickWhole`·`groupLimitNote`(이유 문구 + `buriedText`) · `Klondike`/`FreeCell`/`Spider.pick()` 태블로 경로 교체 · `GameController.press()` 실패 시 이유 안내 · `SelfTest.checkBuriedCard()` | `swift test` **51/51** · `--selftest` **85/85** |
| 2026-10-19 | 문구 폭 실측(창 953px): 스파이더 `무늬가 다르면 한 묶음으로 못 옮깁니다 (게임 → 스파이더 묶음 이동)` = 430px / 쓸 수 있는 440px | 파이썬 앱 글꼴 실측 |
| 2026-10-19 | **v0.3.1 재패키징·설치 완료**(사용자 지시 "둘 다 빌드해") — `~/Applications/P-Solitaire Native.app` v0.3.1(빌드 2), 908K, 서명 확인 통과 | 사용자 실기기 확인 대기(T-011) |
| 2026-10-20 | **파이썬 v0.2.6(26) 설치·동결** — 소스·테스트·빌드 스크립트를 `archive/python/`으로 이동, `ARCHIVED.md` 기록. 네이티브 아이콘을 `native/AppIcon.icns`로 독립 | 아카이브 테스트 51/94 · 설치본 서명/리소스 확인 · 네이티브 빌드 영향 없음 |
| 2026-10-20 | **네이티브 점검·개선 제안** — 소스 정독, `--selftest` 85/85, 샷 27장, 실제 창/메뉴 캡처. P0(줌·메뉴·데이터 보호·버그)~P2 제안 정리 | `docs/plans/NATIVE_REVIEW_2026-10-20.md` · `docs/TODO.md` T-014~T-019 |
| 2026-10-20 | **v0.4.0 P0~P2 구현** — 줌·메뉴/단축키·이어하기/전적 집계·리두·설정/전적/시드·확인/우승/막힘 대화상자·웨이스트 팬·드래그/비행/소리·카드 그림/그림자/타이틀바·접근성 | `swift test` **53/53** · `--selftest` **123/123** · `--shots` **45장** |
| 2026-10-20 | **v0.4.0 패키징** — `~/Applications/P-Solitaire Native.app` v0.4.0(빌드 3), 1.4MB · 서명/중복 실행 금지 확인 · 파이썬 앱/데이터 무수정 | `codesign --verify --strict` · `Info.plist` |
| 2026-10-20 | **v0.4.1 전적 창 정렬** — 중복 제목 제거·고정 열/오른쪽 숫자 정렬·현재 게임 배지·총계 요약·VoiceOver | `--selftest` **125/125** · `--shots` **46장**(`stats.png`) · v0.4.1(빌드 4) |
| 2026-10-20 | **v0.4.2 직접 드래그 즉시 이동** — 손을 뗄 때 원래 자리→목적지로 다시 날아가던 비행 연출 제거, 자동 이동에만 유지 | `swift test` **53/53** · `--selftest` **126/126** · v0.4.2(빌드 5) |
| 2026-10-20 | **v0.5.0 최종 이름 교체·카드 핍 그림자 수정** — `P-Solitaire Native` → `P-Solitaire`, 번들 ID/실행 파일/로그 경로 변경 · `drawCardFaceShadow`를 카드 실루엣에만 적용해 하트 핍 주변 테두리 제거 | `swift test` **53/53** · `--selftest` **127/127** · `--shots` **46장** · v0.5.0(빌드 6) |

> **다음 단계**: M1~M4와 P0~P2, T-020(실기기 확인), T-021(최종 이름 교체) 모두 완료됐다. 새 요청이 생기면 `docs/TODO.md`에 추가한다.

## 5. 성능 예산 (플랫폼 규칙)
- Cold Start **≤1.5s** · 메모리 **≤300MB** · **60fps**(프레임 p95 ≤16.7ms)
- 초과 시 WARN + `bd create --label perf`(bd 미사용 프로젝트이면 `docs/TODO.md` ③ 에 기록)

## 6. 에러 코드
- 접두 **`E-MACOS-GAME-####`** (`error_message_ko.json` 상당 문구 표를 Swift 안에 둔다). 규칙 위반 조작은 조용히 거부 + 안내 문구(현행과 동일)

## 7. 문서
- PLAN: 본 문서 / TODO: 새 항목 T-012(네이티브 재작성) / CHANGELOG: v1.0.0-native(가칭)
- DESIGN: 네이티브 §추가(테마·핍·배치 이식표) / api: `PSolitaireKit` API 요약 / README: 네이티브 빌드·실행 안내

## 8. 예외 규칙
- v0.1~v0.2.4 와 동일: 사용자 화면 간섭 금지(창 띄우기 전 확인), 파괴적 변경 금지
- **현행 앱 파일·데이터(`~/Applications/P-Solitaire.app`, `~/.solitaire_python_stats.json`)은 이 작업에서 수정하지 않는다**
