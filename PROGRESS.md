# Avanzamento — Crate

Unica fonte di verità su cosa è fatto. Aggiornato **a ogni transizione di stato**, non a fine
milestone. Contesto e decisioni stanno in `CLAUDE.md`, il piano esteso in `PLAN.md`.

Legenda: `[ ] todo` · `[~] in-progress` · `[x] done` · `[!] bloccato`

---

## M0 — Contesto e tracciamento · **done**

- [x] `done` — `PLAN.md`: copia del piano approvato nella radice del progetto
- [x] `done` — `CLAUDE.md`: contesto, confini di scope, decisioni architetturali, comandi, convenzioni
- [x] `done` — `PROGRESS.md`: questo file, con tutti i task di M1–M7 in stato `todo`

---

## M1 — Scaffolding · **done**

*Esito atteso: l'app parte, il DB si crea, i test del package passano.*

- [x] `done` — `.gitignore` (build, DerivedData, `Crate.xcodeproj` generato, binari in `Resources/Tools/`)
- [x] `done` — `project.yml` XcodeGen: target app macOS 26, package locale `DJKit`, Info.plist generato, firma ad hoc, sandbox disattivata
- [x] `done` — `DJKit/Package.swift` con dipendenza GRDB 7 · `brew install xcodegen` eseguito
- [x] `done` — `Storage/LibraryPaths.swift` + `VinylSide` · aggiunta anche `Scratch/` per download e conversioni in corso
- [x] `done` — `Model/`: `Track`, `CuePoint`, `Playlist`, `PlaylistItem`, `PlaylistEntry`, `AnalysisState`
- [x] `done` — `Persistence/AppDatabase.swift` + `Migrations.swift` (migrazione `v1-schema`)
- [x] `done` — `Persistence/TrackRepository.swift`, `PlaylistRepository.swift` con riordino denso e `ValueObservation`
- [x] `done` — Shell app SwiftUI: `AppModel`, `ContentView`, `SidebarView`, `LibraryView`, `PlaylistDetailView`, `DeckBarView`
- [x] `done` — Test scritti: `DatabaseTests`, `PlaylistRepositoryTests`, `LibraryPathsTests`
- [x] `done` — `swift test --package-path DJKit`: **14 test su 14 verdi**
- [x] `done` — `xcodegen generate` + `xcodebuild -scheme Crate build`: **BUILD SUCCEEDED**
- [x] `done` — Avvio verificato: cartelle e `library.sqlite` creati in `~/Library/Application Support/Crate/` con le tabelle `track`, `cuePoint`, `playlist`, `playlistItem`


## M2 — Import da YouTube · **done**

*Esito atteso: incolli un URL, la traccia compare in libreria con i metadati e la puoi correggere.*

- [x] `done` — `Scripts/fetch-tools.sh`: scarica yt-dlp (onedir) e ffmpeg statico arm64 in `Resources/Tools/`
- [x] `done` — `Import/ToolLocator.swift`: preferisce `Application Support/Crate/Tools/`, poi il bundle; percorsi relativi per tool
- [x] `done` — `Import/ProcessRunner.swift`: stdout da pipe riga per riga, stderr su file temporaneo
- [x] `done` — `Import/YtDlpRunner.swift`: `--dump-single-json`, download con progresso, `--no-playlist`
- [x] `done` — `Import/YouTubeURL.swift`: estrazione dell'id da tutte le forme di link, `&list=` ignorato
- [x] `done` — `Import/MetadataParser.swift`: euristica Artista/Titolo con pulizia del rumore
- [x] `done` — Test `MetadataParser` (10 casi) e `YouTubeURL` (5 casi)
- [x] `done` — `Import/AudioConverter.swift`: ffmpeg opus/webm → ALAC, solo se AVFoundation non apre il file
- [x] `done` — `Import/ImportQueue.swift`: actor sul main, coda seriale, un errore non blocca gli altri
- [x] `done` — `Analysis/AudioFileInfo.swift`: durata, sample rate e canali dal file reale
- [x] `done` — UI: `ImportSheet` (⌘N) con campo, incolla, coda e barre di progresso
- [x] `done` — UI: tabella libreria con miniatura etichetta, BPM, durata, stato
- [x] `done` — UI: `TrackInspector` (⌥⌘I) con metadati a salvataggio ritardato
- [x] `done` — `ArtworkStore` + foto etichetta lato A/B: drag & drop, incolla, doppio clic, ridimensionamento a 1200 px JPEG
- [x] `done` — Test di integrazione contro YouTube reale: import singolo da link con playlist, rifiuto dei doppioni
- [x] `done` — Verificato che i binari partano da dentro `Crate.app/Contents/Resources/Tools/`


## M3 — Analisi e waveform · **todo** ← prossima

*Esito atteso: le waveform si disegnano, colorate per bande di frequenza.*

