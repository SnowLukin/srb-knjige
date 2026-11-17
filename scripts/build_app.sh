#!/bin/bash
# Собирает Knjige.app в папку build/ и (по желанию) копирует в /Applications.
#   ./scripts/build_app.sh            — собрать
#   ./scripts/build_app.sh --install  — собрать и положить в /Applications
set -euo pipefail
VERSION="${VERSION:-0.1}"
cd "$(dirname "$0")/.."

swift build -c release

BIN="$(swift build -c release --show-bin-path)/Knjige"
APP="build/Knjige.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Knjige"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Knjige</string>
    <key>CFBundleDisplayName</key><string>Knjige</string>
    <key>CFBundleIdentifier</key><string>com.snowlukin.knjige</string>
    <key>CFBundleExecutable</key><string>Knjige</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
</dict>
</plist>
PLIST

# Локальная подпись, чтобы macOS не ругалась на «повреждённое» приложение.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Готово: $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/Knjige.app"
    cp -R "$APP" /Applications/
    echo "Скопировано в /Applications/Knjige.app"
fi
