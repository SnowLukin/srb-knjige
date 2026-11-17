#!/bin/bash
# Собирает Knjige.app и упаковывает в build/Knjige.dmg (окно с приложением и ярлыком «Программы»).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build_app.sh

STAGE="build/dmg"
rm -rf "$STAGE" build/Knjige.dmg
mkdir -p "$STAGE"
cp -R build/Knjige.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Knjige" -srcfolder "$STAGE" -ov -format UDZO build/Knjige.dmg >/dev/null
rm -rf "$STAGE"
echo "Готово: build/Knjige.dmg"
