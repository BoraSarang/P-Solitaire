# docs — 문서 지도 (P-Solitaire)

> 정리 기준 **2026-10-27**. 여기 있는 문서만 보면 프로젝트의 지금 상태를 알 수 있다.
> **활성 트랙은 Swift 네이티브(`native/`)뿐**이다. 파이썬 판은 v0.2.6(26)으로 동결되어 `archive/python/`에 있다.

| 문서 | 언제 보나 | 담긴 것 |
|---|---|---|
| [`TODO.md`](TODO.md) | **세션 시작** | 남은 일 한 곳(⓪ 시작점 · ① 진행 중 · ② 완료 · ③ Perf · ④ 보류) — 다음 세션은 이것만 보면 된다 |
| [`plans/NATIVE_REVIEW_2026-10-20.md`](plans/NATIVE_REVIEW_2026-10-20.md) | **네이티브 개선 이력** | 점검 시점의 P0~P2 제안 + v0.4.0~v0.5.1 구현 결과 |
| [`CHANGELOG.md`](CHANGELOG.md) | 지금까지 무엇이 바뀌었나 | 버전별 변경 기록(v0.1 → v0.2.6 파이썬 동결 → **v0.7.0 네이티브**) |
| [`DESIGN.md`](DESIGN.md) | 화면·토큰을 고칠 때 | 색·폰트·간격 토큰, 카드 도형, 화면 구성(컨트롤 바·창 620), 앱 번들/메뉴 막대, 접근성 |
| [`ASSETS.md`](ASSETS.md) | 외부 리소스를 쓸 때 | 배경음 5곡의 출처·라이선스(CC BY 4.0)·저작자 표시, 아이콘·도형의 자체 제작 여부 |
| [`api/README.md`](api/README.md) | 코어·화면을 고칠 때 | 파이썬 API 요약(동결) + Swift 네이티브 API 지도 — 상세는 `native/Sources/PSolitaireKit` 소스 |
| [`plans/`](plans) | 그때 왜 그렇게 했나 | 작업 계획서(PLAN) — v0.1, v0.2, v0.2.1, v0.2.3, v0.2.4, v0.2.5, v0.2.6, native v0.3, **native v0.6**, 네이티브 리뷰 |
| [`images/`](images) · [`images/archive/`](images/archive) | 화면을 확인할 때 | 파이썬 캡처 5장 · 네이티브 실제 창·전적 창(2026-10-20) · 옛 판 캡처. 네이티브 최신 46장은 `native/shots/` |

- 프로젝트 규칙(플랫폼·스택·금지 사항)은 저장소 루트 `AGENTS.local.md`, 실행·조작 안내는 루트 `README.md`.
- 세션 기록은 `.agent/`(로컬 전용 — 커밋하지 않는다).
- 저장소는 <https://github.com/BoraSarang/P-Solitaire> — `main`이 기준이고 작업은 브랜치 + PR로 합친다. `archive/python`·빌드 산출물은 올리지 않는다.
- 캡처 갱신: 네이티브는 `./build_native.sh shots`(창 없이 46장) 또는 사용자 승인 후 `open -g` + `screencapture -x -o -l <창ID>`. **사용 중에는 클릭/키 입력을 합성하지 않는다.** 파이썬은 `SOLITAIRE_POS=x,y`(동결).
