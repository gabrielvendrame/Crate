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


## M3 — Analisi e waveform · **done**

*Esito atteso: le waveform si disegnano, colorate per bande di frequenza.*

- [x] `done` — `Analysis/AudioDecoder.swift` + `DecodedAudio`: `AVAudioFile` → buffer `Float` per canale, traccia intera
- [x] `done` — `Analysis/PeaksBuilder.swift` + `PeakBin`/`PeaksLevel`/`Peaks`: livelli 64/256/1024/4096, min/max + RMS low/mid/high da STFT vDSP
- [x] `done` — `Storage/PeaksFile.swift`: formato binario compatto, scrittura e lettura
- [x] `done` — Test: round-trip `PeaksFile` (8), `PeaksBuilder` (8), `TrackAnalyzer` (3) — **53 test su 53 verdi**
- [x] `done` — `Decks/WaveformOverviewView.swift`: `Canvas` SwiftUI, traccia intera, clic per saltare
- [x] `done` — `Decks/WaveformZoomView.swift` + `WaveformRenderer` + `Waveform.metal`: rendering Metal scrollante
- [x] `done` — `Decks/DeckState.swift` + `WaveformPalette` + `Timecode`; `DeckBarView` riscritta con scrub e pinch-to-zoom, segnaposto del trasporto conservati
- [x] `done` — `Analysis/TrackAnalyzer.swift`: analisi in coda a `ImportQueue.process`, menu **Deck** con ricalcolo singolo (⌥⌘R) e "Calcola le waveform mancanti"
- [x] `done` — `xcodebuild -scheme Crate build`: **BUILD SUCCEEDED** (ha richiesto `xcodebuild -downloadComponent MetalToolchain`)

## M4 — Deck audio · **done**

*Esito atteso: suoni due tracce insieme, metti cue point e ci salti.*

- [x] `done` — `Audio/DecodedTrack.swift`: allocazione contigua con cornice di zeri agli estremi, più `DeckTrackRef` (descrittore raw) e `CubicInterpolator`
- [x] `done` — `Audio/AudioGraph.swift`: engine, mixer per deck, crossfader a potenza costante, riconnessione al cambio di device
- [x] `done` — `Audio/DeckEngine.swift` + `DeckRenderState`: `AVAudioSourceNode`, playhead frazionario, Catmull-Rom, `rate`, rilascio differito
- [x] `done` — Trasporto: play/pausa dal deck, seek dall'overview, scrub trascinando la waveform zoomata
- [x] `done` — Tasto CUE stile rekordbox: i tre comportamenti in `DeckEngine.pressCue`/`releaseCue`, `CueButton` con pressione e rilascio, marker del cue su overview e vista zoomata
- [x] `done` — Test: `CubicInterpolator` (4), `DecodedTrack` (6), `DeckRenderState` (13), `DeckEngine` — trasporto, CUE, bend e nudge in rendering manuale — (23), `AudioGraph` (3) — **100 test su 100 verdi**
- [x] `done` — **Crash risolto**: il render block ereditava l'isolamento del main actor e il thread audio trappava al primo buffer. Fix in `DeckEngine.makeRenderBlock`, con test di regressione che rende da un `Task.detached`
- [x] `done` — `xcodebuild -scheme Crate build`: **BUILD SUCCEEDED**, nessun avviso
- [!] `da provare` — **verifica all'orecchio di Gabriel**, l'unica cosa che qui non è automatizzabile: due tracce sui due deck, play su entrambe, crossfader al centro, e mettere in fase col nudge — un colpetto per volta e poi la spinta tenuta. Il codice è verificato in rendering offline, che il suono esca dal device no
- [x] `done` — Hot cue 1–8: `HotCueRow` sotto la waveform, un colore per slot (`CuePalette`), pad vuoto che memorizza e pad pieno che salta e suona, ⇧+clic per cancellare, nome e nota nel popover
- [x] `done` — Tasti `1`–`8` e `⇧`+numero sul deck che ha il fuoco, via `DeckKeyMonitor` (monitor `NSEvent`, non voci di menu) · `AppModel.focusedDeckSlot` con la barra accesa sul bordo del deck
- [x] `done` — Marker dei cue su entrambe le waveform: buffer di marker nello shader per la vista zoomata, bandierine numerate nell'overview, cue di lavoro compreso
- [x] `done` — Note degli hot cue: si scrivono col clic destro sul pad e **compaiono passando il puntatore sul pad**, accanto alla riga, senza aspettare il tooltip di sistema
- ~~Memory cue~~ — **fuori scope dal 2026-09-04**, decisione di Gabriel: bastano gli 8 hot cue con la loro nota. Vedi i confini in `CLAUDE.md`
- [x] `done` — `MixerStrip` fra i due deck: crossfader con fermo al centro e un gain per deck. Niente EQ, fuori scope
- [x] `done` — Nudge: `NudgeButton`, **un colpetto sposta di 10 ms, tenuto premuto spinge di ±3%** (`DeckEngine.setBend`/`nudge`, 5 test). Sono i due gesti che servono a mettere in fase, uno a occhio sulla waveform e uno a orecchio mentre suonano
- [x] `done` — `PitchFader` verticale, zero al centro con fermo, **più in basso** come su un SL-1200, doppio clic per azzerare · display del pitch e del BPM effettivo (che resta `— BPM` finché M6 non calcola il tempo)
- [x] `done` — UI deck completa: overview, zoom, trasporto, riga hot cue, fader di pitch verticale e display del BPM effettivo

## M5 — Playlist · **done**

*Esito atteso: costruisci una scaletta completa e la provi.*