- [ ] `todo` — `Analysis/AudioDecoder.swift`: `AVAudioFile` → buffer `Float` per canale, traccia intera
- [ ] `todo` — `Analysis/PeaksBuilder.swift`: livelli 4096/1024/256/64, min/max + energia low/mid/high via FFT vDSP
- [ ] `todo` — `Storage/PeaksFile.swift`: formato binario compatto, scrittura e lettura
- [ ] `todo` — Test: round-trip `PeaksFile`, coerenza fra livelli di zoom
- [ ] `todo` — `Decks/WaveformOverviewView.swift`: `Canvas` SwiftUI, traccia intera
- [ ] `todo` — `Decks/WaveformZoomView.swift`: rendering Metal scrollante a 60 fps
- [ ] `todo` — Analisi automatica a fine import + comando di ricalcolo manuale

## M4 — Deck audio · **todo**

*Esito atteso: suoni due tracce insieme, metti cue point e ci salti.*

- [ ] `todo` — `Audio/DecodedTrack.swift`: buffer in RAM, swap atomico del puntatore, rilascio differito
- [ ] `todo` — `Audio/AudioGraph.swift`: engine, mixer, gain per deck, crossfader, output
- [ ] `todo` — `Audio/DeckEngine.swift`: `AVAudioSourceNode`, playhead frazionario, interpolazione Catmull-Rom, `rate`
- [ ] `todo` — Trasporto: play/pausa, seek dalla waveform, scrub trascinando
- [ ] `todo` — Tasto CUE stile rekordbox (i tre comportamenti descritti in `PLAN.md`)
- [ ] `todo` — Hot cue 1–8: modello, tasti `1`–`8`, `⇧`+numero per cancellare, colore e nota per ognuno
- [ ] `todo` — Memory cue illimitati: marker sulla waveform, editing della nota
- [ ] `todo` — UI deck completa: overview + zoom + trasporto + fader pitch + riga hot cue
- [ ] `todo` — Crossfader e gain per deck

## M5 — Playlist · **todo**

*Esito atteso: costruisci una scaletta completa e la provi.*

- [ ] `todo` — `PlaylistRepository`: creazione, rinomina, eliminazione, inserimento e riordino con `position` densa
- [ ] `todo` — UI editor playlist: righe traccia e righe nota nella stessa lista
- [ ] `todo` — Drag & drop: riordino interno, drop di tracce dalla libreria
- [ ] `todo` — Righe nota: inserimento in qualsiasi punto, editing inline, eliminazione
- [ ] `todo` — Caricamento sul deck A/B dalla scaletta (drag oppure doppio clic)
- [ ] `todo` — Test: il riordino mantiene `position` densa e coerente

## M6 — BPM e beatgrid · **todo**

*Esito atteso: ogni traccia ha un BPM corretto e una griglia allineata.*

- [ ] `todo` — `Analysis/TempoAnalyzer.swift`: spectral flux multi-banda, autocorrelazione FFT, interpolazione parabolica del picco
- [ ] `todo` — Rilevamento della fase del downbeat → `beatgridOffsetSeconds`
- [ ] `todo` — Test su click track sintetici a 120/128/174 BPM, tolleranza ±0.5
- [ ] `todo` — Overlay della griglia sulla waveform zoomata
- [ ] `todo` — Editing manuale: campo BPM, trascinamento della griglia, tap-tempo
- [ ] `todo` — Display del BPM effettivo in funzione della posizione del pitch

## M7 — Rifiniture · **todo**

*Esito atteso: uso quotidiano senza spigoli.*

- [ ] `todo` — Scorciatoie da tastiera complete + pannello di aiuto
- [ ] `todo` — Comando "Aggiorna yt-dlp": scarica l'ultima release GitHub in `Tools/`
- [ ] `todo` — Ricerca e filtro nella libreria
- [ ] `todo` — Eliminazione traccia con rimozione dei file associati e conferma
- [ ] `todo` — Stati vuoti e messaggi d'errore leggibili
- [ ] `todo` — Verifica con Instruments (Audio System Trace): nessuna allocazione nel render callback

---

## Ripartenza a freddo

**Stato:** M0, M1 e M2 chiuse. L'import da YouTube funziona end-to-end ed è stato **provato da
Gabriel dall'interfaccia**, non solo dai test. La libreria mostra le tracce, l'ispettore le
modifica, le foto delle etichette si aggiungono. I deck sono ancora segnaposto.

```bash
cd /Users/gabriel/Desktop/youtube-playlist-creator-dj
./Scripts/fetch-tools.sh                       # solo se Resources/Tools/ è vuota
swift test --package-path DJKit                # 35 test, ~0,02 s
xcodegen generate && xcodebuild -project Crate.xcodeproj -scheme Crate build
```

Test contro YouTube reale (esclusi dalla suite normale):

```bash
CRATE_NETWORK_TESTS=1 swift test --package-path DJKit --filter ImportIntegration
```

