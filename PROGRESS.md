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

## M8 — Chiesto da Gabriel il 2026-09-05 · **in-progress**

Tre richieste arrivate insieme, in ordine di quanto sono definite. **La prima è chiusa**, le
altre due no.

### 1. Salto di 8 · 16 · 32 · 64 battute — **done**

- [x] `done` — `Beatgrid.seconds(afterJumping:fromSeconds:snappingTo:)` in `DJKit`, più
  `BeatJumpSize` (8/16/32/64, con `bars` per dirle anche in misure). Cinque test nuovi in
  `BeatgridTests`, fra cui i due che contano: partendo 12 ms fuori battuta, quattro salti agganciati
  atterrano esatti; senza aggancio lo scarto se lo portano dietro tutti
- [x] `done` — `DeckState.jump(beats:)` e `jump(forward:)`: passano dalla griglia quando il
  quantize è acceso, e da `seek`, che tiene la testina dentro la traccia
- [x] `done` — La taglia è **per deck** (`DeckState.beatJumpSize`), non una per l'app come il
  quantize: 32 per raggiungere il ritornello su A mentre su B si rifinisce di 8 sono due cose
  diverse, non un doppione. Si ricorda fra un avvio e l'altro in `beatJump.A` / `beatJump.B`
- [x] `done` — `BeatJumpControl`: `◀ 16 ▶` nella riga degli hot cue, a destra prima di «zoom 8 s».
  Il numero in mezzo è il menu della taglia, così si legge sempre di quanto si sta per saltare.
  Senza griglia i tre comandi sono spenti. Tenendo premuto un tasto si ripete
- [x] `done` — Scorciatoie `,` e `.` in `DeckKeyMonitor`, con la riga nel pannello ⌘/. Le
  ripetizioni del sistema fanno ripetere il salto (`repeatsWhenHeld`), che è diverso dalla
  pressione tenuta di CUE e nudge — lì tenere premuto è un gesto *altro*, qui è lo stesso ripetuto
- [x] `done` — `.accessibilityLabel` sui due tasti: senza, l'albero AX leggeva il nome del simbolo,
  «Go To Start» e «Go To End», che qui vogliono dire l'opposto
- [x] `done` — **Minimo della fascia affiancata rimisurato: 205 → 209.** La riga sotto i pad
  passa da 12 a 18 punti perché adesso porta anche i tasti di salto. Impilati resta 348, invariato:
  lì il controllo sta nella riga dei pad, che è più alta di lui
- [x] `done` — **Provato pilotando l'app**, con la misura numerica e non a occhio. Su «Opa»
  (124,9996 BPM, downbeat a 1,0456 s) da fermo a inizio traccia, taglia 16: `.` porta a **0:07.7**
  e non a 0:07.6, cioè il salto è agganciato alla battuta e non è 16 battute nude; poi 0:15.4 e
  0:23.1, e `,` ripercorre gli stessi punti fino a 0:00.0, dove si ferma. Con il quantize spento
  (⌥⌘Q) un salto da 64 partito da un punto qualsiasi dell'overview sposta di **30,7 s esatti**,
  cioè non aggancia; riacceso, lo stesso salto atterra a 4:50.9 invece di 4:51.0. Tenendo premuto
  `.` per un secondo la testina fa undici salti e `,` la riporta esattamente dov'era. Taglia scelta
  dal menu e ritrovata dopo il riavvio, con A a 64 e B a 16 indipendenti
- [x] `done` — `swift test --package-path DJKit`: **152 test verdi** · `xcodebuild`: BUILD SUCCEEDED

### 2. Tag ("disco", "funky", …) da configurare e assegnare — `todo`

**Sposta un confine di scope scritto in `CLAUDE.md`**, e va scritto lì quando si fa: i metadati
erano volutamente quattro — titolo, artista, album, foto — «niente genere, anno, rating». I tag non
sono un campo fisso in più: sono una dimensione che se la definisce l'utente, e servono a
ritrovare i dischi. La decisione è di Gabriel del 2026-09-05.

