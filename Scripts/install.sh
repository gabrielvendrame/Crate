#!/bin/bash
# Compila Crate in Release e la installa in /Applications.
#
# Perché Release e non la build che Xcode lascia in DerivedData/Debug: quella porta dentro
# `Crate.debug.dylib` e `__preview.dylib`, cioè l'infrastruttura di sviluppo di Xcode, ed è
# compilata senza ottimizzazioni. Per l'app che si usa davvero — e ancora di più per quella che
# finisce su un altro Mac — serve la Release.
#
#   ./Scripts/install.sh          compila e installa in /Applications
#   ./Scripts/install.sh --zip    compila e prepara Crate.zip da portare su un altro Mac
#
set -euo pipefail

cd "$(dirname "$0")/.."
mode="${1:-install}"

if [[ ! -x Resources/Tools/yt-dlp/yt-dlp_macos || ! -x Resources/Tools/ffmpeg ]]; then
    echo "Mancano i sidecar in Resources/Tools/. Esegui prima ./Scripts/fetch-tools.sh" >&2
    exit 1
fi

[[ -d Crate.xcodeproj ]] || xcodegen generate

echo "Compilo in Release…"
xcodebuild -project Crate.xcodeproj -scheme Crate -configuration Release build \
    | grep -E "error:|warning: .*(deprecat|unused)|BUILD" || true

built=$(xcodebuild -project Crate.xcodeproj -scheme Crate -configuration Release \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')
app="$built/Crate.app"
[[ -d "$app" ]] || { echo "Build non riuscita: $app non esiste" >&2; exit 1; }

if [[ "$mode" == "--zip" ]]; then
    # `ditto -c -k --keepParent` è l'unico modo di comprimere un .app conservando permessi di
    # esecuzione e attributi estesi: uno zip fatto altrimenti arriva con i sidecar non
    # eseguibili e la firma rotta.
    out="$PWD/Crate.zip"
    rm -f "$out"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$out"
    echo
    echo "Pronto: $out ($(du -h "$out" | cut -f1))"
    echo "Sull'altro Mac, dopo averlo scompattato in /Applications:"
    echo "    xattr -dr com.apple.quarantine /Applications/Crate.app"
    exit 0
fi

if pgrep -x Crate >/dev/null; then
    echo "Crate è aperta: la chiudo."
    osascript -e 'quit app "Crate"' || true
    for _ in $(seq 20); do pgrep -x Crate >/dev/null || break; sleep 0.5; done
fi

rm -rf /Applications/Crate.app
ditto "$app" /Applications/Crate.app
echo "Installata: /Applications/Crate.app ($(du -sh /Applications/Crate.app | cut -f1))"
