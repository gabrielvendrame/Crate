# Piano — App macOS per preparare DJ set in vinile

## Contesto

Gabriel prepara set da suonare **in vinile**. Il flusso di lavoro attuale è manuale: trova un
brano su YouTube, lo ascolta, decide dove sta il punto di attacco e come lega con il pezzo
successivo, e tiene traccia di tutto fuori da qualsiasi strumento. Serve un'app locale che chiuda
il cerchio: scarica l'audio da un link YouTube, lo analizza, lo archivia con i metadati e la foto
dell'etichetta del vinile corrispondente, e permette di costruire scalette provando le transizioni
su due deck stile rekordbox, annotando cue point e note di passaggio.

L'app è **solo locale**: nessun deploy, nessun backend, nessun account, nessuna sandbox.

### Scope confermato

| Aspetto | Decisione |
|---|---|
| Stack | Swift 6 + SwiftUI, nativo macOS 26 |
| Sorgenti | Solo link YouTube |
| Deck | Play/pausa, tasto CUE, cue point con note, BPM + beatgrid, pitch/tempo. **Niente loop** |
| Pitch | **Solo varispeed** — velocità e tonalità legate, come un giradischi reale |
| Metadati | Auto da YouTube con parsing euristico, poi editabili a mano |
| Export | Nessuno |
| Binari | yt-dlp + ffmpeg bundled, con comando di auto-update |
| Audio out | Device singolo, gain per deck + crossfader |

## Architettura

### Struttura del progetto

```
youtube-playlist-creator-dj/
  project.yml                  # XcodeGen — progetto rigenerabile, versionabile
  App/                         # target app: SwiftUI, viste, view model
    CrateApp.swift
    Library/                   # tabella libreria, ispettore metadati
    Decks/                     # i due deck + waveform view
    Playlists/                 # editor playlist, drag & drop
    Import/                    # pannello import URL + coda
  DJKit/                       # Swift package locale, testabile senza UI
    Sources/DJKit/
      Model/                   # Track, CuePoint, Playlist, PlaylistItem
      Persistence/             # GRDB: Database.swift, Migrations.swift, repository
      Import/                  # YtDlpRunner, MetadataParser, ImportQueue
      Audio/                   # DeckEngine, AudioGraph, DecodedTrack
      Analysis/                # PeaksBuilder, TempoAnalyzer
      Storage/                 # LibraryPaths, PeaksFile
    Tests/DJKitTests/
  Resources/Tools/             # yt-dlp, ffmpeg, ffprobe (bundled)
```

**Perché XcodeGen**: il progetto si rigenera da `project.yml` (testo), quindi è modificabile senza
aprire Xcode e non degenera in conflitti nel `project.pbxproj`. Richiede `brew install xcodegen`
una tantum. Se preferisci evitarlo, l'alternativa è creare il progetto a mano in Xcode una volta e
usare le *synchronized folders* di Xcode 16+, ma perdi la rigenerabilità.

**Perché un package `DJKit` separato**: parser dei titoli, calcolo dei peaks e rilevamento BPM sono
la parte con più logica e più facile da sbagliare. In un package si testano con `swift test` in
secondi, senza avviare la GUI.

### Persistenza — GRDB 7 (SQLite)

Preferito a SwiftData: migrazioni esplicite e leggibili, controllo totale sull'ordinamento delle
playlist (che è il punto dove SwiftData dà più grattacapi), e `ValueObservation` aggiorna la UI
sul main actor senza cerimonie.

```sql
track(id, youtubeID UNIQUE, youtubeURL, title, artist, album,
      durationSeconds, sampleRate, channelCount,
      bpm, beatgridOffsetSeconds,          -- offset = primo downbeat
      audioFilename, peaksFilename,
      labelImageAFilename, labelImageBFilename,
      analysisState,                        -- pending|downloading|analyzing|ready|failed
      addedAt)

cuePoint(id, trackID → track ON DELETE CASCADE,
         positionSeconds, label, note, colorIndex,
         hotcueSlot,                        -- 1..8, NULL = memory cue
         UNIQUE(trackID, hotcueSlot))

playlist(id, name, note, createdAt, updatedAt)

playlistItem(id, playlistID → playlist ON DELETE CASCADE,
             position INT,                  -- ordinamento denso, riscritto al drop
             kind,                          -- 'track' | 'note'
             trackID → track ON DELETE SET NULL,   -- se kind='track'
             text)                          -- se kind='note'
```

