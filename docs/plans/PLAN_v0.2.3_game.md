# PLAN_v0.2.3_game.md
> 생성일: 2026-10-19 | 플랫폼: game | 작성자: OpenCode

## 1. 목표 (1줄)
메뉴 막대에 "Python"으로 보이던 **앱 이름 문제**를 고치고(v0.2.2),
사용자가 신고한 **스파이더 "두 장이 안 잡힌다"** 를 규칙 근거와 함께 정리해
**왜 한 장만 집히는지 화면이 알려 주게** 하고 **규칙을 고를 수 있게** 한다(v0.2.3).

## 2. 범위
- 사용자 요청(그대로)
  1. "메뉴 막대에 P-Solitaire 라고 나오게 해 줘" → `.app` 번들 안에서 실행 파일이 놓이는 자리 문제 수정
  2. "스파이더에서 두 장 드래그하려면 안쪽 카드만 드래그된다 · 규칙을 제대로 모르는 것 같은데" → 규칙 재검증 + 안내 + 옵션
- **포함**
  1. (v0.2.2) 번들 `Contents/MacOS/@NAME@-launcher` 가 프레임워크의 `Resources/Python.app/Contents/MacOS/Python` **스텁을 exec**(없으면 시스템 파이썬 폴백) → macOS 가 `CFBundleName` 을 읽어 메뉴 막대가 "P-Solitaire"가 된다
  2. (v0.2.2) `Info.plist`(`CFBundleExecutable=@NAME@-launcher`·`CFBundleDevelopmentRegion=ko`·`LSMinimumSystemVersion=11.0`) · 창 제목에서 `(Python)` 제거 · `tools/bundle_name.py`(검증 도구) · `build_and_run.sh` 의 `cmd_stub()`·`probe_py()`
  3. (v0.2.3) **재현 검사**: 무작위 스파이더 판 31,200자리에서 "누른 카드 → 집은 묶음 → 실제 이동 카드"를 MS 규칙(같은 무늬 내림차순)과 대조 → **어긋남 0건**(규칙·화면은 정상)
  4. (v0.2.3) **이유 안내**: `BaseGame.group_limit_note()` — 묶음이 "숫자만 이어지는 카드"보다 짧으면 이유 한 줄. 화면은 카드를 집는 순간 상태줄에 `묶음 N장` 또는 `무늬가 다르면 한 장씩만 옮깁니다 (게임 → 스파이더 묶음 이동)`(4초)
  5. (v0.2.3) **규칙 선택(쉬움 옵션)**: `run_from(..., rank_only=True)` · `Spider(suit_free=)` · `Spider.set_suit_free()` · `settings["spider_group"]`(`same_suit` 기본 / `any_suit`) · 메뉴 **게임 → 스파이더 묶음 이동** — 판·점수는 그대로, 이동 규칙만 바뀐다
  6. 문서 갱신(README·DESIGN·CHANGELOG·TODO·API·AGENTS.local.md·세션) + `docs/images/archive/` 로 옛 캡처 정리 · `.DS_Store` 제거
  7. 앱 번들 재생성(v0.2.2 빌드 22 → v0.2.3 빌드 23)
- **제외**
  - **기본 규칙 변경 없음** — 실제 MS 스파이더와 같게 `same_suit` 유지(사용자 확인). `any_suit` 는 사용자가 메뉴에서 고르는 옵션
  - 스파이더 세트 자동 수거 방식, 진행 중인 판 저장, 카드 소리, 창 크기 조절