- [x] `done` — `PlaylistRepository`: c'era già dalla M1 (creazione, rinomina, eliminazione, inserimento a una posizione, riordino denso)
- [x] `done` — UI editor: righe traccia e righe nota nella stessa lista, numerazione progressiva dei soli brani, durata totale e conteggio nel sottotitolo, badge del deck su cui una traccia è caricata
- [x] `done` — Drag & drop: riordino della scaletta col trascinamento nativo (`onMove`), drop di tracce dalla libreria al punto indicato, drop su un deck che carica · in più «Aggiungi alla scaletta» nel menu contestuale della libreria e «Sposta su/giù» in quello della scaletta
- [x] `done` — Righe nota: dalla barra strumenti (dopo la riga selezionata), dal menu contestuale («qui sotto»), editing inline con salvataggio ritardato, eliminazione
- [x] `done` — Caricamento sul deck dalla scaletta: tastini **A**/**B** sulla riga e menu contestuale · dalla libreria anche trascinando sul deck, che si accende sul bordo
- [x] `done` — **Verificato pilotando l'app** (screenshot + eventi sintetici): riordino trascinando, selezione della riga, aggiunta di brani trascinandoli sulla scaletta nella barra laterale, scrittura di una nota, titolo non più sovrapposto
- [x] `done` — Rinomina della scaletta dalla barra strumenti
- [x] `done` — Eliminazione righe: tasto ⌫ sulla selezione e menu contestuale
- [x] `done` — Test: due nuovi sull'inserimento in mezzo e sull'ordine di un drop multiplo, oltre ai sei della M1 — **102 test su 102 verdi**

## M6 — BPM e beatgrid · **done**

*Esito atteso: ogni traccia ha un BPM corretto e una griglia allineata.*

- [x] `done` — `Analysis/TempoAnalyzer.swift` + `TempoEstimate`: spectral flux multi-banda (9 bande per ottave, ampiezze compresse in log), autocorrelazione via FFT, somma armonica con preferenza attorno a 126 BPM, interpolazione parabolica del picco, **raffinatura su ritardo lungo** che porta l'errore sotto 0,05 BPM
- [x] `done` — `TempoAnalyzer.resolveOctave`: guarda **in mezzo** alle battute trovate e dimezza il periodo se anche lì ci sono colpi. Senza, un 174 con la cassa sull'uno veniva letto 87 — l'autocorrelazione preferisce sistematicamente il periodo lungo
- [x] `done` — Fase per treno di impulsi + scelta dell'uno della misura sulle bande basse → `beatgridOffsetSeconds`
- [x] `done` — `Model/Beatgrid.swift` + `QuantizeResolution`: griglia a BPM costante, aggancio, trascinamento con rientro nella prima misura
- [x] `done` — Analisi e repository: `TrackAnalyzer` calcola il tempo nella stessa passata dei peaks, `TrackRepository.updateAnalysis` e `updateBeatgrid`, `Track.beatgrid`
- [x] `done` — Test: `TempoAnalyzer` su click track sintetici 120/128/174 con tolleranza ±0.5 (7), `Beatgrid` (10), quantize del cue in `DeckEngine` (6) — **125 test su 125 verdi**
- [x] `done` — Overlay della griglia nella vista zoomata: shader Metal, **corsia dedicata in cima**
  (14 px del drawable) con trattini di battuta e trattini di misura più alti, più una linea di
  misura tenue dentro la waveform. Le linee spariscono da sole quando lo zoom le impasta
- [x] `done` — Editing manuale: `BeatgridEditor` in popover dal display del BPM del deck — campo
  BPM, ×2/÷2, tap-tempo (dal quarto colpo, media sugli ultimi otto), «primo 1 qui», frecce da
  1 ms (10 ms con ⇧), «rileva di nuovo», «togli la griglia». **⌥ e trascina** sposta la griglia
  sulla waveform. Campo BPM anche nell'ispettore della libreria, con pulsante «Rileva»
- [x] `done` — Display del BPM effettivo col pitch: c'era già da M4, ora ha un numero da mostrare;
  il display è diventato il pulsante che apre l'editor della griglia
- [x] `done` — **Quantize** — chiesto da Gabriel il 2026-09-04. Interruttore + risoluzione 1/1 e
  1/2 nel mixer (e nel menu **Deck**, ⌥⌘Q), impostazione unica per entrambi i deck e ricordata fra
  un avvio e l'altro. Aggancia il punto **memorizzando** un hot cue, **spostando il cue di lavoro**
  e **saltando** a un hot cue; non tocca scrub e seek. Le decisioni lasciate aperte sono scritte in
  `CLAUDE.md`
- [x] `done` — `swift test`: **125 test su 125 verdi** · `xcodebuild`: **BUILD SUCCEEDED**
- [x] `done` — **Verificato sulla libreria vera, pilotando l'app**: analizzate le 5 tracce
  (125,00 · 117,74 · 126,96 · 119,89 · 124,00 BPM). Misurato in modo indipendente dallo spectral
  flux — inviluppo di energia contro griglia — che **le battute cadono entro 2–8 ms dagli attacchi
  di cassa** su tutte e cinque, con scarto interquartile 2–8 ms. Provati dall'interfaccia: hot cue
  agganciato (battuta 512,000 esatta), hot cue non agganciato a quantize spento (530,103), ÷2 e ×2,
  ⌥+trascinamento della griglia (0,712 → 1,031 s per 40 punti a zoom 8 s), scrittura ritardata

## M7 — Rifiniture · **done**

*Esito atteso: uso quotidiano senza spigoli.*

- [x] `done` — **Crash risolto alla radice: niente più `@Environment(AppModel.self)`.** Bastava
  scrivere un carattere nel campo di ricerca in toolbar per far cadere l'app. Causa: SwiftUI
  rivaluta il `body` del proprietario **dentro l'hosting view della toolbar**, dove l'ambiente
  iniettato alla radice della scena non c'è, e il property wrapper chiama `fatalError`.
  Reiniettare `.environment` copre un caso alla volta — è la toppa già messa all'ispettore il
  2026-09-04. Ora c'è `AppModel.shared`, letto direttamente da tutte e dodici le viste
- [x] `done` — Scorciatoie complete: `DeckKeyMonitor` riscritto con `keyDown` **e** `keyUp` e tre
  fasi (pressione, tenuto, rilascio) — spazio, C per il CUE tenuto premuto, Z/X per nudge e
  spinta, D cambia deck, G apre la griglia, −/+ zoom. Pannello di aiuto in `KeyboardShortcuts`
  (⌘/), che è anche la sola tabella da tenere allineata. **Provate pilotando l'app** con
  `Scripts/ui-key.swift`: spazio fa partire e fermare, C in play riporta a 0:00.0, e C **tenuto
  premuto** suona finché è giù e si ferma al rilascio — che è il comportamento per cui il monitor
  esiste
- [x] `done` — `Import/ToolsUpdater.swift` + `SettingsSheet` (⌘,): ultima release da GitHub,
  variante **onedir** come quella impacchettata, spacchettata con `ditto` e scambiata alla fine —
  un download interrotto non lascia un yt-dlp mezzo scritto. **Provato davvero**, su una libreria
  temporanea: scarica, spacchetta, e il binario installato risponde `--version` (21 s)
- [x] `done` — Ricerca e filtro: `DJKit/Library/LibraryFilter` (parole in qualsiasi campo e
  ordine, accenti e maiuscole ignorati) + quattro sottoinsiemi, campo ⌘F e menu in toolbar,
  sottotitolo «n di m brani», stato vuoto dedicato per «nessun risultato» — 7 test
- [x] `done` — Eliminazione con conferma: sempre, anche per una traccia sola, con l'elenco di cosa
  sparisce e **quanto spazio libera**; ⌫ sulla selezione e selezione multipla
- [x] `done` — Messaggi d'errore leggibili: `AppModel.describe` al posto di `String(describing:)`,
  che su un errore di GRDB stampava la struttura interna del tipo
- [x] `done` — **Verifica che nel render callback non ci sia niente di proibito**:
  `Scripts/check-render-callback.sh` disassembla il binario linkato, segue la catena che parte dal
  render block e cerca `malloc`, retain/release, `objc_msgSend`, lock, `swift_beginAccess`.
  Sei funzioni attraversate — closure, forwarder, `render`, `adoptTrackRef`, `adoptSeek`,
  `CubicInterpolator.sample` — e nessuna chiamata proibita. Statica e ripetibile, mentre un
  profilo con Instruments vede il difetto solo se capita mentre si registra. **Due modi in cui
  mentiva, entrambi corretti**: sull'oggetto non linkato i `bl` non hanno bersaglio e passava
  sempre; includendo la fabbrica `makeRenderBlock` segnalava un `swift_retain` legittimo — ed è
  la prova che sa anche dire di no

Chiesti da Gabriel il **2026-09-04**, usando l'app:

- [x] `done` — **Foto dell'etichetta accanto al deck.** Deciso da Gabriel il 2026-09-05:
  la foto sta **sotto il titolo del brano, nella colonna del deck, e piccola** (`DeckLabelPhoto`).
  Il clic la apre in un popover a dimensione piena — l'obiettivo originale del task era vederla
  grande, e la sola miniatura non lo darebbe. Stesso popover dalla miniatura in tabella. Il posto
  resta occupato anche senza foto, o i comandi sotto ballerebbero al cambio di traccia.
- [x] `done` — **Copertina da Discogs all'import.** `DJKit/Discogs/`: client, costruzione della
  ricerca a tentativi (dal più stretto al più largo, vinile prima), decodifica, token in un file
  0600 dentro la libreria. `DiscogsPickerSheet` mostra le edizioni in griglia con le copertine, il
  vinile in cima. Automatico a fine import: un solo risultato si applica da sé, più d'uno vanno in
  **coda** — non un foglio che salta su a metà di dieci import. Comando manuale nell'ispettore e
  nel menu contestuale. 12 test, più due di integrazione con `CRATE_DISCOGS_TOKEN`
- [x] `done` — **Disposizione dei deck commutabile**: oltre agli attuali due deck impilati
  (orizzontale su due righe), poterli affiancare su **due colonne**, waveform sempre orizzontali.
  Preferenza salvata, di default resta l'impilata. Il compromesso è scritto nei vincoli di
  `CLAUDE.md`: affiancando, ogni waveform ha metà larghezza. Attenzione a `HotCueRow` e
  all'overview, che a mezza larghezza vanno stretti: le bandierine numerate dell'overview si
  sovrappongono prima, e gli otto pad occupano quasi tutta la riga senza lasciare spazio alla
  nota su hover — che a quel punto conviene spostare sotto i pad su una seconda riga.
  **Ed è successo davvero**: con i pad a larghezza fissa la riga ne pretendeva 396 e la fascia
  diventava più larga della finestra — fader di pitch del deck B e mezzo mixer fuori dallo
  schermo. Pad elastici fino a 26 punti, fader del mixer elastici, nota sotto i pad quando è
  stretto. Menu **Vista**, ⌥⌘D, preferenza ricordata, impilata di default
- [x] `done` — **Scattare la foto dell'etichetta dall'app.** `CameraController` +
  `LabelCameraSheet`: elenco dei device con l'**iPhone via Continuity per primo** — inquadra un
  disco in mano molto meglio di una webcam sopra lo schermo — anteprima dal vivo, scatto salvato
  come le altre foto. `NSCameraUsageDescription` in `project.yml`: senza, TCC **termina il
  processo** invece di rifiutare. Da provare al primo scatto, che è quando macOS chiede il
  consenso: quello non è automatizzabile.

---

## Ripartenza a freddo

**Stato:** da M0 a M7 chiuse: **l'app è finita** rispetto al piano. **Il motore audio c'è e suona, e le scalette si costruiscono.** L'import da
YouTube funziona end-to-end ed è stato **provato da Gabriel dall'interfaccia**. L'analisi calcola i
peaks a fine import e le due waveform si disegnano su entrambi i deck, colorate per bande.
Caricando una traccia su un deck l'audio viene decodificato in RAM e il tasto play la fa suonare;
la waveform zoomata scorre a 60 fps sotto la testina. **Il tasto CUE funziona con i tre
comportamenti del CDJ** e il cue è segnato su entrambe le waveform. **Gli otto hot cue
funzionano**, dai pad e dai tasti `1`–`8`, con nome e nota per ognuno, e **sono disegnati su
entrambe le waveform** — bandierine numerate nell'overview, linee colorate nella vista zoomata.
La nota di un hot cue si scrive col clic destro sul pad e si legge passando il puntatore sul pad.
**I memory cue sono fuori scope**: bastano gli otto hot cue. Ci sono anche fader di pitch
verticale, crossfader, gain per deck e i due tasti di nudge, quindi **M4 è chiusa**: due tracce si
possono suonare insieme e mettere in fase.

L'editor delle scalette è completo e **provato pilotando l'app**: riordino trascinando, brani
aggiunti lasciandoli sulla scaletta nella barra laterale, note scritte sul posto.

**Ogni traccia ha BPM e beatgrid.** Il tempo si calcola nella stessa passata dei peaks, la griglia
si disegna in una corsia in cima alla vista zoomata, e il display del BPM del deck apre l'editor
per correggerla — campo BPM, ×2/÷2, tap-tempo, «primo 1 qui», frecce fini; sulla waveform, ⌥ e
trascina. **Il quantize è acceso di default**, a 1/1, e aggancia i cue alla battuta. Sulle cinque
tracce vere in libreria la griglia sta entro 2–8 ms dagli attacchi di cassa per tutta la durata.
Il limite noto è l'**ottava**: 87 con i charleston in levare contro 174 con la cassa su ogni
quarto è ambiguo anche a orecchio, e si raddrizza con ÷2 o ×2.

Da M7: ricerca in libreria (⌘F) con quattro filtri, eliminazione sempre confermata con lo spazio
che libera, scorciatoie complete con il CUE tenuto premuto vero (pannello ⌘/), aggiornamento di
yt-dlp e token di Discogs nelle impostazioni (⌘,), **copertine prese da Discogs all'import**, foto
dell'etichetta sul deck e scattabile con l'iPhone via Continuity, deck impilati o affiancati
(⌥⌘D). E `Scripts/check-render-callback.sh`, che verifica sul codice generato che nel callback
audio non entrino allocazioni, lock o chiamate al runtime.

**Il suono è stato sentito da Gabriel** («funziona»), quindi il motore è verificato all'orecchio e
non solo in rendering offline. Restano da ascoltare con attenzione: che scrub e seek non producano
schiocchi, e che l'anteprima del CUE tenuto premuto attacchi e stacchi pulita.

```bash
cd /Users/gabriel/Desktop/youtube-playlist-creator-dj
./Scripts/fetch-tools.sh                       # solo se Resources/Tools/ è vuota
swift test --package-path DJKit                # 125 test, ~1 s
xcodegen generate && xcodebuild -project Crate.xcodeproj -scheme Crate build
```

Test contro YouTube reale (esclusi dalla suite normale):

```bash
CRATE_NETWORK_TESTS=1 swift test --package-path DJKit --filter ImportIntegration
```

**Provare l'interfaccia si può, e conviene.** Il processo `claude` ha registrazione dello schermo
e Accessibilità, quindi screenshot, clic e trascinamenti sintetici funzionano. Gli strumenti sono
nel repo, con l'uso scritto in testa a ognuno:

```bash
swiftc -O Scripts/window-bounds.swift -o /tmp/window-bounds   # limiti della finestra
swiftc -O Scripts/ui-ax-dump.swift    -o /tmp/ui-ax-dump      # albero AX con le coordinate
swiftc -O Scripts/ui-mouse.swift      -o /tmp/ui-mouse        # click | doubleclick | drag
swiftc -O Scripts/ui-type.swift       -o /tmp/ui-type         # digitare in un campo
swiftc -O Scripts/ui-key.swift        -o /tmp/ui-key          # tasti per codice fisico, e tenuti
osascript -e 'tell application "Crate" to activate'
/tmp/ui-ax-dump $(pgrep -x Crate) AXRow 12                    # dove sono le righe
/tmp/ui-mouse drag 648 204 648 122 30
screencapture -x -R"$(/tmp/window-bounds Crate)" /tmp/crate.png
```

**Per attivare la finestra usa `open -a` sul bundle**, non `activate` via osascript: su questa
macchina altre app si riprendono il primo piano di continuo, e `open -a` la rialza in modo
affidabile. E `keystroke` di System Events porta avanti un'altra app facendo perdere il fuoco:
per scrivere serve `ui-type`, per le scorciatoie a tasto nudo `ui-key` — quelle si riconoscono dal
**codice fisico**, e un evento con stringa unicode ha `keyCode` 0, quindi non scatterebbero.

Le coordinate si prendono dall'albero AX, non misurando i pixel di uno screenshot — e per lo
stesso motivo **quello che si vede in uno screenshot non è una verifica**: dove esiste una misura
numerica sui dati veri, è quella che decide. Le attese brevi dentro un comando funzionano
(`sleep 2`), quelle lunghe usate per aspettare un lavoro no: si aspetta una condizione, per
esempio `until [ "$(sqlite3 … )" = "0" ]; do sleep 5; done` in background.

**Il toolchain Metal va installato a parte**, una tantum, altrimenti la compilazione di
`Waveform.metal` fallisce con "cannot execute tool 'metal'":

```bash
xcodebuild -downloadComponent MetalToolchain
```

**Come lanciare l'app che si è appena compilata.** Il prodotto sta nel DerivedData standard e il
percorso non cambia. Il bundle identifier è unico, quindi `open` da solo non basta: se una copia
vecchia è ancora in esecuzione, macOS porta in primo piano quella.

```bash
osascript -e 'quit app "Crate"'; osascript -e 'delay 2'
open ~/Library/Developer/Xcode/DerivedData/Crate-ccwemjglglgepydupulkiluzdkvq/Build/Products/Debug/Crate.app
```

**Traccia di prova** fornita da Gabriel: `https://www.youtube.com/watch?v=wqf-xIyf5y4` —
"FrescoEdits - Jom", 5:45, m4a AAC 129k, 44,1 kHz stereo. Il link originale portava dietro
`&list=RDjLEvbgq2oEQ&index=7`, ed è il caso su cui è costruito il test del `--no-playlist`.

**Le cinque tracce in libreria sono analizzate**, waveform e BPM compresi: le mancanze si
recuperano dal menu **Deck → Analizza le tracce mancanti**, o una alla volta con ⌥⌘R. Waveform e
tempo escono dalla stessa passata, perché condividono la decodifica, che è la parte cara.

**Il progetto è sotto git** (branch `main`, nessun remote), con tre commit: l'impianto con
l'import da YouTube, *«Waveform, deck audio con CUE e hot cue, editor delle scalette»* che chiude
M3, M4 e M5, e la ripartenza a freddo aggiornata.

## Correzioni dopo la prova di Gabriel (2026-09-05)

- [x] `done` — **La fascia dei deck usciva dallo schermo, e la maniglia era sparita.** Un sintomo
  solo: `ContentView` imponeva l'altezza con `.frame(height:)`, e una fascia più corta del suo
  contenuto non lo comprime — lo lascia debordare **centrato**, quindi tagliato sotto dal bordo
  della finestra e sopra sopra la maniglia, che finiva coperta. Ora è `.frame(minHeight:)`: la
  fascia non scende mai sotto ciò che le serve. In più il pavimento del trascinamento dipende
  dalla disposizione (400 impilati, 240 affiancati) invece di essere un 300 fisso, e la maniglia
  è più alta, più larga e si accende passandoci sopra
- [x] `done` — **Due pulsantini `−` e `+` per il pitch**, ai lati della percentuale: un colpo vale
  **0,05%** (0,064 BPM a 128), con ⇧ **0,5%**, e tenuti premuti si ripetono. Servono perché il
  fader non arriva a quella precisione: con 200 punti di corsa per ±8%, un solo punto vale già
  0,08%. Percentuale e BPM effettivo passati a **due decimali**, o un passo di rifinitura non si
  vedrebbe muovere il numero
- [x] `done` — **Icona dell'app**: un disco visto dall'alto, etichetta arancione come l'accento,
  testina appoggiata. Generata da `Scripts/make-app-icon.swift` in tutte e dieci le misure, con i
  PNG versionati in `App/Assets.xcassets/AppIcon.appiconset`

## Prossimo passo — quello che serve a Gabriel, non al piano

Il piano è finito. Quello che resta è **provare l'app usandola**, che è la sola cosa che qui non
si può automatizzare:

1. **Il token di Discogs**, che va generato e incollato in ⌘, — finché non c'è, la ricerca delle
   copertine è spenta e i comandi sono disabilitati. Dopo, il primo import è la prova vera.
2. **Il primo scatto dell'etichetta**: macOS chiede il consenso alla fotocamera al primo tentativo,
   e con Continuity l'iPhone va sbloccato e vicino perché compaia nell'elenco.
3. **I BPM sulle tracce di Gabriel**: se qualcuno è un'ottava sopra o sotto, ÷2 e ×2 lo
   raddrizzano. La griglia è verificata numericamente contro gli attacchi di cassa, ma un pezzo
   che accelera e rallenta si sente, non si misura.
4. **Le scorciatoie a tasto nudo** si prendono i tasti che le tabelle userebbero per la selezione
   per digitazione: se dà fastidio, il posto dove toglierle è `DeckKeyMonitor.actionByCharacter`.

## Note di implementazione

### Da M6

- **L'autocorrelazione preferisce sistematicamente il periodo lungo, e la somma armonica non lo
  corregge.** Il conto è questo: per un pezzo con la cassa forte sull'uno e colpi più leggeri sugli
  altri quarti, l'autocorrelazione a due quarti di distanza è **più alta** che a un quarto, perché
  il colpo forte ricade sul colpo forte. Sommare i multipli non aiuta — sia il periodo giusto sia
  il suo doppio raccolgono quattro picchi — e la differenza che resta, dovuta al decadimento della
  stima polarizzata, vale il 2%. Un 174 usciva 87. Quello che scioglie il dubbio è una domanda
  diversa: **fra una battuta e l'altra c'è un colpo?** Se c'è, quella è una battuta anche lei.
  `TempoAnalyzer.resolveOctave`, sei righe, e il test sul click track a 174 passa.
- **La precisione sul BPM viene da un ritardo lungo, non da una parabola più furba.** Il picco a
  trenta periodi di distanza si trova con lo stesso mezzo frame di incertezza, ma diviso per trenta
  vale un trentesimo. Serve davvero: 0,1 BPM di errore su un brano di sei minuti sono un quarto di
  secondo di scarto in fondo. La raffinatura si applica solo se il picco lungo cade dove il periodo
  grossolano lo prevedeva (entro il 2%), altrimenti il pezzo non ha un tempo abbastanza fisso e si
  tiene la misura corta.
- **La griglia disegnata sopra la waveform sparisce proprio quando è giusta.** I trattini cadono
  sull'attacco della cassa, che è dipinto quasi bianco e alto quanto tutta la vista, e ci finiscono
  dentro: la griglia si vedeva solo sopra il silenzio. Ci si arriva solo guardando l'app su un
  brano vero — a schermo sembrava che la griglia non venisse disegnata affatto. Rimedio: una
  **corsia dedicata in cima** (`kGridLaneHeight`), con la forma d'onda che si stringe sotto, più
  una linea di misura tenue dentro la waveform. Le bandierine dei cue sono state fatte scendere
  sotto la corsia, o le si sovrapporrebbero.
- **Il trascinamento della griglia scrive in ritardo.** ⌥+trascina manda decine di aggiornamenti al
  secondo: una transazione per ciascuno vorrebbe dire centinaia di scritture su SQLite per un gesto
  solo, e ogni scrittura fa ripartire l'osservazione della libreria. `DeckState` aggiorna subito la
  copia in memoria e salva 250 ms dopo l'ultimo movimento. Cambiando traccia il task **non si
  annulla**: ha già in mano l'identificativo giusto e la scrittura arriva a destinazione.
- **I deck tenevano una copia vecchia della traccia.** `DeckState.track` è una `struct` copiata al
  caricamento: correggendo un BPM dall'ispettore, il deck continuava a quantizzare su quello
  vecchio. `AppModel` ora chiama `refreshTrack(from:)` sull'osservazione della libreria — cosa che
  sistema anche i metadati corretti a traccia caricata, che restavano indietro da M2.
- **Dentro un `Form`, la stringa di un `TextField` diventa un'etichetta, non un segnaposto.** Nel
  campo BPM dell'ispettore comparivano due etichette accanto: "BPM" e "non rilevato". Il testo di
  suggerimento va passato come `prompt`, con `.labelsHidden()`.
- **Il modo giusto di verificare la griglia non è guardarla.** Leggere i pixel di uno screenshot
  porta a scambiare i picchi della forma d'onda per linee di griglia — è successo, e la conclusione
  era sbagliata di un terzo di battuta. La misura che decide è indipendente: inviluppo di energia
  del file audio, attacchi sopra metà del picco, distanza dalla battuta più vicina. Su cinque brani
  veri: mediana da +2,5 a +13 ms, scarto interquartile 2–8 ms.

### Da M5

- **La lista della scaletta osserva il database, non lo legge una volta.** Una riga può cambiare
  da fuori — cancellando una traccia dalla libreria la sua riga resta come segnaposto — e con una
  lettura sola la scaletta mostrerebbe ancora il titolo di un brano che non c'è più.
  `observeEntries(playlistID:).values(in:)` è un `AsyncSequence`: sta dentro un `.task(id:)` e si
  cancella da sé cambiando scaletta.
- **Il riordino è ottimistico.** `onMove` riscrive subito l'array locale e poi manda il nuovo
  ordine al database; aspettare il giro dall'osservazione farebbe tornare indietro la riga sotto
  il dito per un fotogramma.
- **Il payload del drag è l'identificativo della traccia, una stringa.** Un tipo `Transferable`
  proprio avrebbe voluto un UTI dichiarato nell'`Info.plist`, che per un trascinamento interno
  all'app non paga: chi riceve filtra gli id contro la libreria (`known(_:)`) e qualsiasi altro
  testo trascinato dentro viene ignorato invece di diventare una riga fantasma.
- **Le righe della libreria sono trascinabili solo con la forma esplicita di `Table`**
  (`Table(of:selection:sortOrder:columns:rows:)` con `TableRow(track).draggable(...)`): con la
  forma breve `Table(sortedTracks, …)` le righe non esistono come viste e non c'è dove attaccare
  il drag.
- **Un gesto sul contenuto di una riga di `List` si mangia tutti gli eventi del mouse di quella
  riga.** `PlaylistTrackRow` aveva `.contentShape(Rectangle())` più un
  `.simultaneousGesture(TapGesture(count: 2))` per il doppio clic: con quello attaccato la riga
  **non si selezionava e non si riordinava trascinando**, perché la lista non vedeva più il mouse.
  Nemmeno `simultaneousGesture` salva, malgrado il nome. Diagnosi fatta pilotando l'app: clic
  esatto al centro della riga (coordinate prese dall'albero AX) → nessuna selezione; tolto il
  gesto → selezione e riordino funzionanti. **Il caricamento sul deck resta sui tastini A/B e sul
  menu contestuale**, che sono `Button` e il clic lo ricevono sempre.
- **`onMove` e `dropDestination` sul `ForEach` convivono**: verificato, si riordina e si
  inserisce senza che uno rubi l'altro. Il sospetto opposto, scritto qui prima, era sbagliato.
- **`onMove` e il trascinamento di una riga altrove sono però lo stesso gesto: se ne sceglie uno.**
  Il riordino usa `onMove`, quindi una riga di scaletta non si può trascinare su un deck. Fra i
  due, quello che serve tutti i giorni è il riordino.
- **I brani si aggiungono a una scaletta trascinandoli sulla sua riga nella barra laterale**, come
  in Musica — e non poteva che essere lì: libreria ed editor di scaletta sono due viste
  *alternative* dello stesso pannello, quindi mentre guardi la libreria la scaletta non è sullo
  schermo e non c'è nessun posto dove lasciar cadere il brano. È il motivo per cui Gabriel non
  riusciva ad aggiungerli, e per cui il `dropDestination` dentro l'editor — che pure funziona —
  non serviva a niente. Nell'editor resta buono per riordinare.
- **Il drop esterno sta sul `ForEach`** (`DynamicViewContent.dropDestination`): è l'unico che
  riceve **l'indice di inserimento** e dà l'indicatore fra le righe. Attenzione all'ordine degli
  argomenti della closure: `(elementi, indice)`.
- **`RowDrag` è un tipo suo invece della semplice stringa dell'id**, così un testo qualsiasi
  trascinato dentro non viene scambiato per un brano; la seconda rappresentazione, testo semplice,
  serve a chi si aspetta comunque una stringa.
- **Dentro un `List` con selezione, il clic va alla lista.** Ne sono venuti due bug segnalati da
  Gabriel il 2026-09-04: un `TextField` in una riga non prendeva mai il fuoco (le note non si
  potevano scrivere) e il doppio clic per caricare sul deck arrivava quando voleva. Rimedi: la
  nota a riposo è un `Button` che entra in modifica e porta il fuoco al campo con `@FocusState`,
  e il caricamento ha due tastini **A**/**B** — un `Button` il clic lo riceve sempre. Il doppio
  clic resta come `simultaneousGesture`, che lascia passare anche la selezione.
