# Crate — contesto di progetto

App **macOS nativa** per preparare DJ set **in vinile**. Gabriel trova i brani su YouTube, li
ascolta, decide dove attaccarli e come legano fra loro; questa app chiude quel ciclo in un unico
posto: scarica l'audio da un link, lo analizza, lo archivia con metadati e foto dell'etichetta del
vinile, e permette di costruire scalette provando le transizioni su due deck stile rekordbox, con
cue point annotati e note di passaggio fra un pezzo e l'altro.

**È un'app puramente locale.** Nessun backend, nessun deploy, nessun account, nessuna sandbox,
nessuna sincronizzazione. Non introdurre nulla di tutto ciò.

## File di riferimento

| File | Contenuto |
|---|---|
| `CLAUDE.md` (questo) | Contesto stabile, decisioni e convenzioni. **Non contiene stato di avanzamento.** |
| `PLAN.md` | Il piano approvato per esteso: architettura, schema DB, milestone, verifica. |
| `PROGRESS.md` | **Unica fonte di verità sull'avanzamento.** Da leggere per primo a inizio sessione. |

Regola operativa: `PROGRESS.md` si aggiorna **a ogni transizione di stato di un task**
(`todo` → `in-progress` → `done`), non a fine milestone. Se il contesto viene svuotato a metà di
un task, quel file deve dire con precisione dove eravamo e qual è il passo successivo.

## Confini dello scope — decisi, non da rimettere in discussione

Queste sono esclusioni volute. Non aggiungerle "perché sarebbe utile".

- **Niente loop** (né auto-loop, né loop in/out).
- **Niente keylock / time-stretch.** Il pitch è **solo varispeed**: velocità e tonalità legate,
  come su un giradischi reale. È il comportamento che serve per prevedere cosa succederà davvero
  sui piatti.
- **Solo YouTube** come sorgente. Niente import di file locali, niente altre piattaforme.
- **Nessun export** (né PDF, né testo, né copia dei file).
- **Un solo device audio in uscita.** Niente preascolto in cuffia su device separato.
- **Solo quattro campi di metadati**: titolo, artista, album — più le foto dell'etichetta. Niente
  genere, anno, rating, commenti, energy.
- **Beatgrid a BPM costante** (offset del downbeat + BPM). Niente beatgrid a marker multipli.

## Vincolo di layout: waveform orizzontali a piena larghezza

Le waveform scorrono **in orizzontale**, tempo da sinistra a destra, e occupano tutta la larghezza
della finestra. Di conseguenza **i due deck sono impilati** — A sopra, B sotto — come in rekordbox,
**non affiancati**: affiancarli dimezzerebbe la larghezza di ogni waveform e renderebbe illeggibile
proprio la cosa che serve guardare. Vale sia per l'overview sia per la vista zoomata.

## Decisioni architetturali e il loro perché

**Swift 6 + SwiftUI, nativo, target macOS 26.** Il cuore dell'app è audio a bassa latenza su due
deck simultanei più rendering di waveform a 60 fps. Qualsiasi runtime interposto (Electron, Tauri)
avrebbe richiesto comunque un ponte verso Core Audio, con jitter e RAM in più.

**Motore audio: `AVAudioSourceNode` con render callback custom, non `AVAudioPlayerNode`.**
Con il player node la posizione riportata non coincide con ciò che si sente (buffering interno) e
`playerTime(forNodeTime:)` restituisce `nil` in pausa — esattamente le due cose che rompono un
deck DJ. Con un source node il playhead è nostro, quindi seek, scrub, CUE e hot cue sono esatti al
sample.

**Il varispeed è l'avanzamento del playhead a passo frazionario** (interpolazione cubica
Catmull-Rom), non `AVAudioUnitVarispeed` in catena. Un'unità in più disaccoppierebbe di nuovo la
posizione riportata dall'audio udito, e ci riporterebbe al problema di sopra.

**Il render callback audio è real-time: nessuna allocazione, nessun lock, nessuna chiamata
Objective-C.** La traccia intera sta in RAM come `Float`: misurato su un brano reale di 5:45,
**116 MB** (44,1 kHz stereo float32 = ~21 MB al minuto), quindi circa 240 MB con due deck pieni.
Il cambio traccia
scambia un puntatore e il buffer vecchio viene liberato dal main thread al ciclo successivo.
Questa è la regola più facile da violare per sbaglio e la più difficile da diagnosticare dopo:
qualsiasi modifica dentro il callback va guardata con questo metro.

**Persistenza: GRDB 7 (SQLite), non SwiftData.** Migrazioni esplicite e leggibili, e controllo
totale sulla colonna `position` che ordina le playlist — che è il punto dove SwiftData dà più
problemi. `ValueObservation` aggiorna la UI sul main actor.

**Peaks precalcolati, multi-risoluzione e a 3 bande di frequenza.** Livelli con bin da
4096/1024/256/64 sample così overview e vista zoomata si disegnano entrambe dalla stessa cache
senza ricalcoli. Le tre bande (low < 200 Hz, mid 200 Hz–4 kHz, high > 4 kHz) servono a colorare la
waveform come rekordbox: è ciò che fa riconoscere a colpo d'occhio dove entra la cassa.

