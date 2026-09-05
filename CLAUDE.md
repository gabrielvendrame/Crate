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
  sui piatti. Corsa del fader **±8%**, come un SL-1200: un range più largo darebbe un'idea
  sbagliata di quanto si potrà tirare il pezzo sul piatto vero.
- **Solo YouTube** come sorgente. Niente import di file locali, niente altre piattaforme.
- **Nessun export** (né PDF, né testo, né copia dei file).
- **Un solo device audio in uscita.** Niente preascolto in cuffia su device separato.
- **Solo quattro campi di metadati**: titolo, artista, album — più le foto dell'etichetta. Niente
  genere, anno, rating, commenti, energy.
- **Beatgrid a BPM costante** (offset del downbeat + BPM). Niente beatgrid a marker multipli.
- **Quantize: solo i cue, e uno solo per tutta l'app.** Senza loop non c'è altro da
  quantizzare. Risoluzione **1/1 o 1/2** (scelta di Gabriel del 2026-09-05, dal picker nel mixer;
  sotto la mezza battuta non serve, un sedicesimo a 128 BPM sono 117 ms). L'aggancio vale per
  **memorizzare** un hot cue, per **spostare il cue di lavoro** e anche per **saltare** a un hot
  cue — così un punto piazzato a mano prima che ci fosse la griglia atterra comunque in battuta.
  Non è invece un'azione *ritardata* alla battuta successiva come su alcuni lettori: il salto
  avviene subito, sul punto agganciato. Farlo aspettare vorrebbe dire programmare un evento dentro
  il thread audio, e senza loop non ripaga.
- **Niente memory cue.** Solo gli **8 hot cue**, ognuno con nome e nota. Deciso da Gabriel il
  2026-09-04 usando l'app, e **sostituisce il punto 2 di `PLAN.md`** che prevedeva anche memory
  cue illimitati. La colonna `hotcueSlot` resta annullabile — è così che `assignHotCue` libera uno
  slot senza violare l'indice unico — ma un cue senza slot è un residuo, non una funzione.

## Vincolo di layout: waveform orizzontali a piena larghezza

Le waveform scorrono **in orizzontale**, tempo da sinistra a destra. **Di default i due deck sono
impilati** — A sopra, B sotto — come in rekordbox, così ogni waveform occupa tutta la larghezza
della finestra: è la disposizione da tenere come predefinita, perché affiancare i deck dimezza la
larghezza di ogni waveform e rende meno leggibile proprio la cosa che serve guardare. Vale sia per
l'overview sia per la vista zoomata.

Su richiesta di Gabriel (2026-09-04) i deck si potranno **anche** affiancare su due colonne, come
alternativa scelta dall'utente e non come nuovo default: le waveform restano orizzontali in
entrambi i casi, cambia solo quanta larghezza ha ciascuna. Il compromesso è quello scritto sopra e
va tenuto presente, non ridiscusso: chi trova il codice con due disposizioni non sta guardando una
regressione.

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

In pratica: il callback **non vede mai un oggetto Swift**. Il main pubblica un `DeckTrackRef` —
puntatori ai canali e quattro numeri, in memoria raw — e ne scambia l'indirizzo con un'atomica;
il riferimento forte al `DecodedTrack` resta sul main, che lo libera solo dopo che il contatore di
render è avanzato oltre lo scambio. Risalire all'oggetto da un `Unmanaged` dentro il callback
sembra equivalente e non lo è: legarlo a una variabile locale genera una retain/release, che è una
chiamata di runtime con un lock dentro.

Per lo stesso motivo il render block **non va creato dentro un contesto `@MainActor`**:
`AVAudioSourceNodeRenderBlock` è importato senza `@Sendable`, quindi la closure eredita
l'isolamento e il compilatore le mette in testa un controllo di esecutore che sul thread audio fa
`SIGTRAP` al primo buffer. Va costruito in un metodo `nonisolated` con la closure `@Sendable`
(`DeckEngine.makeRenderBlock`). Non è un errore di compilazione né un avviso: si manifesta solo
premendo play.

**Il rilevamento del tempo sbaglia l'ottava, e si corregge guardando in mezzo alle battute.**
`TempoAnalyzer` misura il periodo per autocorrelazione della curva di onset, con somma armonica:
il metodo preferisce **sistematicamente il periodo lungo**, perché un pezzo con la cassa forte
sull'uno si autocorrela meglio a due quarti di distanza che a uno. Un 174 veniva letto 87. Il
rimedio non è pesare diversamente i multipli — non discriminano — ma chiedersi se **fra una
battuta e l'altra c'è un colpo**: se c'è, quella è una battuta anche lei (`resolveOctave`). Resta
ambiguo il caso opposto, 87 con i charleston in levare contro 174 con la cassa su ogni quarto, che
è ambiguo anche a orecchio: lì decide una preferenza morbida attorno ai 126 BPM, e se sbaglia ci
sono ×2 e ÷2 nell'editor.

La precisione sul BPM viene invece da una **seconda misura su un ritardo lungo**: individuato il
picco a una trentina di periodi di distanza e diviso per trenta, lo stesso mezzo frame di errore
pesa trenta volte meno. Senza, 0,1 BPM di scarto diventano un quarto di secondo in fondo a un
brano di sei minuti. Misurato su cinque brani veri della libreria: le battute della griglia cadono
entro 2–8 ms dagli attacchi di cassa, per tutta la durata.