**Traccia di prova** fornita da Gabriel: `https://www.youtube.com/watch?v=wqf-xIyf5y4` —
"FrescoEdits - Jom", 5:45, m4a AAC 129k, 44,1 kHz stereo. Il link originale portava dietro
`&list=RDjLEvbgq2oEQ&index=7`, ed è il caso su cui è costruito il test del `--no-playlist`.

**Il progetto non è sotto controllo di versione** (nessun `git init` fatto). Il `.gitignore` è già
scritto e pronto.

## Prossimo passo — M3

1. `Analysis/AudioDecoder.swift`: decodifica completa in buffer `Float` **per canale**
   (non interleaved, come lo restituisce `AVAudioPCMBuffer`), da riusare tal quale in M4 per il
   deck. Già misurato: 0,19 s e 116 MB per un brano di 5:45.
2. `Analysis/PeaksBuilder.swift` e `Storage/PeaksFile.swift`. Formato deciso ma non ancora scritto:
   - livelli con bin da **4096 / 1024 / 256 / 64** sample, tutti nello stesso file, così overview e
     vista zoomata leggono dalla stessa cache senza ricalcoli;
   - per ogni bin **cinque valori `UInt8`**: `min`, `max`, ed energia nelle bande
     **low < 200 Hz**, **mid 200 Hz–4 kHz**, **high > 4 kHz**, ricavate con FFT vDSP;
   - header con magic, versione, sample rate, numero di frame e tabella dei livelli;
   - attesi 1–2 MB per traccia.
3. Test: round-trip del file e coerenza fra livelli di zoom.
4. `Decks/WaveformOverviewView` con `Canvas`, `Decks/WaveformZoomView` con Metal.
   **Orizzontali a piena larghezza**, deck impilati — vincolo in `CLAUDE.md`.
5. Agganciare l'analisi in fondo a `ImportQueue.process` (dove ora c'è il commento
   "L'analisi di peaks e tempo entra qui in M3/M6") e aggiungere un comando di ricalcolo manuale
   per le tracce già importate, che non hanno peaks.

## Note di implementazione

### Da M2

- **yt-dlp onedir, non binario singolo.** Il file singolo impiega 13 s ad avviarsi *ogni volta*
  (PyInstaller onefile si riespande e macOS lo riscansiona); la onedir 0,33 s. Import completo:
  58 s → 5,7 s. Motivo scritto anche in `CLAUDE.md` perché è una regressione invisibile.
- **`--no-playlist` è obbligatorio.** I link copiati da YouTube portano dietro `&list=RD…`, il mix
  automatico: senza quel flag si scarica l'intera radio. C'è un test dedicato.
- **Le risorse a cartella in XcodeGen** vanno puntate alla cartella finale (`Resources/Tools`), non
  a quella che la contiene, altrimenti atterrano in `Contents/Resources/Resources/Tools/`.
- **ffprobe non serve**: durata, sample rate e canali li dà `AVAudioFile`. Un binario in meno.
- Il parser tiene le indicazioni di versione fra tonde — `(Original Mix)`, `(Radio Edit)`,
  `(… Remix)` — e butta le quadre finali con etichetta o catalogo. Per un DJ la versione è parte
  dell'identità del pezzo.
- Un brano reale di 5:45 occupa **116 MB** in RAM come float32, non i ~50 MB stimati nel piano.

### Da M1

- `LibraryPaths` ha una cartella `Scratch/` in più rispetto al piano: i download e le conversioni
  ffmpeg ci lavorano dentro e viene svuotata a ogni avvio, così un download interrotto non lascia
  file mezzi scritti nella libreria.
- `playlistItem.trackID` va a `NULL` quando la traccia viene cancellata: la riga resta in scaletta
  come segnaposto invece di aprire un buco silenzioso. Verificato da un test.
- L'indice unico `(trackID, hotcueSlot)` sfrutta il fatto che SQLite ammette più `NULL`: i memory
  cue restano illimitati senza clausole speciali. `assignHotCue` libera lo slot precedente prima
  di scrivere.
- `Track.analysisError` non era nel piano: serve a mostrare *perché* un import è fallito invece di
  un generico stato rosso.
- **Swift 6, concorrenza stretta**: nelle closure di scrittura GRDB la copia mutabile va dichiarata
  *dentro* la closure (`write { db in var x = x; try x.save(db) }`). Catturare una `var` esterna è
  un errore di compilazione, non un avviso. Vale per ogni nuovo metodo di repository.
- **Verifica visiva e GUI non sono automatizzabili su questa macchina**: la shell non ha il
  permesso di registrazione dello schermo (`screencapture` fallisce con "could not create image
  from window") né quello di automazione. Quindi: niente screenshot, niente click simulati. Tutto
  ciò che richiede l'interfaccia va provato da Gabriel, oppure coperto con un test che eserciti lo
  stesso codice sotto la UI — come fa `ImportIntegrationTests` con `ImportQueue`.

## Questioni aperte

Nessuna. Le decisioni prese in autonomia sono elencate in fondo a `PLAN.md` e sono state approvate.