- **`VSplitView` non propaga ai figli l'inset della toolbar della finestra**: il contenuto partiva
  dal bordo superiore e il titolo della scaletta finiva scritto **sopra la prima riga**. È stato
  sostituito da una `VStack` con `DeckBarDivider`, una maniglia scritta a mano: l'altezza della
  fascia dei deck è ora un numero nostro, ricordato fra un avvio e l'altro, e non una divisione
  che il framework ricalcola ogni volta che cambia la vista sopra — che era anche il motivo per
  cui entrando in una scaletta la fascia si schiacciava al minimo. Il riassunto della scaletta è
  passato da `navigationSubtitle` a un'intestazione dentro il contenuto.
- **La libreria ha anche «Aggiungi alla scaletta» nel menu contestuale**, che funziona su una
  selezione multipla e non dipende dal drag & drop: venti pezzi trascinati uno per uno non sono un
  modo di lavorare. Le tracce vengono passate **nell'ordine della tabella**, perché un `Set` non
  ha ordine e l'ordine è proprio ciò che conta in una scaletta.
- **Con una scaletta vuota la fascia dei deck finisce sul suo pavimento**, perché
  `ContentUnavailableView` si prende tutta l'altezza che può: la waveform zoomata diventava una
  striscia. Il minimo della zoomata è passato a 80 punti e quello della fascia a 340, così anche
  schiacciata resta leggibile.