**La griglia si disegna in una corsia sua, in cima alla vista zoomata.** Disegnarla sopra la
waveform sembrava ovvio e non funziona: quando la griglia è **giusta** i trattini cadono
esattamente sull'attacco della cassa, che è dipinto quasi bianco e alto quanto tutta la vista, e ci
spariscono dentro — la griglia si vedeva solo sopra il silenzio. Con la corsia lo sfondo sotto i
trattini è sempre scuro; sopra la waveform resta solo una linea di misura tenue. `kGridLaneHeight`
in `Waveform.metal` toglie quei pixel all'altezza della forma d'onda, e senza griglia la corsia non
c'è.

**Il modello dell'app si raggiunge da `AppModel.shared`, non dall'`environment`.** Su macOS
diversi pezzi di interfaccia vivono in una `NSHostingView` propria — toolbar, ispettore, fogli,
popover — e quando uno di quei pezzi scrive nel modello, SwiftUI rivaluta il `body` del
proprietario **dentro l'hosting view secondaria**, dove l'ambiente iniettato alla radice della
scena non c'è: `@Environment(AppModel.self)` chiama `fatalError` e il processo muore. Bastava
scrivere un carattere nel campo di ricerca. Reiniettare `.environment` copre un caso alla volta
(è la toppa che era stata messa all'ispettore il 2026-09-04) e ne lascia scoperti altri.
L'osservazione di `@Observable` funziona sulla lettura della proprietà, non su come si è ottenuto
l'oggetto, quindi le viste si aggiornano come prima. Il prezzo — modello non sostituibile per
preview e test di interfaccia — qui non è un prezzo: i test coprono la logica in `DJKit` e di
preview non ce ne sono.

**Persistenza: GRDB 7 (SQLite), non SwiftData.** Migrazioni esplicite e leggibili, e controllo
totale sulla colonna `position` che ordina le playlist — che è il punto dove SwiftData dà più
problemi. `ValueObservation` aggiorna la UI sul main actor.

**Peaks precalcolati, multi-risoluzione e a 3 bande di frequenza.** Livelli con bin da
4096/1024/256/64 sample così overview e vista zoomata si disegnano entrambe dalla stessa cache
senza ricalcoli. Le tre bande (low < 200 Hz, mid 200 Hz–4 kHz, high > 4 kHz) servono a colorare la
waveform come rekordbox: è ciò che fa riconoscere a colpo d'occhio dove entra la cassa.

Nel file `.peaks` le bande sono l'**RMS vero**. La compensazione della pendenza naturale dello
spettro — senza la quale ogni waveform verrebbe blu da capo a fondo — è una scelta di
presentazione e vive nei guadagni `1 / 3 / 12`, che stanno **in due posti**:
`WaveformPalette.bandGain` e `kBandGain` in `Waveform.metal`. Vanno cambiati insieme.

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
    Import/          ToolLocator, YtDlpRunner, MetadataParser, ImportQueue, ToolsUpdater
    Discogs/         DiscogsClient, DiscogsQuery, DiscogsRelease, DiscogsToken
    Library/         LibraryFilter
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

## L'icona

Sta in `App/Assets.xcassets/AppIcon.appiconset` ed è **generata da codice**:

```bash
swift Scripts/make-app-icon.swift     # riscrive tutte e dieci le misure
```

I PNG sono versionati insieme allo script, quindi chi clona compila senza eseguire niente; lo
script serve a **cambiarla**, non a ricostruirla. È il motivo per cui è fatta così: correggere un
colore vuol dire toccare una riga e rilanciare, invece di riaprire un editor grafico e riesportare
undici file a mano tenendoli allineati.

Se dopo un cambio l'icona vecchia resta nel Dock o nel Finder è la cache delle icone di macOS, non
la compilazione: `touch Crate.app && killall Dock`.

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

`./Scripts/check-render-callback.sh` verifica **sul codice generato** che nel render callback audio
non entrino allocazioni, lock o chiamate al runtime. Va rieseguito dopo qualsiasi modifica dentro
`DeckRenderState.render` o alla catena che ne parte, ed è più affidabile di un profilo con
Instruments, che quel difetto lo vede solo se capita mentre si registra.

`CRATE_DISCOGS_TOKEN=... swift test --package-path DJKit --filter DiscogsIntegration` esegue i test
che parlano davvero con Discogs.

`xcodegen` si installa con `brew install xcodegen` (una tantum). Dopo aver aggiunto o rimosso file
o dipendenze in `project.yml`, rigenera il progetto prima di compilare.

Il **toolchain Metal non è incluso in Xcode** e va scaricato una volta, altrimenti
`App/Decks/Waveform.metal` non compila ("cannot execute tool 'metal'"):

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Convenzioni

- Swift 6 con concorrenza rigorosa. I repository sono `actor` o isolati al main actor; il codice
  audio real-time sta fuori dagli actor e comunica con puntatori e valori atomici.
- Un tipo per file, nome del file uguale al nome del tipo.
- I test coprono la logica pura (parsing, serializzazione, DSP): niente test sulla UI.
- Il `TempoAnalyzer` si verifica su click track sintetici a BPM noto (120/128/174), tolleranza
  ±0.5 BPM — non su file musicali reali, che rendono i test non riproducibili.
- Commenti in italiano, identificatori e API in inglese.
