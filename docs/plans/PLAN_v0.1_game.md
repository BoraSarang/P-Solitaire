# PLAN_v0.1_game.md
> 생성일: 2026-10-18 | 플랫폼: game | 작성자: OpenCode

## 1. 목표 (1줄)
마이크로소프트 클래식 솔리테어(클론다이크)를 **추가 설치 없이** 돌아가는 Python 게임으로 만든다.

## 2. 범위
- 플랫폼: game (macOS 데스크톱에서 실행)
- 기술 스택: **Python 3 + tkinter(표준 라이브러리만)** — "설치 없이 실행"이 요구사항이라 창·그리기·입력을 표준 라이브러리로 모두 처리한다. 카드 그림은 이미지·폰트 글리프 없이 캔버스 도형으로 직접 그린다
- design_profile: **custom** (클래식 MS 솔리테어 룩 — 초록 테이블·카드 도형)
- **포함**
  1. 규칙 전체 — 배분(시드 결정적), 태블로(색 교대·내림차순·빈 줄은 K만), 파운데이션(A→K), 스톡/웨이스트(1장·3장 모드), 웨이스트 재활용, 뒤집기
  2. 조작 — 끌어놓기(여러 장 묶음·놓을 자리 표시), 더블클릭 자동 올리기, 클릭 공개, 힌트(깜빡임), 자동 완성, 실행 취소(무제한)
  3. 점수 — MS 표준 + 우승 보너스(700,000 ÷ 걸린 초), 시간·이동·모드 표시, 전적 저장(`~/.solitaire_python_stats.json`)
  4. 우승 연출(카드 쏟아지기, Esc로 중단)과 결과 대화상자
  5. 코어/화면 분리 — `solitaire_core.py`(헤드리스 테스트 가능) + `solitaire.py`(tkinter)
  6. 자동 테스트 44개(코어 19 + UI 25), 창을 띄우지 않는 UI 검증
  7. 로거(DebugLogger 규약)·오류 코드(`E-GAME-…`)·디버그 패널(`Cmd+Shift+D`)
- **제외**
  - 카드 이미지·사운드 파일, 배포용 `.app` 번들, 온라인 랭킹·통계 업로드
  - 다른 변형(프리셀·스파이더·피라미드)

## 3. 문서 위치
- PLAN: 본 문서 / TODO: `docs/TODO.md` T-001~T-005
- DESIGN: `docs/DESIGN.md` (색·폰트·간격·카드 도형·배치 계산)
- API: 해당 없음 → `docs/api/README.md`

## 4. 성능 예산
- budgets.json `game` 기본값. 목표 fps 60 — 고정 프레임 루프가 아니라 이벤트·애니메이션 기반
- 다시 그리기(카드 52장 전부) **60ms 이하** — 초과 시 `[PERF]` 로그, 디버그 패널에서 상시 확인
- 메모리 **≤300MB**(디버그 패널의 최대 RSS)
- 우승 연출은 45ms 간격(≈22fps)으로 의도적으로 느리게 둔다(클래식 연출)
- 테스트 예산: smoke ≤1s, unit ≤60s

## 5. 에러 코드
- `E-GAME-STORE-0001` 전적 읽기 실패 / `E-GAME-STORE-0002` 전적 저장 실패
- `E-GAME-ASSET-0001` `error_message_ko.json` 읽기 실패
- `E-GAME-INPUT-0001` 조작 상태 어긋남(예비)
- 이후 신규는 `E-GAME-{CATEGORY}-{NUM4}` (공통 목록에 game 접두가 없어 예외 — `AGENTS.local.md` §4)

## 6. 빌드 & 검증 계획
- `./build_and_run.sh build game` → `py_compile` + `error_message_ko.json` 형식 검사
- `./build_and_run.sh test game smoke|unit|full` → 코어 19 / 코어+UI 25 / + Tk 버전 점검
- UI 테스트는 `root.withdraw()` 로 창을 숨긴 채 마우스·키 이벤트를 주입한다(**사용자 화면 간섭 없음**)
- 디버그 패널 검증 항목: 다시 그리기 ms, 캔버스 항목 수, 메모리, **ERROR 0건**
- 실기기 확인(사용자): 카드 앞면(9·10 핍과 코너 숫자), 우승 연출, 전적 보기

## 7. 예외 규칙 (있으면)
- 공통 macOS 규칙의 SwiftUI/`xcodebuild` 대신 **Python/tkinter** 를 쓴다 — 근거는 `AGENTS.local.md` §1·§4
- 게임 플랫폼 규칙의 "엔진 CLI"는 파이썬 인터프리터 실행으로 대체한다(`build_and_run.sh`)
- 사용자가 맥을 쓰는 중에는 창을 띄우는 검증·화면 캡처를 하지 않는다 [HARD 사용자 공존]