- **La numerazione conta solo i brani.** Le note stanno nella stessa lista ma non prendono un
  numero, altrimenti «il quinto pezzo» smetterebbe di voler dire qualcosa.

### Da M4

- **Il render block audio non deve ereditare l'isolamento del main actor.**
  `AVAudioSourceNodeRenderBlock` è un blocco Objective-C importato senza `@Sendable`: una closure
  creata dentro un `init` marcato `@MainActor` ne eredita l'isolamento, e il compilatore le mette
  in testa un controllo di esecutore. Il thread audio non è la coda principale, quindi al primo
  buffer `dispatch_assert_queue` fa `SIGTRAP`: **l'app moriva appena si premeva play**, con tutti
  i test verdi. Il blocco va costruito in un metodo `nonisolated` e la closure dichiarata
  `@Sendable` (`DeckEngine.makeRenderBlock`). Questa è la trappola peggiore di tutta la M4: non è
  un errore di compilazione, non è un avviso, e i test in rendering manuale la mancano perché
  `renderOffline` chiamato dal main thread supera il controllo. Per questo il test di regressione
  rende da un `Task.detached`; se l'isolamento torna, quel test non fallisce, **fa cadere il
  processo di test con un trap**.
- **I test del deck abilitano il rendering manuale *prima* di collegare i nodi.** Collegando
  prima, l'engine istanzia l'uscita hardware per sapere che formato ha e passa dal HAL: se in quel
  momento il device è occupato — l'app aperta, un altro engine che sta partendo — `start()`
  fallisce con `-80802` dopo un paio di secondi. È successo una volta, dodici test insieme, e al
  giro dopo erano tutti verdi. Con `enableManualRenderingMode` in testa l'hardware non c'entra
  più: la suite è tornata deterministica e più veloce (0,35 s contro 0,45).
