#!/bin/sh
# build_native.sh — Swift 네이티브 P-Solitaire: 검사·PNG 렌더·앱 번들 조립.
#
#   ./build_native.sh test            코어 검사(swift test) + 화면 자체 검사(--selftest)
#   ./build_native.sh shots [폴더]     게임·테마별 PNG 를 창 없이 렌더(눈으로 확인용)
#   ./build_native.sh package         릴리스 빌드 → ~/Applications/P-Solitaire.app
#   ./build_native.sh run             설치된 앱 실행(창이 뜬다 — 사용자 확인 뒤에만)
#
# 동결한 파이썬 앱은 ~/.Trash/P-Solitaire.app에 보존되어 있고, 이 스크립트는 건드리지 않는다.
# 설정·전적도 별도 파일(~/.psolitaire-nat.json)을 써서 파이썬 기록과 섞이지 않는다.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE" || exit 1

APP_NAME="P-Solitaire"
APP_ID="com.borasarang.P-Solitaire"
APP_VERSION="0.7.0"
APP_BUILD="9"
APP_DEST="$HOME/Applications/$APP_NAME.app"
SHOTS_DIR="$HERE/shots"
ICON_SRC="$HERE/AppIcon.icns"

usage() {
    echo "사용법: ./build_native.sh {test|shots|package|run} [폴더]" >&2
    exit 2
}

do_test() {
    swift test
    swift run PSolitaire --selftest
}

do_shots() {
    dir=${1:-$SHOTS_DIR}
    mkdir -p "$dir"
    swift run PSolitaire --shots "$dir"
    echo "[SHOTS] $dir"
}

do_package() {
    swift build -c release --product PSolitaire
    bin=$(swift build -c release --product PSolitaire --show-bin-path)/PSolitaire
    if [ ! -x "$bin" ]; then
        echo "[PACKAGE] 실행 파일을 찾지 못했습니다: $bin" >&2
        exit 1
    fi
    if pgrep -f "$APP_DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        echo "[PACKAGE] $APP_NAME 이(가) 실행 중입니다. 종료한 뒤 다시 실행하세요." >&2
        exit 1
    fi

    rm -rf "$APP_DEST"
    mkdir -p "$APP_DEST/Contents/MacOS" "$APP_DEST/Contents/Resources"
    cp "$bin" "$APP_DEST/Contents/MacOS/$APP_NAME"

    cat > "$APP_DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>$APP_NAME</string>
	<key>CFBundleDisplayName</key>
	<string>$APP_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>$APP_ID</string>
	<key>CFBundleExecutable</key>
	<string>$APP_NAME</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$APP_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$APP_BUILD</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleDevelopmentRegion</key>
	<string>ko</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.card-games</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>LSMultipleInstancesProhibited</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>개인용 로컬 게임 · Swift + SwiftUI · 외부 통신 없음</string>
</dict>
</plist>
PLIST

    if [ -f "$ICON_SRC" ]; then
        cp "$ICON_SRC" "$APP_DEST/Contents/Resources/AppIcon.icns"
    fi

    # 배경음 5곡과 출처(CC BY 4.0). MusicPlayer 는 Contents/Resources/Music 에서 찾는다.
    if [ -d "$HERE/Resources/Music" ]; then
        mkdir -p "$APP_DEST/Contents/Resources/Music"
        cp "$HERE/Resources/Music/"*.m4a "$APP_DEST/Contents/Resources/Music/"
        cp "$HERE/Resources/Music/CREDITS.md" "$APP_DEST/Contents/Resources/Music/"
    fi

    # 중첩 코드가 없는 단일 실행 파일 번들이라 --deep 없이 서명한다.
    codesign --force --sign - "$APP_DEST" >/dev/null 2>&1 || true
    codesign --verify --strict "$APP_DEST" || echo "[PACKAGE] 서명 확인 실패(그래도 실행은 됩니다)" >&2

    size=$(du -sh "$APP_DEST" | cut -f1)
    echo "[PACKAGE] $APP_DEST ($size)"
    echo "[PACKAGE] 버전 $APP_VERSION($APP_BUILD) · 실행 파일 $(ls -lh "$APP_DEST/Contents/MacOS/$APP_NAME" | awk '{print $5}')"
    echo "[PACKAGE] 외부 의존:"
    otool -L "$APP_DEST/Contents/MacOS/$APP_NAME" | tail -n +2 | sed 's/^/    /'
}

do_run() {
    if [ ! -d "$APP_DEST" ]; then
        echo "[RUN] 먼저 ./build_native.sh package 를 실행하세요." >&2
        exit 1
    fi
    open "$APP_DEST"
    echo "[RUN] $APP_DEST 실행"
}

[ $# -ge 1 ] || usage
cmd=$1
shift

case "$cmd" in
    test)    do_test ;;
    shots)   do_shots "$@" ;;
    package) do_package ;;
    run)     do_run ;;
    *)       usage ;;
esac