## 3. 설계 결정
| 결정 | 이유 |
|---|---|
| 규칙 자체는 고치지 않는다 | MS 공식 도움말·Wikipedia 모두 "같은 무늬 내림차순만 통째로 이동, 부분 묶음은 분리 가능" — 무늬가 섞인 두 장은 한 장씩이 정상. 재현 검사 31,200자리에서 어긋남 0건 |
| 대신 **화면이 이유를 말하게** 한다 | "규칙을 모르는 것 같다"는 지적의 실질은 *왜 한 장만 집히는지 알 수 없다*였다. 상태줄 한 줄로 즉시 설명한다 |
| 규칙을 **옵션**으로 열어 둔다 | 사용자가 원하는 동작(무늬 상관없이)을 막지 않으면서 MS 충실도는 기본값으로 지킨다. 바꿔도 판·점수·실행 취소는 그대로 |
| `run_from()` 에 `rank_only` 를 더한다 | 무늬·색 규칙만 끄는 세 번째 모드가 필요하다(색 교대 = 클론다이크·프리셀, 같은 무늬 = 스파이더 기본, 숫자만 = 스파이더 쉬움). 묶음 계산은 여전히 한 함수에서만 한다 |
| 상태줄 문구는 `pick()` 결과와 비교해 만든다 | "숫자만 이어지는 묶음"과 "실제로 집은 묶음"의 차이가 곧 제한 이유다 — 게임별로 문구만 바꾼다 |
| 스텁을 번들에 복사한다 | macOS 는 실행 파일이 어느 `.app` 안에 있는지로 앱 이름을 정한다. `bin/python3.14` 복사는 CoreFoundation 의존이 없어 이름이 안 잡힌다(실측) |

## 4. 문서 위치
- PLAN: 본 문서 / TODO: `docs/TODO.md` T-009(완료) / CHANGELOG: v0.2.2 · v0.2.3
- DESIGN: §3(묶음 집기 표현)·§5(시스템 UI: 메뉴 막대 이름) / API: `docs/api/README.md` §1(`run_from`·`group_limit_note`)·§3(`settings["spider_group"]`)

## 5. 성능 예산
- v0.1~v0.2.1 과 동일: 다시 그리기 60ms 이하 · 메모리 ≤300MB · 우승 연출 45ms 간격
- 규칙 옵션·이유 문구는 이동/집기 시점의 문자열 한 줄이라 비용이 없다(다시 그리기 없음)

## 6. 에러 코드
- 추가 없음. 알 수 없는 `settings["spider_group"]` 값은 `normalize_settings()` 가 기본값(`same_suit`)으로 되돌린다

## 7. 빌드 & 검증 계획
- `./build_and_run.sh test game unit` → 코어 **50** + UI **82** 전부 통과
- 코어: `test_spider_suit_free_moves_mixed_group` · `test_spider_suit_free_toggle_keeps_board` · `test_group_limit_note_explains_why_one_card` · `test_make_game_ignores_suit_free_elsewhere` 추가
- 코어(추가): `test_spider_suit_free_mixed_group_reveals_card`(묶음 이동 → 아래 카드 드러내기·실행 취소) · `test_spider_suit_free_hint_and_auto_move_follow_option`(힌트·더블클릭 자동 이동도 설정을 따르는지)
- UI: 규칙 전환(무늬 섞임 1장 → 옵션 켜면 2장) · 상태줄 문구(`묶음 2장`·이유) · 설정 저장·복원 · 메뉴 항목 추가
- 재현 검사(임시 스크립트): 무작위 판 300개 × 열 10 × 카드 자리 = **31,200자리**에서 누른 자리·집은 묶음·실제 이동 카드 대조 → 어긋남 0건
- 앱 번들: `./build_and_run.sh package game` → 스텁 포함 로그 확인, `tools/bundle_name.py` 로 `CFBundleName=P-Solitaire` 확인, `codesign --verify --deep --strict` 통과
- 실기기 확인(사용자): 메뉴 막대 이름 · 창 제목 · 스파이더에서 두 장 잡기(같은 무늬/섞임)와 상태줄 문구

## 8. 예외 규칙
- v0.1~v0.2.1 과 동일: Python/tkinter · `E-GAME-*` 접두 · 사용자 화면 간섭 금지
- 앱 번들 교체·재시작은 **진행 중인 판을 버리는 파괴적 변경** → 사용자에게 먼저 알리고 승인받는다(이번 세션: 승인받고 재시작)