- **Il fader di pitch ha il più in basso**, come un SL-1200 e come un CDJ: spingere verso il basso
  accelera. Invertirlo allenerebbe il gesto sbagliato, ed è tutto il senso dell'app. È scritto a
  mano e non con `Slider` per tre motivi: `Slider` è orizzontale e ruotarlo porta dietro guai di
  layout, serve il **fermo allo zero** (che è ciò che permette di tornare a velocità nominale
  senza guardare) e servono le tacche a ±4 e ±8.
- **Nudge e bend sono due gesti diversi, non due tarature dello stesso.** Il colpetto sposta la
  testina di 10 ms: preciso, si usa guardando la waveform, e si sente appena come uno scarto. La
  spinta tenuta accelera del 3% finché il tasto è premuto: sposta la fase **senza schiocco**, e si
  usa a orecchio mentre le due tracce suonano. Sullo stesso tasto si distinguono a tempo — sotto
  250 ms è un colpetto — e il ritardo prima che la spinta parta non si nota perché una spinta la
  si tiene comunque. La spinta si somma al fader senza spostarlo, e caricare una traccia la
  azzera (il fader invece resta: è un comando fisico).
- **Il BPM effettivo non include la spinta**: farebbe ballare il numero proprio mentre lo si
  legge, e quello che serve sapere è dove si è messo il fader.
