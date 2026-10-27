# 배경음 출처 (Music credits)

이 폴더의 5곡은 모두 **Kevin MacLeod (incompetech.com)** 의 곡으로,
**Creative Commons Attribution 4.0 International (CC BY 4.0)** 라이선스로 제공됩니다.

- 라이선스: <https://creativecommons.org/licenses/by/4.0/>
- 원본·라이선스 안내: <https://incompetech.com/music/royalty-free/>
- 가공: 원본 mp3(160~320kbps)를 **96kbps AAC(m4a)** 로 변환해 앱 번들 크기를 줄였습니다.
  멜로디·구성은 바꾸지 않았습니다.

| 파일 | 곡 | 작곡·연주 | 원본 |
|---|---|---|---|
| `Lobby Time.m4a` | Lobby Time | Kevin MacLeod | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Lobby%20Time.mp3> |
| `Backbay Lounge.m4a` | Backbay Lounge | Kevin MacLeod | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Backbay%20Lounge.mp3> |
| `BossaBossa.m4a` | BossaBossa | Kevin MacLeod | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/BossaBossa.mp3> |
| `Night in Venice.m4a` | Night in Venice | Kevin MacLeod | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Night%20in%20Venice.mp3> |
| `Late Night Radio.m4a` | Late Night Radio | Kevin MacLeod | <https://incompetech.com/music/royalty-free/mp3-royaltyfree/Late%20Night%20Radio.mp3> |

## 표기 문구 (앱 정보·설정에 그대로 쓴다)

> 배경음: Kevin MacLeod (incompetech.com) · CC BY 4.0

## 앱에 포함할 때

- `build_native.sh package` 가 이 폴더를 `P-Solitaire.app/Contents/Resources/Music/` 로 복사합니다.
- 곡을 바꾸면 `native/Sources/PSolitaire/MusicPlayer.swift` 의 `musicTracks` 목록과
  이 파일의 표를 함께 고칩니다.
- CC BY 4.0 은 저작자 표시를 요구합니다. 앱 정보(정보 메뉴)·설정 소리 섹션·이 문서 중
  한 곳이라도 표시가 빠지면 라이선스 위반입니다.
