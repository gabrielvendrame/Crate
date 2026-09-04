#!/bin/bash
#
# Scarica i binari sidecar in Resources/Tools/, da dove finiscono in
# Crate.app/Contents/Resources/Tools/.
#
#   ./Scripts/fetch-tools.sh          scarica solo ciò che manca
#   ./Scripts/fetch-tools.sh --force  riscarica tutto
#
# ffprobe non serve: durata, sample rate e numero di canali li legge AVFoundation.
#
# yt-dlp viene preso nella variante "onedir" (yt-dlp_macos.zip) e non come binario singolo.
# Il binario singolo è un pacchetto PyInstaller onefile che si riespande in una cartella
# temporanea a ogni lancio: macOS ne riscansiona il contenuto ogni volta e l'avvio costa ~13
# secondi, misurati. La onedir paga quella scansione una volta sola, alla prima esecuzione, e poi
# parte in ~0,4 s. Pesa di più su disco, ma su un'app locale il disco non è la risorsa scarsa.

set -euo pipefail

cd "$(dirname "$0")/.."
TOOLS="Resources/Tools"
mkdir -p "$TOOLS"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip"
# Build statica nativa arm64. evermeet.cx pubblica solo x86_64, che girerebbe in Rosetta.
FFMPEG_URL="https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"

YTDLP_BIN="$TOOLS/yt-dlp/yt-dlp_macos"

if [[ $FORCE -eq 1 || ! -x "$YTDLP_BIN" ]]; then
    echo "› yt-dlp…"
    TMP="$(mktemp -d)"
    curl -fL -s "$YTDLP_URL" -o "$TMP/yt-dlp.zip"
    unzip -qo "$TMP/yt-dlp.zip" -d "$TMP/unpacked"
    rm -rf "$TOOLS/yt-dlp"
    mkdir -p "$TOOLS/yt-dlp"
    # L'archivio contiene l'eseguibile accanto alla cartella _internal: vanno tenuti insieme.
    cp -R "$TMP/unpacked/." "$TOOLS/yt-dlp/"
    rm -rf "$TMP"
    chmod +x "$YTDLP_BIN"
    xattr -cr "$TOOLS/yt-dlp" 2>/dev/null || true
else
    echo "› yt-dlp già presente"
fi

if [[ $FORCE -eq 1 || ! -x "$TOOLS/ffmpeg" ]]; then
    echo "› ffmpeg…"
    TMP="$(mktemp -d)"
    curl -fL -s "$FFMPEG_URL" -o "$TMP/ffmpeg.zip"
    unzip -qo "$TMP/ffmpeg.zip" -d "$TMP"
    FOUND="$(find "$TMP" -name ffmpeg -type f -print -quit)"
    [[ -n "$FOUND" ]] || { echo "ffmpeg non trovato nell'archivio" >&2; exit 1; }
    mv "$FOUND" "$TOOLS/ffmpeg"
    rm -rf "$TMP"
    chmod +x "$TOOLS/ffmpeg"
    xattr -c "$TOOLS/ffmpeg" 2>/dev/null || true
else
    echo "› ffmpeg già presente"
fi

echo
echo "yt-dlp  $("$YTDLP_BIN" --version 2>&1 | tail -1)"
"$TOOLS/ffmpeg" -version 2>&1 | head -1
echo "ingombro: $(du -sh "$TOOLS" | cut -f1)"