- **Il fermo al centro del crossfader sta nel setter di `AppModel.crossfader`, non nella vista**,
  così vale per qualunque cosa lo muova. Stesso motivo per cui il clamp del pitch sta in
  `DeckState`: la vista non è l'unico scrittore possibile.
- **Un cue senza slot è un residuo, non una funzione.** I memory cue sono fuori scope dal
  2026-09-04. `hotcueSlot` resta annullabile perché è così che `assignHotCue` libera uno slot
  senza violare l'indice unico, e il marker grigio col triangolino continua a disegnarli se
  capitano: costa zero e vale come rete. Non ci si costruisca sopra una funzione.
- **I marker della vista zoomata stanno nello shader, quelli dell'overview in SwiftUI**, e la
  differenza non è un'incoerenza: nell'overview i marker **non scorrono** — la loro x dipende solo
  da posizione e durata — quindi non c'è niente da tenere in sincrono e ci si può scrivere sopra
  il numero dello slot, che uno shader non saprebbe disegnare. Nella vista zoomata scorrono a
  60 fps mentre SwiftUI si aggiorna a 20: là un overlay resterebbe indietro di qualche pixel.
- **Nel buffer dei marker un `float4`, non una struct con un `float3`.** In Metal `float3` si
  allinea a 16 byte, quindi `{float bin; float3 color;}` diventerebbe 32 byte con un buco in
  mezzo, e il layout andrebbe tenuto d'accordo a mano con Swift. Un `float4` — `.x` la posizione
  in bin, `.yzw` il colore — è 16 byte da entrambe le parti e non c'è niente da ricordare.
- **Il buffer dei marker si ricarica solo se cambia la lista *o il livello di zoom*.** Le
  posizioni sono in bin, e il `binSize` cambia zoomando: senza il `binSize` nella chiave della
  cache i marker resterebbero dove stavano prima della zoomata. Ricostruirlo a ogni disegno
  sarebbe invece un'allocazione sessanta volte al secondo per una decina di numeri.
- **I marker si disegnano nell'ordine in cui arrivano e l'ultimo vince**: per questo il cue di
  lavoro è in fondo a `DeckState.cueMarkers`, così dove due cadono nello stesso pixel resta
  visibile quello che si muove.
- **`hotCues` è derivato da `cuePoints`, non memorizzato.** La fonte è una sola lista, quella che
  sta nel database: tenere due contenitori separati significherebbe poterli far divergere. Le
  scritture passano da `upsert`, che replica anche il declassamento a memory cue del vecchio
  occupante di uno slot — la stessa cosa che fa `assignHotCue` in SQL.
- **La bandierina del marker zoomato è in pixel del drawable, non in punti**: sono 12 px di
  altezza, cioè 6 punti su Retina. Su uno schermo non Retina risulterebbe il doppio; non è un
  problema oggi e non vale una uniform in più per la scala.
- **Il pad di un hot cue salta e *suona*, anche se il deck era in pausa.** È il comportamento del
  CDJ («premi un HOT CUE: la riproduzione parte da quel punto») ed è quello che serve alla
  preparazione: si marcano otto punti e li si ascolta uno dietro l'altro. **Corregge una nota
  scritta qui durante M4**, che diceva l'opposto — «in pausa salta e resta fermo» — e che era una
  mia supposizione, non il manuale. Diverso dal CUE, che in pausa sul cue suona solo mentre lo si
  tiene premuto. Un pad **vuoto** invece memorizza il punto in cui si è, sempre come il CDJ.
- **Il fuoco del deck esiste perché la tastiera è una e i deck sono due.** `1`–`8` agiscono sul
  deck che ha `AppModel.focusedDeckSlot`, che si sposta caricando una traccia o toccando un
  controllo di quel deck, e si vede dalla barra accesa sul bordo sinistro della fascia. Serve
  anche a M7: qualsiasi scorciatoia di trasporto avrà lo stesso problema.
- **I tasti degli hot cue sono un monitor `NSEvent`, non voci di menu con scorciatoia.** Su macOS
  le *key equivalent* dei menu vengono valutate **prima** del first responder: una cifra senza
  modificatori scavalcherebbe i campi di testo, e digitare «1» nel campo dell'URL farebbe scattare
  un hot cue. Il monitor invece guarda l'evento e lo lascia passare quando il first responder è un
  `NSTextView` (il *field editor* di qualsiasi `TextField`) o quando c'è un foglio aperto.
- **Il monitor legge `keyCode`, non i caratteri.** Con lo shift premuto
  `charactersIgnoringModifiers` restituisce `!` invece di `1` (e altro ancora su layout non ANSI),
  quindi leggere i caratteri farebbe fallire proprio la combinazione che cancella l'hot cue. I
  `keyCode` sono posizioni fisiche e valgono su qualsiasi layout.
- **Lo shift sul clic si legge da `NSEvent.modifierFlags`**: un `Button` di SwiftUI non riporta
  quali modificatori erano premuti. È lo stato corrente della tastiera, letto dentro l'azione.
- **`NSEvent` non è `Sendable`**: oltre il confine di `MainActor.assumeIsolated` passano solo
  `keyCode` e `modifierFlags.rawValue`, non l'evento.
- **La riga dei pad sta sotto la waveform zoomata**, non nella colonna di sinistra: otto pad in
  quella colonna avrebbero richiesto di allargarla, e la larghezza è ciò che serve alle waveform.
  Ha portato la fascia dei deck da 220 a 290 punti di altezza minima (`ContentView`).
- **Le scritture dei cue sono ottimistiche**: il pad si accende sotto il dito e la scrittura su
  SQLite segue; se fallisce, `DeckState` rilegge dal database e segnala l'errore. Non c'è
  `ValueObservation` perché **oggi il deck è l'unico che scrive i propri cue**. Appena l'ispettore
  potrà modificarli, quella premessa cade e serve `observeCuePoints(trackID:)`, altrimenti i pad
  restano indietro. Vale già ora, in piccolo, se la stessa traccia è caricata sui due deck.
- **I colori degli hot cue saltano il rosso puro e il bianco**: sono della testina e del cue di
  lavoro. Con i marker sulla waveform un pad rosso sarebbe indistinguibile dalla testina.
- **Il tasto CUE ha tre comportamenti perché legge lo stato del deck**, e il terzo è quello che
  sorprende: in pausa a metà pezzo, premere CUE **sposta** il cue lì invece di riportare indietro
  la testina. È il comportamento del CDJ e va tenuto così — quello che si impara sull'app deve
  valere davanti al piatto. Eccezione aggiunta: arrivati in fondo alla traccia il tasto fa *back
  cue* come in play, perché lì il deck si è fermato da sé e piazzare il cue sull'ultimo frame non
  servirebbe a niente.
- **Il timer interno di `MTKView` si ferma dentro i loop di tracking di AppKit.** Tenendo premuto
  uno `Slider`, il divisore di una split view o una barra di scorrimento, il run loop passa in
  modalità di tracking e i timer registrati nella modalità normale non scattano più: la waveform
  si inchiodava mentre si muoveva il crossfader. Segnalato da Gabriel due volte, il 2026-09-04.
  Ora il movimento lo dà un `CADisplayLink` creato con `NSView.displayLink(target:selector:)` e
  **aggiunto in `.common`**, che batte anche durante il tracking; la `MTKView` resta sempre in
  modalità su richiesta e il link chiama `draw()`. Vale per qualsiasi controllo AppKit, non solo
  per il crossfader.
