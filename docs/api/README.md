# API — 내부 모듈 정리 (외부 API 없음)

P-Solitaire 는 **외부 서버·네트워크·API 를 쓰지 않는다**(전부 로컬, 표준 라이브러리만).

- 입출력: 화면(SwiftUI/Canvas 또는 동결 파이썬 tkinter)과 로컬 JSON 하나.
- 현재 네이티브: `~/.psolitaire-nat.json` (설정·전적·진행 중 판 스냅숏) · 동결 파이썬: `~/.solitaire_python_stats.json`.
- 따라서 `ENDPOINTS.md` 는 두지 않는다. 서버를 붙이는 일이 생기면 이 폴더에 엔드포인트 문서를 만든다.

## 0. Swift 네이티브 API (현재)

- **규칙**: `native/Sources/PSolitaireKit/` — `Card`, `BaseGame`/`Klondike`/`FreeCell`/`Spider`, `makeGame`, `GameSnapshot`.
  - `exportSnapshot()` / `restoreSnapshot(_:)` — 진행 중인 판 저장·복원(스파이더 파운데이션 포함)
  - `canRedo` / `redo()` — 새 이동 시 redo 무효화
  - 나머지는 파이썬 `solitaire_core.py`와 같은 역할(`pickWhole`, `groupRun`, `hint`, `autocompleteStep`, `undo` 등)
- **풀리는 스파이더 판**: `SpiderWinnable` (`SpiderWinnable.swift`)
  - `SpiderWinnable.makeDeal(sourceSeed:suits:timeLimit:nodeLimit:)` — 1무늬 판을 풀어 해답을 얻고 무늬를 다시 칠해 `SpiderWinnableDeal`(배분 + `[SpiderSolutionMove]` 해답)을 만든다. 실제 규칙으로 해답을 다시 두어 이김을 확인한 뒤에만 돌려준다
  - `SpiderWinnable.makeDeal(suits:startingSeed:attempts:timeLimit:nodeLimit:)` — 실패하면 다음 번호로 재시도
  - `Spider.applyDeal(_:)` — 배분을 적용하고 `startLayout`에 시작 배치를 기억한다
  - `Spider.startLayout` / `SpiderStartLayout` — 다시 시작·이어하기 때 같은 배분을 유지한다(저장 파일 `spiderStart`)
  - 앱 설정 키 `spider_winnable`(기본 `true`). 만드는 동안 `GameController.preparingDeal`이 켜져 화면이 안내로 덮인다
- **화면/상태**: `native/Sources/PSolitaire/GameController.swift` — 게임 상태, 저장/복원, 줌, 사운드/애니메이션, 대화상자 요청, 통계 집계(`played`는 첫 실제 이동 때만)
- **그리기/배치**: `Board.swift`(1x 논리 좌표·히트테스트), `Drawing.swift`(카드/무늬/뒷면), `Theme.swift`(치수·테마), `Views.swift`(`BoardCanvas`·`GameControlBar`)
  - `drawCardFaceShadow`는 **집은/나는/우승 카드에만** 쓴다. 그림자는 카드 실루엣에만 주고(앞면 전체를 넣으면 핍마다 그림자가 생긴다), 쉬는 카드는 `drawCardFace`로 평평하게 그린다(집지 않았는데 집은 것처럼 보이던 둥근 그늘 제거).
- **배경음**: `MusicPlayer.swift` — `musicTracks`(5곡), `MusicRepeatMode`, `apply(on:trackID:repeatMode:volume:)`, `url(for:)`. 설정은 `GameController`가 `music` 키로 저장·정규화하고, `--selftest`/`--shots`에서는 무음.
- **창/메뉴**: `PSolitaireApp.swift`(WindowGroup·Settings·전적 Window·메뉴/단축키), `SettingsViews.swift`(테마·소리·게임·자동·데이터)
- **앱 정체성(v0.5.0)**: `~/Applications/P-Solitaire.app` · 번들 ID `com.borasarang.P-Solitaire` · 실행 파일 `P-Solitaire` · 로그 `~/Library/Logs/P-Solitaire.log`
- **검증**: `swift test`(Kit) · `swift run PSolitaire --selftest`(창 없이 UI 계층) · `--shots`(오프스크린 PNG)

## 1. `solitaire_core.py` — 게임 규칙(GUI 없음)