Le note tra i brani sono **righe autonome** (`kind='note'`), non un campo attaccato alla traccia:
così puoi metterne più di una tra due pezzi, o una in testa alla scaletta, e si riordinano col
drag & drop insieme alle tracce.

### File su disco

```
~/Library/Application Support/Crate/
  library.sqlite
  Audio/<uuid>.m4a
  Peaks/<uuid>.peaks
  Artwork/<uuid>-A.jpg, <uuid>-B.jpg
  Tools/yt-dlp                    # versione aggiornata, ha la precedenza su quella bundled
```

### Pipeline di import

1. `yt-dlp --dump-single-json <url>` → titolo, canale, durata, thumbnail
2. `MetadataParser` estrae Artista/Titolo dal titolo del video: gestisce i separatori `-`, `–`,
   `—`, `|`, `:` e ripulisce il rumore (`(Official Video)`, `[HD]`, `Full Album`, `Remastered`,
   `HQ`, anni tra parentesi…). Album lasciato vuoto. Tutto correggibile nell'ispettore.
3. `yt-dlp -f 'bestaudio[ext=m4a]/bestaudio' -o <tmp>` — il formato 140 di YouTube è AAC 128k in
   contenitore m4a, decodificabile nativamente da AVFoundation **senza ricodifica**.
4. Se YouTube serve solo Opus/WebM (che AVFoundation non apre): `ffmpeg -i in.webm -c:a alac
   out.m4a` — ALAC è lossless, quindi la conversione non aggiunge perdita sopra quella della
   sorgente.
5. Decodifica completa → `PeaksBuilder` → `TempoAnalyzer` → riga nel DB, stato `ready`.

Coda seriale in un `actor ImportQueue`; la percentuale si legge dallo stdout di yt-dlp
(`[download]  42.3% of ...`). Un fallimento marca la traccia `failed` con il messaggio d'errore,
senza bloccare la coda.

### Analisi — peaks e tempo

**`PeaksBuilder`** produce un file `.peaks` **multi-risoluzione** e **a 3 bande**:

- Livelli con bin da 4096 / 1024 / 256 / 64 sample → l'overview dell'intera traccia e la vista
  zoomata scrollante si disegnano entrambe senza ricalcolare nulla.
- Per ogni bin: `min`, `max`, più l'energia in tre bande (low < 200 Hz, mid 200 Hz–4 kHz,
  high > 4 kHz) ottenuta da FFT vDSP. Serve a colorare la waveform come rekordbox — blu i bassi,
  verde i medi, arancio gli alti — che è ciò che ti fa riconoscere a colpo d'occhio dove entra la
  cassa o dove c'è solo un cappello.