- **I fader del mixer sono scritti a mano per lo stesso motivo.** Uno `Slider` di macOS è un
  controllo AppKit e apre un loop di tracking; un `DragGesture` di SwiftUI no. Con il display
  link in `.common` il problema sarebbe già risolto, ma i fader propri restano: il gesto è più
  diretto e somigliano a quelli di un mixer invece che a controlli di sistema.
- **Una vista che contiene una closure risulta sempre «cambiata».** SwiftUI confronta le viste
  per decidere cosa rifare, e una closure non è confrontabile: `WaveformZoomView`, che porta
  dentro `livePosition`, finiva quindi in `updateNSView` a **ogni** rivalutazione del `body` che
  la conteneva — e siccome stava nello stesso `body` del fader di pitch, trascinare il fader la
  ridisegnava sessanta volte al secondo. Da lì lo scatto segnalato da Gabriel il 2026-09-04. Due
  rimedi, entrambi applicati: la colonna delle waveform è una vista a sé (`DeckWaveforms`), che
  ha come unico dato un riferimento a `DeckState` e quindi viene saltata quando il padre si rifà;
  e `updateNSView` scrive `isPaused`/`enableSetNeedsDisplay` **solo se cambiano**, perché
  riscrivere `isPaused` rimette in piedi il timer di disegno della `MTKView`.
- **Ogni stato del motore che serve a una vista va ricopiato in `DeckState`.** `DeckEngine` vive
  fuori da `@Observable`: leggerlo da un `body` compila, funziona a prima vista e poi non si
  aggiorna. Succede con `hasTrack`, che finita la decodifica lasciava il tasto play disabilitato
  finché non si toccava qualcos'altro — segnalato da Gabriel il 2026-09-04 e risolto con la copia
  osservabile `isAudioReady`. Il sintomo è sempre lo stesso: *«devo muovere qualcosa perché la UI
  si accorga»*.
- **La logica del CUE sta in `DeckEngine`, non in `DeckState`.** Nel target app non c'è suite di
  test; in `DJKit` la stessa macchina a stati si verifica in rendering manuale offline, dove
  l'anteprima e il ritorno al cue si misurano sul playhead vero. `DeckState` si limita a
  ricopiare ciò che il motore ha deciso, in `syncAfterTransport()`: se qualcosa non si aggiorna
  nella fascia del deck, è quasi sempre una chiamata al motore senza quella riga dietro.
- **Il cue di lavoro vive in RAM, non in tabella.** I punti *annotati* — hot cue e memory cue —
  sono un'altra cosa e hanno la loro riga nel database. Quando arriveranno, un default sensato per
  il cue al caricamento sarà il primo memory cue della traccia invece di zero.
- **`Button` non basta per il CUE**: reagisce al rilascio, mentre il *press-and-hold* ha bisogno
  di sapere quando il tasto viene premuto. `CueButton` usa un `DragGesture(minimumDistance: 0)`,
  che scatta al mouse down e finisce al mouse up anche se il puntatore è uscito dal tasto —
  quindi un rilascio non può restare in sospeso. `onChanged` arriva a ogni movimento, quindi la
  pressione va protetta da un flag o parte più volte.
- **Il marker del cue nella vista zoomata sta dentro lo shader**, non in un overlay SwiftUI: la
  waveform scorre a 60 fps mentre la UI si aggiorna a 20, quindi un overlay resterebbe indietro
  di qualche pixel e sembrerebbe scollato. Calcolato dalle stesse uniform è inchiodato alla
  waveform per costruzione. Nell'overview, dove tutta la traccia sta in poche centinaia di pixel,
  un overlay va benissimo. `WaveformPalette.cue` e `kCueColor` in `Waveform.metal` sono due copie
  della stessa terna, come già per le bande.
- **Nel render callback non entra nessun oggetto Swift.** Il main pubblica un `DeckTrackRef` —
  due puntatori ai canali più quattro numeri, in memoria raw — e ne scambia l'indirizzo con
  un'atomica; il riferimento forte al `DecodedTrack` resta sul main. Risalire all'oggetto da un
  `Unmanaged` dentro il callback sembra equivalente e non lo è: legarlo a una variabile locale
  genera una retain/release, cioè una chiamata di runtime con un lock dentro.
- **Il rilascio differito aspetta il contatore di render, non un timeout a caso.** `DeckRenderState`
  alza `renderTick` **alla fine** di ogni render: se il contatore è avanzato oltre il valore che
  aveva allo scambio, il thread audio ha già riletto il puntatore nuovo e la memoria vecchia si
  può liberare. Il tetto di 200 ms serve solo al caso del grafo fermo, in cui nessuno legge e
  quindi il contatore non avanzerà mai. Se il tick venisse alzato all'inizio del render la
  garanzia cadrebbe e si libererebbe memoria ancora in uso.
- **`Synchronization.Atomic` richiede macOS 15**, quindi `DJKit/Package.swift` è passato da
  `.macOS(.v14)` a `.macOS(.v15)`. L'app punta comunque a macOS 26.
- **Lo stato che appartiene solo al thread audio sta in un `UnsafeMutablePointer<Scratch>`**
  (posizione fra i buffer, ultimo seek visto, descrittore adottato). Con Swift 6 mutare una `var`
  di classe da dentro il callback obbligherebbe a un `@unchecked Sendable` che nasconde il
  problema invece di risolverlo; la memoria raw dice cosa è davvero condiviso e cosa no.
- **Il seek passa da un contatore, non dal valore.** Se il main scrivesse direttamente il playhead,
  il render già in volo lo sovrascriverebbe col valore vecchio. Il main scrive `seekTarget` e
  incrementa `seekCounter`; il callback adotta il target solo quando il contatore è cambiato. Il
  playhead *pubblicato* viene aggiornato subito dal main, così la testina segue il dito senza
  aspettare il buffer successivo.
- **La conversione di frequenza è gratis**: `baseStep = sampleRate del file / sampleRate del grafo`,
  moltiplicato per il rate del varispeed. Un file a 44,1 kHz su un grafo a 48 kHz avanza di 0,919
  frame per frame di uscita, con la stessa interpolazione. Il formato dei nodi resta **fisso** per
  tutta la vita del grafo: se al cambio di device si ricalcolasse il passo sulla nuova frequenza,
  il pitch di ciò che sta suonando si sposterebbe. La conversione verso l'hardware la fa il mixer.
- **Su una rampa lineare la Catmull-Rom è esatta.** È la proprietà su cui poggiano i test del
  varispeed: a rate 0,5 il sample numero *i* deve valere esattamente `inizio + 0,5·i`, quindi il
  valore atteso si può scrivere in chiaro invece di confrontare due implementazioni.
- **Il render callback si prova senza device audio.** `DeckRenderStateTests` gli passa un
  `AudioBufferList` finto; `DeckEngineTests` monta il deck in un vero `AVAudioEngine` in
  `enableManualRenderingMode(.offline)` e verifica che dal `AVAudioSourceNode` esca il segnale
  caricato — cioè che grafo e formato coincidano. Senza questo, l'unico modo di scoprire un grafo
  scollegato sarebbe il silenzio a orecchio.
- **La `MTKView` ha due modalità, non una.** Mentre il deck suona gira a 60 fps e chiede la
  posizione a `DeckEngine.positionSeconds` (`nonisolated`, due letture atomiche) a ogni frame:
  SwiftUI non c'entra. Da ferma torna in modalità su richiesta. `isPaused` e
  `enableSetNeedsDisplay` vanno tenuti l'uno l'opposto dell'altro.
- **Due frequenze per la stessa posizione, di proposito.** `DeckState.playheadSeconds` si aggiorna
  a 20 Hz da un `Task` e alimenta timecode e overview, dove un ventesimo di secondo non si vede;
  la waveform zoomata legge il motore a 60 fps. Ricostruire l'albero SwiftUI sessanta volte al
  secondo per far scorrere una texture sarebbe lavoro buttato.