```python
from solitaire_core import make_game, GAME_KEYS, GAME_CLASSES

game = make_game("spider", seed=123, suits=1)   # kind: klondike | freecell | spider
game.deal(seed)          # 카드 배분(시드 고정 → 같은 판 재현)
game.move(src, index, dst)          # {"ok": bool, "points": int, "reason": str, ...}
game.pick(src, index)               # 집을 수 있는 묶음 — 열 맨 위까지 이어질 때만(아니면 None)
game.run_from(src, index, same_suit=True)   # "어디까지 이어지는지" 계산(스파이더는 same_suit=True)
game.run_from(src, index, rank_only=True)   # 숫자만 내림차순(스파이더 "무늬 상관없이" 설정)
game.group_run(src, index)          # 이 게임의 묶음 규칙으로 이어지는 카드(스파이더가 오버라이드)
game.pick_whole(src, index)         # 태블로에서 집을 수 있는 묶음(맨 위까지 이어져야 함)
game.group_limit_note(src, index)   # 못 집을 때 이유 한 줄(없으면 None) — 화면이 상태줄에 보여 준다
game.can_drop(cards, dst)           # 놓을 수 있는지(드래그 중 표시용)
game.draw_from_stock()              # 스톡 넘기기/재활용, 스파이더는 딜(빈 열이면 거부)
game.flip_top(pile)                 # 뒤집힌 카드 공개
game.auto_move(src, index)          # 더블클릭 자동 이동
game.hint()                         # {"type": "move"|"draw"|"recycle", "src", "index", "dst"}
game.autocomplete_step()            # 자동 완성 한 수
game.undo() / game.can_undo         # 실행 취소
game.score, game.moves, game.seed   # 점수·이동 수·시드
game.columns, game.foundations_count, game.has_stock, game.has_waste, game.freecells
game.sorted_cards(), game.cards_remaining(), game.is_won(), game.can_auto_complete()
```

- `_snapshot()` / `_restore()` 는 실행 취소 스택 내부용(직접 쓸 일 없음). `move()` 가 돌려주는 `points`·`reason`·`sets` 로 화면이 로그·안내를 만든다.
- **묶음 계산은 `run_from()` 한 곳에 있다**: `run_from()` 은 "`index` 부터 규칙이 이어지는 만큼"(끊기면 거기까지, 최소 1장)을 돌려준다. `group_run()` 이 게임별 규칙(스파이더는 같은 무늬 / `suit_free` 면 숫자만)을 얹고, `pick()` 은 `pick_whole()` 을 거친다.
  - 클론다이크·프리셀: 내림차순 + 색 교대 · 스파이더: 내림차순 + 같은 무늬
  - `rank_only=True`: 숫자만 내림차순(무늬·색을 따지지 않는다) — 스파이더 `suit_free` 설정에서만 쓴다
  - `move(src, index, dst)` 는 `index`부터 `len(run)`장만 떼어낸다(아래에 남는 카드는 그대로).
- **집을 수 있는 조건은 `pick_whole()`**: `index` 부터 이어지는 묶음이 **그 열의 맨 위 카드까지 닿을 때만** 집힌다. 중간 카드만 쏙 빼내는 것은 MS 규칙에 없다 — 덮여 있는 카드를 누르면 집히지 않고 이유만 안내한다(스톡 배분으로 끊긴 스파이더 열·무작위 배분 프리셀에서 실제로 생기던 버그).
- `group_limit_note(ref, index)`: 지금 집을 수 없을 때 **왜 못 집는지** 한 줄을 돌려준다 — 묶음 규칙(무늬·색)에서 끊기면 `GROUP_LIMIT_TEXT`, 위 카드가 아예 이어지지 않으면 `BURIED_TEXT`(스파이더는 자기 문구로 덮어씀). 규칙이 바뀌어도 화면 문구는 이 함수 하나만 고치면 된다.

| 클래스 | 게임 | 특징 |
|---|---|---|
| `BaseGame` | 공통 뼈대 | 점수·이동·undo 스택·시드·요약. 기본 동작은 no-op |
| `Klondike` | 클론다이크 | 7열·스톡/웨이스트(1·3장)·색 교대 |
| `FreeCell` | 프리셀 | 8열·프리셀 4칸·슈퍼무브·스톡 없음 |
| `Spider` | 스파이더 | 10열·104장·난이도(1·2·4무늬)·세트 자동 수거·묶음 규칙 옵션(`suit_free`) |