- Formato binario compatto (header + `UInt8` per canale d'ampiezza), ~1–2 MB per traccia.

**`TempoAnalyzer`**: onset detection tramite *spectral flux* multi-banda, autocorrelazione FFT
sulla curva di onset, interpolazione parabolica del picco per la precisione sub-lag, poi ricerca
della fase del downbeat. Implementazione diretta su vDSP/Accelerate anziché una dipendenza
esterna poco nota. Beatgrid = **BPM costante + offset del primo downbeat**, entrambi regolabili a
mano (trascinando la griglia, o con tap-tempo) — sufficiente per praticamente tutta la musica da
club, e senza la complessità dei beatgrid a marker multipli.

### Motore audio

Un `AVAudioSourceNode` per deck con render callback custom, invece della catena
`AVAudioPlayerNode` + `AVAudioUnitVarispeed`. Il motivo è pratico: con `AVAudioPlayerNode` la
posizione riportata non coincide con ciò che senti (buffering interno) e
`playerTime(forNodeTime:)` restituisce `nil` in pausa — proprio le due cose che rompono un deck
DJ. Con un source node il playhead è nostro, quindi seek, scrub e CUE sono esatti al sample.

```
DeckEngine (× 2)
  DecodedTrack      buffer float32 per canale, traccia intera in RAM (~50 MB per 5 min)
  playhead: Double  frame frazionario, letto atomicamente dalla UI a 60 Hz
  rate: Double      1.0 + pitch/100  →  varispeed per interpolazione cubica Catmull-Rom
  AVAudioSourceNode → gain deck → crossfader → mainMixerNode → output
```

Il varispeed è **l'avanzamento del playhead a passo frazionario**: alzando il pitch sale anche la
tonalità, esattamente come sul piatto. Niente allocazioni né lock nel callback; il cambio traccia
scambia un puntatore e il buffer vecchio viene liberato sul main thread al ciclo successivo.

**Comportamento del tasto CUE** (identico a rekordbox):
- in play → torna al cue e mette in pausa;
- in pausa sul cue → tenendolo premuto suona da lì, al rilascio torna al cue;
- in pausa altrove → sposta il cue nella posizione corrente.

**Hot cue 1–8**: tasti `1`–`8` per saltarci, `⇧`+numero per cancellare. Ognuno ha colore e nota.
I memory cue (senza slot) sono illimitati e compaiono come marker sulla waveform.

### Interfaccia

Finestra singola, tre zone:

- **Sidebar**: Libreria + elenco playlist.
- **Centro**: tabella libreria (titolo, artista, album, BPM, durata, miniatura etichetta) oppure
  editor playlist a seconda della selezione.
- **Fascia inferiore, sempre visibile**: i due deck A/B affiancati. Ogni deck ha overview
  dell'intera traccia, waveform zoomata scrollante allineata ai beat, trasporto, fader pitch
  verticale con display del BPM effettivo, e la riga degli 8 hot cue.
- **Ispettore a destra** (⌥⌘I): metadati editabili, foto etichetta lato A e lato B, elenco dei cue
  point con le rispettive note, BPM e offset beatgrid.

Rendering waveform: `Canvas` SwiftUI per l'overview (statica, poche centinaia di punti), **Metal**
per la vista zoomata che scorre a 60 fps sotto la testina.

Le foto etichetta si aggiungono con drag & drop dal Finder o incollando dagli appunti (⌘V), utile
se fotografi l'etichetta col telefono e usi Continuity.

Trascinando una traccia dalla libreria alla playlist la si accoda; trascinandola su un deck la si
carica. Il riordino nella playlist è drag & drop su tracce e note indistintamente.

## Continuità del contesto

Prima di scrivere qualsiasi codice creo tre file nella radice del progetto, tenuti distinti:

**`CLAUDE.md`** — il contesto stabile, letto automaticamente all'inizio di ogni sessione.
Contiene: a cosa serve l'app e per chi (preparazione di DJ set in vinile), lo scope confermato con
i suoi confini espliciti (**niente loop, niente keylock, solo YouTube, niente export, un solo
device audio**), le decisioni architetturali con il *perché* (source node custom, varispeed reale,
GRDB, peaks a 3 bande, nessuna ricodifica audio), la mappa delle cartelle, i comandi di build e
test, le convenzioni di codice, e i puntatori a `PLAN.md` e `PROGRESS.md`. Non contiene lo stato
di avanzamento: quello sta altrove e cambia in continuazione.

**`PLAN.md`** — copia di questo piano nella radice del progetto, così sopravvive a un reset del
contesto senza dipendere da `~/.claude/plans/`. Si aggiorna solo se cambiano le decisioni.

**`PROGRESS.md`** — lo stato di avanzamento, unica fonte di verità su cosa è fatto. Ogni milestone
è spezzata in task con stato esplicito:

```markdown
## M2 — Import  ·  in-progress

- [x] `done` — YtDlpRunner: wrapper Process con parsing del progresso
- [~] `in-progress` — MetadataParser: euristica Artista/Titolo
- [ ] `todo` — ImportQueue: actor con coda seriale e ripresa dopo errore
```

Ogni task registra, quando serve, una riga di note su file toccati e decisioni prese durante
l'implementazione. **Aggiorno `PROGRESS.md` a ogni transizione di stato**, non a fine milestone:
se il contesto viene svuotato a metà di un task, il file dice esattamente dove eravamo. In coda un
blocco *"Prossimo passo"* con la ripartenza immediata, e uno *"Questioni aperte"* per i dubbi
emersi in corsa che vanno posti a Gabriel.

## Milestone

| # | Contenuto | Esito verificabile |
|---|---|---|
| M0 | `CLAUDE.md`, `PLAN.md`, `PROGRESS.md` popolato con tutti i task di M1–M7 in stato `todo` | Il contesto è ricostruibile da zero leggendo i tre file |
| M1 | Scaffolding: `project.yml`, `DJKit`, schema GRDB + migrazioni, cartelle libreria, shell dell'app | L'app parte, il DB si crea, i test del package passano |
| M2 | Import: binari sidecar, `YtDlpRunner`, `MetadataParser`, `ImportQueue`; tabella libreria + ispettore + foto etichetta | Incolli un URL, la traccia compare in libreria con i metadati e la puoi correggere |
| M3 | Analisi: decoder, `PeaksBuilder` multi-livello a 3 bande, cache `.peaks`, rendering waveform | Le waveform si disegnano, colorate per bande |
| M4 | Deck: `DeckEngine`, varispeed, play/pausa, CUE, hot cue con note, crossfader | Suoni due tracce insieme, metti cue point e ci salti |
| M5 | Playlist: CRUD, drag & drop, note tra i brani, caricamento sul deck dalla scaletta | Costruisci una scaletta completa e la provi |
| M6 | BPM/beatgrid: `TempoAnalyzer`, overlay griglia, tap-tempo, editing manuale, BPM effettivo col pitch | Ogni traccia ha un BPM corretto e una griglia allineata |
| M7 | Rifiniture: scorciatoie, aggiornamento yt-dlp, stati vuoti, gestione errori | Uso quotidiano senza spigoli |

## Verifica

- `swift test` su `DJKit`: parsing dei titoli YouTube su un set di casi reali; round-trip del file
  `.peaks`; `TempoAnalyzer` su segnali sintetici a BPM noto (click track a 120/128/174) con
  tolleranza ±0.5 BPM; migrazioni del DB da schema vuoto.
- `xcodebuild -project Crate.xcodeproj -scheme Crate build` per la compilazione dell'app.
- Verifica end-to-end manuale su una traccia reale: import da URL → metadati corretti → waveform
  disegnata → BPM plausibile → caricamento sui due deck → cue point con nota → playlist con note
  di transizione riordinabile.
- Controllo che il render callback audio non allochi: profilo con Instruments (template Audio
  System Trace) durante il playback dei due deck con pitch in movimento.

## Decisioni prese in autonomia — dimmi se ne cambio qualcuna

1. **Nome: `Crate`** (il termine con cui i DJ chiamano la cassa dei vinili). Alternative se non
   piace: `VinylPrep`, `Setlist`.
2. **8 hot cue** (tasti 1–8) più memory cue illimitati.
3. **Due foto etichetta per traccia**, lato A e lato B.
4. **Waveform a 3 bande di frequenza** colorata stile rekordbox, anziché monocromatica.
5. **Beatgrid a BPM costante** (offset + BPM, entrambi editabili a mano), senza marker multipli.
6. **Note di playlist come righe autonome** inseribili ovunque nella scaletta.
7. **Audio conservato nel formato originale** (m4a AAC da YouTube), decodificato in RAM al
   caricamento del deck. Nessuna ricodifica se non strettamente necessaria.
8. **XcodeGen** come generatore di progetto (`brew install xcodegen`, una tantum).