- Schema: migrazione **`v2`** — non toccare la `v1`. Tabella `tag` (`id`, `name`, `colorIndex`,
  `position`) e tabella ponte `trackTag` (`trackID`, `tagID`, chiave primaria composta, cascata su
  entrambe). La `position` serve a ordinarli a mano come le scalette.
- `TagRepository` in `DJKit/Persistence/`, con `ValueObservation` come gli altri.
- Filtro: `LibraryFilter.Scope` ha già quattro casi; aggiungere `case tag(String)` e ricordarsi che
  `Scope` è `CaseIterable` — con un caso associato non lo è più, quindi il picker in toolbar va
  costruito dalla lista dei tag invece che da `allCases`.
- Assegnazione: menu contestuale della libreria (vale anche su selezione multipla, come
  «Aggiungi alla scaletta») e una sezione nell'ispettore.
- Gestione: sezione nella barra laterale sotto le scalette, con rinomina e colore.

### 3. Riconoscere il disco dalla videocamera → Discogs → scaricare l'album — `todo`, da decidere

**Si può fare, ed è tre cose separate.** Ognuna è utile da sola, e conviene farle in
quest'ordine perché ognuna verifica la precedente.

**a. Leggere il disco inquadrato.** `AVCaptureSession` c'è già (`CameraController`, M7). Due
strade, e la seconda è quella buona:
- OCR dell'etichetta con `VNRecognizeTextRequest`: legge artista, titolo e **numero di catalogo**.
  Su un'etichetta ferma e ben illuminata funziona; su una inclinata o che gira, no.
- **Codice a barre della copertina** con `VNDetectBarcodesRequest`: molto più affidabile, perché è
  un identificatore esatto invece di testo da interpretare. I dischi dagli anni '80 in poi ce
  l'hanno quasi tutti; quelli prima no, e lì serve l'OCR del numero di catalogo.

**b. Da lì a Discogs.** È la parte già pronta: `DiscogsClient` esiste. Le API accettano
`barcode=` e `catno=`, che sono ricerche **esatte** — molto più precise del testo libero che
usiamo oggi. Serve una chiamata in più, `GET /releases/{id}`, per avere la **tracklist**, che oggi
non leggiamo: `DiscogsRelease` tiene solo ciò che serve a scegliere una copertina.

**c. Scaricare i brani da YouTube.** yt-dlp sa cercare (`ytsearch1:"artista titolo"`), quindi
meccanicamente si fa. **Il punto debole è l'abbinamento**, non il download: per un pezzo di
un'edizione precisa YouTube restituisce spesso una versione live, un edit o un remix con lo stesso
titolo. Va fatto con una schermata di conferma — la tracklist da Discogs a sinistra, il candidato
trovato con durata e canale a destra, e la durata di Discogs come primo controllo automatico
(scarta ciò che diverge di più di qualche secondo). Scaricare venti tracce senza guardarle
significa riempire la libreria di roba da ributtare via, e ogni download costa minuti.

**Da decidere con Gabriel prima di partire:** se gli interessa davvero l'album intero o solo il
riconoscimento del disco che ha in mano per ritrovarlo/etichettarlo. Il punto (a) + (b) da solo —
inquadra il disco, l'app ti dice cos'è e ti riempie i metadati — è molto meno lavoro e forse è già
il 90% del valore.

---

## Ripartenza a freddo

**Stato:** da M0 a M7 chiuse: **l'app è finita rispetto al piano originale**, e M8 raccoglie tre
richieste nuove di Gabriel (salto di battute, tag, riconoscimento del disco dalla videocamera) —
nessuna iniziata, tutte descritte sopra. **Il motore audio c'è e suona, e le scalette si costruiscono.** L'import da
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

