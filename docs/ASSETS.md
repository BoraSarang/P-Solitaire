# ASSETS — 외부 리소스와 라이선스 (P-Solitaire)

> 기준 2026-10-27 · Swift 네이티브 **v0.6.0**.
> 카드·탁자·아이콘은 직접 그리거나 자체 제작했고, **배경음 5곡만 외부 리소스**다.
> 외부 리소스를 추가·교체하면 이 표와 `native/Resources/Music/CREDITS.md`를 함께 고친다.

## 1. 배경음 (v0.6.0)

| 파일 | 곡 | 작곡·연주 | 길이 | 형식 | 크기 | 원본 |
|---|---|---|---|---|---|---|
| `Lobby Time.m4a` | Lobby Time | Kevin MacLeod | 3:13 | AAC 96kbps · 44.1kHz | 2.4MB | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Lobby%20Time.mp3> |
| `Backbay Lounge.m4a` | Backbay Lounge | Kevin MacLeod | 4:27 | AAC 96kbps · 44.1kHz | 3.3MB | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Backbay%20Lounge.mp3> |
| `BossaBossa.m4a` | BossaBossa | Kevin MacLeod | 2:47 | AAC 96kbps · 44.1kHz | 2.1MB | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/BossaBossa.mp3> |
| `Night in Venice.m4a` | Night in Venice | Kevin MacLeod | 3:38 | AAC 96kbps · 44.1kHz | 2.6MB | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Night%20in%20Venice.mp3> |
| `Late Night Radio.m4a` | Late Night Radio | Kevin MacLeod | 4:24 | AAC 96kbps · 44.1kHz | 3.2MB | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Late%20Night%20Radio.mp3> |

- 합계 **12.9MB** (13,511,650 bytes). 원본 mp3(160~320kbps)를 **96kbps AAC(m4a)** 로 변환해 번들 크기를 줄였다. 멜로디·구성은 바꾸지 않았다.
- 저장 위치: `native/Resources/Music/` → 패키징 시 `P-Solitaire.app/Contents/Resources/Music/`.
- 재생: `native/Sources/PSolitaire/MusicPlayer.swift` (`AVAudioPlayer`, 외부 패키지 없음).

### 라이선스 · 저작자 표시 (CC BY 4.0)

이 5곡은 **Kevin MacLeod (incompetech.com)** 의 곡이며 **Creative Commons Attribution 4.0 International (CC BY 4.0)** 로 제공된다.

- 라이선스 원문: <https://creativecommons.org/licenses/by/4.0/>
- 원본·라이선스 안내: <https://incompetech.com/music/royalty-free/>
- 앱에 표시하는 문구(정보 메뉴·설정 **소리** 섹션·`CREDITS.md`):

> 배경음: Kevin MacLeod (incompetech.com) · CC BY 4.0

CC BY 4.0은 **저작자 표시**를 요구한다. 앱 정보·설정·`native/Resources/Music/CREDITS.md`·이 문서 중 표시가 빠지면 라이선스 위반이다. 곡을 바꾸면 `musicTracks` 목록·`CREDITS.md`·이 표를 함께 고친다.

## 2. 자체 제작 리소스

| 리소스 | 위치 | 설명 |
|---|---|---|
| 앱 아이콘 | `native/AppIcon.icns` | 직접 제작. `build_native.sh package` 가 `Contents/Resources/AppIcon.icns` 로 복사 |
| 카드 앞면·뒷면·무늬 | `native/Sources/PSolitaire/Drawing.swift` | 이미지 파일 없이 `Canvas` 도형으로 그린다 |
| 탁자·테마 색 | `native/Sources/PSolitaire/Theme.swift` | 초록·파랑·어두운 탁자 × 카드 뒷면 3종 |
| 시스템 효과음 | macOS 기본 사운드 | `NSSound(named:)` 로 재생(파일을 번들에 넣지 않는다) |

## 3. 외부 리소스를 추가할 때

1. 라이선스가 **재배포·상업 이용·개작**을 허용하는지 확인한다(CC BY·CC0·퍼블릭 도메인 우선).
2. 저작자 표시가 필요하면 앱 정보·설정·`CREDITS.md`·이 문서에 넣는다.
3. 오디오는 96kbps AAC(m4a)로 변환하고, 파일 크기와 길이를 이 표에 적는다.
4. `swift test` · `--selftest`(파일 존재·설정) · `--shots` 를 다시 돌리고, 패키징 후 `Contents/Resources`에 실제로 들어갔는지 확인한다.