- `Spider(seed, suits=1, suit_free=False)` · `Spider.set_suit_free(on)` — 규칙만 바꾸고 판·점수·undo 는 그대로. 힌트·더블클릭 자동 이동도 같은 `pick()` 을 쓰므로 함께 바뀐다.
- `make_game("spider", suits=2, suit_free=True)` 처럼 넘기면 되고, 다른 게임에는 `suit_free` 를 넘겨도 무시된다.

- 게임 이름·순서는 `GAME_KEYS`(`("klondike", "freecell", "spider")`) 와 `GAME_CLASSES` 로 관리한다.
- 화면은 이 API만 쓴다 — 새 게임을 추가하려면 `BaseGame` 하위 클래스를 만들고 `GAME_CLASSES` 에 등록한다.

## 2. `debuglog.py` — 로거

`debuglog.info/error/perf/cache(기능, 문구[, 오류코드])` · `debuglog.lines()` · `debuglog.error_count()` ·
`debuglog.user_message(코드)`(→ `error_message_ko.json`). 규약: `[INFO]` `[PERF]` `[CACHE]` `[ERROR]`.

## 3. `solitaire.py` — 화면

`SolitaireApp(root, variant=None)` 가 전부 담당한다(그리기·입력·애니메이션·디버그 패널).
게임별 차이는 `STYLE` 표(간격·이름)와 `top_refs()`(위 줄 자리)로만 표현한다.

| 설정 | 키 | 기본값 |
|---|---|---|
| `settings["variant"]` | `klondike` / `freecell` / `spider` | 마지막에 하던 게임 |
| `settings["draw_count"]` | 1 / 3 (클론다이크) | 3 |
| `settings["spider_suits"]` | 1 / 2 / 4 | 1 |
| `settings["spider_group"]` | `same_suit`(MS 규칙) / `any_suit`(무늬 상관없이) | `same_suit` |
| `settings["auto"]` | `double` · `collect` · `finish` | `True` · `True` · `False` |
| `settings["theme"]` | `background`(green·blue·dark) · `back`(lattice·rays·dots) | `green` · `lattice` |
| `settings["zoom"]` | 100 / 125 / 150 / 175 / 200 (%) | 100 |

- 자동 기능: `auto_on(key)` · `set_auto(key, on)` · `toggle_auto_all()` · `auto_collect_foundations()` · `maybe_auto_finish()`
- 상태줄 안내: `set_hint(문구, 초=3.0)` 이 **앞선 안내의 되돌리기 예약(`hint_after`)을 취소하고** 새 문구를 띄운다 → 가장 최근 안내가 정해진 시간만큼 유지된다(취소하지 않으면 앞선 타이머가 나중 문구를 일찍 지운다). `restore_hint()` 는 기본 단축키 안내로 되돌리고, `cancel_animations()`(새 게임·다시 시작·게임 전환)도 예약을 정리하고 기본 안내로 되돌린다
- 스파이더 묶음 규칙: `spider_suit_free()` · `on_spider_group()`(메뉴) — 설정을 저장하고, 진행 중인 판은 `Spider.set_suit_free()` 로 **규칙만** 바꾼다(판·점수 그대로)
- 테마: `apply_theme()` · `set_theme(bg_key, back_key, save=True)` — 저장하지 않는 모드(캡처용)도 있다
- 확대: `zoom_items(tag="all")`(1x 로 그린 항목을 배율만큼 키우고 선 두께도 배율 적용) · `set_zoom(pct, save=True)`(화면에 안 들어가면 `False`) · `zoom_step(±1)` · `fit_zoom(pct)`(화면에 들어가는 최대 배율) · `logical(x, y)`(픽셀 → 1x 좌표). 그리기·판정은 **항상 1x 논리 좌표**이고 배율은 화면에 낼 때만 곱한다
- 설정 정규화: `normalize_settings(stats)` 가 알 수 없는 값을 기본값으로 되돌린다(옛 파일·손상 대비)
- 환경 변수 `SOLITAIRE_GAME` · `SOLITAIRE_DEMO` · `SOLITAIRE_HOLD` · `SOLITAIRE_SHOT` · `SOLITAIRE_PS` ·
  `SOLITAIRE_BG` · `SOLITAIRE_BACK` · `SOLITAIRE_ZOOM` · `SOLITAIRE_POS` · `SOLITAIRE_HEADLESS` 는 확인용이다(README 참조).