Da M8.1: **salto di battute**, 8/16/32/64, con i comandi `◀ 16 ▶` nella riga degli hot cue e i
tasti `,` e `.`. La taglia è per deck e si ricorda; senza griglia i comandi sono spenti; il salto
passa dal quantize, così non scivola fuori battuta ripetendolo.

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
  della finestra e sopra sopra la maniglia, che finiva coperta. Il fondo di 300 era sotto il
  minimo reale, che è **346** impilati e **203** affiancati — misurati, non stimati: si mette in
  preferenze un'altezza troppo bassa e si legge a quale valore l'app la corregge al primo
  disegno. La maniglia è anche più alta, più larga, e si accende passandoci sopra
- [x] `done` — **Poi la fascia non si ridimensionava più**, segnalato da Gabriel: `minHeight` la
  rendeva elastica come il contenuto sopra, e si prendeva tutto lo spazio. Torna l'altezza esatta,
  con due difese: il trascinamento si ferma al minimo misurato, e se quel numero un giorno
  diventasse sbagliato `noteDeckBarContentHeight` se ne accorge — il contenuto riporta quanto ha
  occupato davvero, e se ha dovuto debordare la fascia si alza. **La rete non basta da sola**:
  scatta quando la misura cambia, e trascinando ancora più in giù la misura resta ferma
- [x] `done` — **Il trascinamento andava a metà velocità.** `DragGesture` misurava nello spazio
  della maniglia, che è proprio il bordo che si sposta: lo spostamento risultava la differenza fra
  quanto si muoveva il puntatore e quanto si muoveva lei. Con `coordinateSpace: .global` la fascia
  segue il mouse 1:1 — verificato: da 500 a 380 con 120 punti, a 580 con 200 in su
- [x] `done` — **Due pulsantini `−` e `+` per il pitch**, ai lati della percentuale: un colpo vale
  **0,05%** (0,064 BPM a 128), con ⇧ **0,5%**, e tenuti premuti si ripetono. Servono perché il
  fader non arriva a quella precisione: con 200 punti di corsa per ±8%, un solo punto vale già
  0,08%. Percentuale e BPM effettivo passati a **due decimali**, o un passo di rifinitura non si
  vedrebbe muovere il numero
- [x] `done` — **Icona dell'app**: un disco visto dall'alto, etichetta arancione come l'accento,
  testina appoggiata. Generata da `Scripts/make-app-icon.swift` in tutte e dieci le misure, con i
  PNG versionati in `App/Assets.xcassets/AppIcon.appiconset`

## Prossimo passo

**Da fare, in ordine**: M8.1 (salto di battute) è **chiusa** — comandi nella riga degli hot cue,
tasti `,` e `.`, taglia per deck che si ricorda. Tocca a M8.2 (tag): è chiaro ma tocca lo schema del
database, quindi va fatto con calma e con la migrazione `v2` scritta bene. M8.3 va **prima discusso
con Gabriel**: la domanda scritta in fondo alla sua descrizione è se gli serve l'album intero o solo
il riconoscimento.

**Da far provare a Gabriel**, che è la parte non automatizzabile:

1. **Il primo scatto dell'etichetta**: macOS chiede il consenso alla fotocamera al primo tentativo,
   e con Continuity l'iPhone va sbloccato e vicino perché compaia nell'elenco. Mai provato.
2. **I BPM sulle sue tracce**: se qualcuno è un'ottava sopra o sotto, ÷2 e ×2 lo raddrizzano. La
   griglia è verificata numericamente contro gli attacchi di cassa, ma un pezzo che accelera e
   rallenta si sente, non si misura.
3. **Le scorciatoie a tasto nudo** si prendono i tasti che le tabelle userebbero per la selezione
   per digitazione: se dà fastidio, il posto dove toglierle è `DeckKeyMonitor.actionByCharacter`.

**Stato di Discogs**: il token è configurato e funziona — al 2026-09-05 cinque tracce su sei in
libreria hanno la copertina presa da lì. L'unica senza è «Only Love Can Break Your Heart».