- **In fondo alla traccia `play` non fa niente**, come un piatto arrivato al centro del disco. Far
  ripartire da capo un pezzo finito, in mezzo a un set, sarebbe peggio di un pulsante che non
  risponde: basta riportare indietro la testina. `hasReachedEnd` si azzera al primo seek.
- **Il crossfader è a potenza costante** (`cos`/`sin`): a metà corsa i due deck stanno entrambi a
  0,707, così suonando insieme la somma non satura. Si moltiplica al gain del deck, e il prodotto
  finisce in `outputVolume` del mixer di quel deck.
- **Il caricamento su un deck ferma il deck.** Decodificare 130 MB dura qualche decimo di secondo:
  nel frattempo l'utente può aver caricato un'altra traccia sullo stesso deck, quindi prima di
  passare l'audio al motore si ricontrolla che la traccia sia ancora quella richiesta.
- **Il grafo audio si crea a parte dal resto di `AppModel`**: se l'uscita non si configura, la
  libreria resta usabile e sono solo i deck a restare muti. Il grafo poi **parte al primo play**,
  non al lancio, così l'app non tiene occupato il device quando non sta suonando.

### Da M3

- **Normalizzazione della FFT.** Il livello RMS di banda è
  `sqrt(Σ|V|²) / (N · √0,75)`, dove `V` è l'uscita di `vDSP_fft_zrip` e 0,75 tiene insieme la
  potenza della finestra di Hann (`Σw²/N = 0,375`) e il fattore 2 con cui vDSP scala l'uscita
  reale. Verificata dai test: una sinusoide a fondo scala in una banda dà 0,707, cioè il suo RMS
  vero. Se si cambia finestra va rifatto il conto.
- **La finestra della STFT è 1024 con passo 256, non una FFT per bin da 64.** Una FFT su 64
  sample dà 689 Hz di risoluzione: il taglio a 200 Hz non sarebbe collocabile. Con 1024 si hanno
  43 Hz e 23 ms — corti abbastanza da non spalmare l'attacco della cassa. Il livello da 64
  eredita il colore dal bin da 256 che lo contiene: 5,8 ms di quantizzazione, sotto il pixel
  anche alla massima zoomata.
- **La sagoma sale per aggregazione esatta, il colore in RMS.** `max` di un bin grosso è
  esattamente il `max` dei bin fini che contiene — c'è un test che lo verifica su tutti e tre i
  livelli. I livelli di banda si combinano invece come radice della media dei quadrati.
- **Il colore ha bisogno di guadagni di presentazione, i dati no.** Misurato su un brano vero,
  l'RMS medio nei passaggi forti è **low 0,278 · mid 0,100 · high 0,011**: mescolando i rapporti
  grezzi ogni waveform sarebbe blu dall'inizio alla fine. I guadagni **1 / 3 / 12** stanno in
  `WaveformPalette.bandGain` *e* in `Waveform.metal` (`kBandGain`) — sono due copie, vanno
  cambiate insieme. Nel file `.peaks` restano i valori veri.
- **Le uniform dello shader sono in bin, non in frame.** Un brano lungo supera i 15 milioni di
  frame, oltre la precisione di un `float`; in bin sono qualche centinaio di migliaia e l'errore
  resta sotto il sample.
- **La `MTKView` non ricostruisce geometria a ogni frame**: la cache sta in un `MTLBuffer` e il
  fragment shader decide colonna per colonna, quindi far scorrere la waveform costa cinque
  numeri. È per questo che in M4 passare a 60 fps è stato solo un cambio di flag — vedi
  "due modalità, non una" in *Da M4*.
- **`TrackAnalyzer` riscrive solo le colonne dell'analisi**, mai la traccia intera: l'analisi dura
  secondi e nel frattempo l'ispettore può aver salvato metadati corretti a mano. C'è un test.
- **Swift 6 e `Identifiable` su una classe `@MainActor`**: la conformità va marcata `nonisolated`
  (`nonisolated let slot`, `nonisolated var id`), altrimenti è un errore di compilazione, non un
  avviso.
- **Il toolchain Metal non è incluso in Xcode**: va scaricato una volta con
  `xcodebuild -downloadComponent MetalToolchain`, altrimenti `Waveform.metal` non compila.
- **La fascia dei deck è già condivisa fra Libreria e Scaletta.** `DeckBarView` sta nel `detail`
  del `NavigationSplitView`, dentro il `VSplitView` e **fuori** dallo switch sulla selezione della
  barra laterale: cambiando vista i deck restano dove sono, con le tracce caricate. Domanda posta
  da Gabriel il 2026-09-04 e verificata: non c'è niente da spostare o da condividere.
- **I controlli di trasporto erano segnaposto disattivati**, non codice mancante: marcavano lo
  spazio di play e CUE. Da M4 il play è vivo; **CUE resta disattivato** finché non arriva il suo
  task. Riscrivendo `DeckBarView` per M3 erano stati tolti per distrazione e sono stati rimessi —
  se spariscono di nuovo è una regressione, non una scelta.
- **Misure su un brano reale di 6:32** (44,1 kHz stereo): decodifica **0,27 s** per **132 MB** in
  RAM, peaks **0,29 s**, file `.peaks` **1,71 MB** — dentro il budget di 1–2 MB dichiarato nel
  piano.

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
- **Gli screenshot dell'app si possono fare** (aggiornato il 2026-09-04: la nota diceva il
  contrario). La registrazione dello schermo è concessa a `claude`, quindi
  `screencapture -x -R"x,y,w,h"` funziona; i limiti della sola finestra di Crate li dà
  `Scripts/window-bounds.swift`, che legge `CGWindowListCopyWindowInfo` e non richiede
  Accessibilità. **Guardare la finestra prima di ipotizzare**: il titolo della scaletta
  sovrapposto alla prima riga si è capito in dieci secondi da uno screenshot, dopo due tentativi
  a vuoto fatti a ragionamento.
- **I click e i trascinamenti simulati richiedono l'Accessibilità** per `claude`
  (*Impostazioni di Sistema → Privacy e sicurezza → Accessibilità*); senza, `osascript` fallisce
  con `-1719` appena chiede la geometria di una finestra. Finché manca, le interazioni le prova
  Gabriel — oppure si copre il codice sottostante con un test che eserciti lo stesso percorso
  senza UI, come fa `ImportIntegrationTests` con `ImportQueue`.

## Questioni aperte

- **Crash da `@Environment(AppModel.self)`, 2026-09-04 16:26** (`Crate-2026-09-04-162656.ips`).
  Assertion di SwiftUI dentro `NSHostingView.layout()`: una vista ha cercato `AppModel`
  nell'environment e non l'ha trovato — con `@Environment` di un `@Observable` questo **fa cadere
  l'app**, non restituisce `nil`. Era la build pre-M4. Il sospetto principale è l'ispettore, che
  su macOS è una colonna ospitata a parte come il foglio di import (a cui l'`environment` era già
  stato reiniettato a mano durante M2, probabilmente per lo stesso motivo): ora `LibraryView`
  glielo passa esplicitamente. **Non è una diagnosi certa**: se ricapita, serve sapere cosa si
  stava facendo — aprire l'ispettore, un clic destro su una riga, trascinare una foto.

Nessun'altra in sospeso. Le decisioni prese in autonomia sono elencate in fondo a `PLAN.md` e sono
state approvate.

Chiuse durante M3, per non riaprirle:

- *«La waveform non andrebbe messa sotto, condivisa con la playlist?»* — lo è già, vedi la nota
  in fondo a "Da M3".
- *«Non vedo i tasti»* — erano segnaposto disattivati; da M4 il play funziona e resta segnaposto
  solo il CUE, vedi la stessa sezione.