**yt-dlp si impacchetta nella variante "onedir" (`yt-dlp_macos.zip`), mai come binario singolo.**
Il binario singolo è un PyInstaller *onefile*: si riespande in una cartella temporanea a ogni
lancio e macOS ne riscansiona il contenuto ogni volta. Misurato: **13 secondi di avvio a ogni
invocazione** contro **0,33 s** della onedir, che paga la scansione una volta sola. Su un import
completo la differenza è 58 s contro 5,7 s. Costa 124 MB di bundle, che su un'app locale non sono
una risorsa scarsa. Se qualcuno "semplifica" tornando al file singolo, l'app torna lenta senza che
nulla appaia rotto.

**Nessuna ricodifica dell'audio quando è evitabile.** YouTube serve già AAC in contenitore m4a
(formato 140), che AVFoundation apre nativamente. ffmpeg interviene solo quando è disponibile il
solo Opus/WebM, che AVFoundation non apre: in quel caso converte in **ALAC** (lossless), per non
sommare una seconda perdita a quella della sorgente.

**Le note di playlist sono righe autonome** (`playlistItem.kind = 'note'`), non un campo attaccato
alla traccia: se ne possono mettere più d'una fra due pezzi, o una in testa alla scaletta, e si
riordinano col drag & drop insieme alle tracce.

**Le playlist si riordinano riscrivendo `position` in modo denso** su tutta la playlist al drop.
Le scalette sono corte (decine di righe), quindi non serve niente di più furbo e si evita la
deriva dei fractional index.

## Struttura

```
project.yml          XcodeGen — il progetto Xcode si RIGENERA da qui, non modificarlo a mano
App/                 target app: SwiftUI, viste, view model
  Library/           tabella libreria, ispettore metadati
  Decks/             i due deck, waveform, trasporto
  Playlists/         editor playlist, drag & drop
  Import/            pannello import URL, coda
DJKit/               Swift package locale — tutta la logica testabile senza UI
  Sources/DJKit/
    Model/           Track, CuePoint, Playlist, PlaylistItem
    Persistence/     AppDatabase, Migrations, repository
    Import/          ToolLocator, YtDlpRunner, MetadataParser, ImportQueue
    Audio/           AudioGraph, DeckEngine, DecodedTrack
    Analysis/        AudioDecoder, PeaksBuilder, TempoAnalyzer
    Storage/         LibraryPaths, PeaksFile
  Tests/DJKitTests/
Resources/Tools/     sidecar bundled, NON versionati: ./Scripts/fetch-tools.sh
  yt-dlp/            cartella onedir (eseguibile + _internal/), da tenere intera
  ffmpeg             binario statico arm64
```

**La logica va in `DJKit`, non nel target app.** Parser dei titoli, calcolo dei peaks e rilevamento
BPM sono la parte con più logica e più facile da sbagliare: nel package si testano con
`swift test` in secondi, senza avviare la GUI.

## Dati dell'utente su disco

```
~/Library/Application Support/Crate/
  library.sqlite
  Audio/<uuid>.m4a
  Peaks/<uuid>.peaks
  Artwork/<uuid>-A.jpg, <uuid>-B.jpg
  Tools/yt-dlp                 yt-dlp aggiornato: ha la precedenza su quello bundled
```

Questa è la libreria musicale di Gabriel: i file audio sono il risultato di download che possono
richiedere minuti ciascuno. **Non cancellare né sovrascrivere nulla sotto questo percorso** per
comodità di test — usa una directory temporanea.

## Comandi

```bash
./Scripts/fetch-tools.sh                              # scarica yt-dlp e ffmpeg (una tantum)
xcodegen generate                                     # rigenera Crate.xcodeproj da project.yml
xcodebuild -project Crate.xcodeproj -scheme Crate build
swift test --package-path DJKit                       # test della logica, veloci
open Crate.xcodeproj
```

`CRATE_NETWORK_TESTS=1 swift test --package-path DJKit --filter ImportIntegration` esegue i test
che parlano davvero con YouTube: sono esclusi dalla suite normale perché richiedono rete e
dipendono da un video che potrebbe sparire.

`xcodegen` si installa con `brew install xcodegen` (una tantum). Dopo aver aggiunto o rimosso file
o dipendenze in `project.yml`, rigenera il progetto prima di compilare.

## Convenzioni

- Swift 6 con concorrenza rigorosa. I repository sono `actor` o isolati al main actor; il codice
  audio real-time sta fuori dagli actor e comunica con puntatori e valori atomici.
- Un tipo per file, nome del file uguale al nome del tipo.
- I test coprono la logica pura (parsing, serializzazione, DSP): niente test sulla UI.
- Il `TempoAnalyzer` si verifica su click track sintetici a BPM noto (120/128/174), tolleranza
  ±0.5 BPM — non su file musicali reali, che rendono i test non riproducibili.
- Commenti in italiano, identificatori e API in inglese.
