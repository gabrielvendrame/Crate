# Binari sidecar

`yt-dlp`, `ffmpeg` e `ffprobe` vivono qui e vengono copiati in `Crate.app/Contents/Resources/Tools/`.

Non sono versionati: si scaricano con

```bash
./Scripts/fetch-tools.sh
```

A runtime l'app preferisce la copia in `~/Library/Application Support/Crate/Tools/`, aggiornata
dal comando "Aggiorna yt-dlp", e ricade su questi solo se quella manca.
