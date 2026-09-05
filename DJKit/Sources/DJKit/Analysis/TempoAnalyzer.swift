import Accelerate
import Foundation

/// Rileva BPM e posizione del primo downbeat di una traccia.
///
/// Tre passaggi, ognuno con un motivo preciso:
///
/// 1. **Curva di onset (spectral flux multi-banda).** Una STFT a finestra 1024 e passo 256 —
///    la stessa granularità dei peaks — e per ogni frame la somma degli aumenti di ampiezza
///    rispetto al frame precedente, misurati **banda per banda** e mediati dentro ognuna. La
///    divisione in bande conta: sommando i bin grezzi, le ottave alte — che hanno molti più bin —
///    coprirebbero l'attacco della cassa, che è il colpo su cui la griglia deve appoggiarsi. Le
///    ampiezze si comprimono in logaritmo prima di sottrarle, così un ritornello forte e un
///    break piano pesano allo stesso modo.
///
/// 2. **Periodo, per autocorrelazione della curva.** L'autocorrelazione si calcola con una FFT
///    sull'intera curva (il metodo diretto su 60.000 campioni sarebbe un miliardo di prodotti), e
///    fra i periodi candidati si sceglie con una **somma armonica**: il punteggio di un periodo è
///    la somma dell'autocorrelazione ai suoi multipli, che premia il periodo giusto rispetto ai
///    suoi multipli interi. Poi una parabola sui tre campioni attorno al picco dà la precisione
///    sotto il frame.
///
/// 3. **Fase, per treno di impulsi.** Si prova ogni fase dentro un periodo, si sommano i valori
///    della curva sulle battute che ne risultano, e si tiene la migliore. Sulle quattro battute di
///    una misura si ripete lo stesso conto per decidere quale sia l'uno.
///
/// **Il limite noto è l'ottava**: distinguere 87 BPM con i charleston in levare da 174 BPM con la
/// cassa su ogni quarto è ambiguo anche per un orecchio umano, e nessuna misura lo risolve da
/// sola. Qui la scelta è guidata da una preferenza morbida attorno ai 126 BPM, che è dove sta la
/// musica che finisce su un piatto; quando sbaglia, i pulsanti ×2 e ÷2 dell'editor la
/// raddrizzano in un clic — che è molto meno lavoro di quanto costerebbe un rilevatore che non
/// sbaglia mai.
public enum TempoAnalyzer {
    /// Estremi della ricerca. Sotto i 70 e sopra i 200 non c'è musica da ballare, e allargare la
    /// finestra aggiunge solo occasioni di prendere un'ottava per l'altra.
    public static let minimumBPM = 70.0
    public static let maximumBPM = 200.0

    public static let fftSize = 1024
    public static let hopSize = 256

    /// Centro e larghezza (in ottave) della preferenza sui tempi. 126 BPM è il centro di gravità
    /// di house, disco e techno; mezza ottava di deviazione lascia comunque arrivare 174.
    static let preferredBPM = 126.0
    static let preferenceOctaves = 0.55

    /// Fino a che multiplo del periodo si somma l'autocorrelazione.
    static let harmonicCount = 6

    /// Quanto devono pesare i colpi **in mezzo** alle battute perché la battuta vera sia il
    /// doppio. Vedi `resolveOctave`.
    static let octaveSplitRatio = 0.5

    /// Confini delle bande di flusso, in hertz. Spaziate per ottave: è la scala su cui l'orecchio
    /// separa la cassa dal rullante dal charleston, cioè i tre colpi che disegnano il ritmo.
    static let bandEdgesHz: [Double] = [20, 60, 120, 240, 480, 960, 1920, 3840, 7680, 15360]

    /// Le bande sotto questa soglia contribuiscono anche alla curva usata per trovare l'uno della
    /// misura: è la regione della cassa e del basso, dove i cambi di armonia segnano la misura.
    static let lowBandLimitHz = 240.0

    /// Compressione logaritmica delle ampiezze: `log(1 + γ·|X|)`. Con γ = 100 un passaggio piano
    /// e uno forte producono flussi confrontabili, che è ciò che serve perché la griglia non si
    /// aggrappi solo al ritornello.
    static let compressionGamma: Float = 100

    /// Mezza finestra della media mobile sottratta alla curva, in secondi. Ottanta centesimi
    /// coprono un paio di battute a qualsiasi tempo utile: abbastanza per togliere l'andamento
    /// lento del brano, troppo poco per intaccare i colpi.
    static let adaptiveWindowSeconds = 0.4

    // MARK: - Ingresso

    public static func analyze(
        _ audio: DecodedAudio,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> TempoEstimate? {
        analyze(mono: audio.makeMono(), sampleRate: audio.sampleRate, onProgress: onProgress)
    }

    /// Variante su segnale mono già pronto: la usano i test, che costruiscono click track
    /// sintetici a BPM noto senza passare da un file.
    public static func analyze(
        mono: [Float],
        sampleRate: Double,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> TempoEstimate? {
        guard sampleRate > 0 else { return nil }
        guard var curve = onsetCurve(mono, sampleRate: sampleRate, onProgress: onProgress)
        else { return nil }

        let curveRate = sampleRate / Double(hopSize)
        let windowFrames = max(1, Int((adaptiveWindowSeconds * curveRate).rounded()))
        subtractMovingAverage(&curve.flux, halfWindow: windowFrames)
        subtractMovingAverage(&curve.low, halfWindow: windowFrames)

        guard let correlation = autocorrelation(curve.flux) else { return nil }
        guard let period = pickPeriod(correlation, curveRate: curveRate) else { return nil }

        let frames = resolveOctave(curve.flux, periodFrames: period.frames, curveRate: curveRate)
        let phase = pickPhase(curve, periodFrames: frames)
        let bpm = 60 * curveRate / frames

        return TempoEstimate(
            bpm: bpm,
            beatgridOffsetSeconds: phase / curveRate,
            confidence: period.confidence
        )
    }

    // MARK: - Curva di onset

    struct OnsetCurve {
        /// Flusso su tutte le bande: è la curva su cui si misura il periodo.
        var flux: [Float]
        /// Solo le bande basse: serve a scegliere quale delle quattro battute è l'uno.
        var low: [Float]
    }

    /// Spectral flux per bande, un valore ogni `hopSize` campioni.
    ///
    /// La finestra è **centrata** sul frame, come in `PeaksBuilder`: il valore di indice `i`
    /// appartiene all'istante `i · hop / sampleRate`, senza mezze finestre di sfasamento da
    /// ricordare a valle.
    static func onsetCurve(
        _ mono: [Float],
        sampleRate: Double,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> OnsetCurve? {
        let size = fftSize
        let half = size / 2
        let hop = hopSize
        let sampleCount = mono.count
        guard sampleCount > size * 2, sampleRate > 0 else { return nil }

        let frameCount = sampleCount / hop
        // Sotto le otto battute più lente non c'è abbastanza segnale per un'autocorrelazione che
        // voglia dire qualcosa: meglio nessun BPM di uno inventato su due secondi di audio.
        guard frameCount >= Int(8 * 60 / minimumBPM * sampleRate / Double(hop)) else { return nil }

        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        let binHz = sampleRate / Double(size)
        var bands = [Range<Int>]()
        var lowBandCount = 0
        for index in 0..<(bandEdgesHz.count - 1) {
            // Si parte dal bin 1: nel formato impacchettato di vDSP l'indice 0 tiene insieme
            // continua e Nyquist, e un eventuale offset continuo non è un colpo di cassa.
            let lower = max(1, Int((bandEdgesHz[index] / binHz).rounded()))
            let upper = min(half, Int((bandEdgesHz[index + 1] / binHz).rounded()))
            guard lower < upper else { continue }
            bands.append(lower..<upper)
            if bandEdgesHz[index + 1] <= lowBandLimitHz { lowBandCount += 1 }
        }
        guard !bands.isEmpty else { return nil }

        let window = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let windowed = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let realp = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let imagp = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let magnitudes = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let previous = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let difference = UnsafeMutablePointer<Float>.allocate(capacity: half)
        defer {
            window.deallocate()
            windowed.deallocate()
            realp.deallocate()
            imagp.deallocate()
            magnitudes.deallocate()
            previous.deallocate()
            difference.deallocate()
        }
        previous.update(repeating: 0, count: half)
        vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        var flux = [Float](repeating: 0, count: frameCount)
        var low = [Float](repeating: 0, count: frameCount)
        var gamma = compressionGamma
        var one: Float = 1
        var zero: Float = 0
        let progressStep = max(1, frameCount / 50)

        mono.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }

            for frame in 0..<frameCount {
                let start = frame * hop - size / 2

                if start >= 0, start + size <= sampleCount {
                    vDSP_vmul(base + start, 1, window, 1, windowed, 1, vDSP_Length(size))
                } else {
                    // Fuori dal brano c'è silenzio: il primo e l'ultimo frame non vanno letti
                    // oltre il buffer.
                    for offset in 0..<size {
                        let position = start + offset
                        windowed[offset] = (position >= 0 && position < sampleCount)
                            ? base[position] * window[offset]
                            : 0
                    }
                }

                windowed.withMemoryRebound(to: DSPComplex.self, capacity: half) { packed in
                    vDSP_ctoz(packed, 2, &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvabs(&split, 1, magnitudes, 1, vDSP_Length(half))

                // log(1 + γ·|X|): compressione, non normalizzazione. Le due sono diverse — una
                // normalizzazione per frame cancellerebbe proprio il salto di energia che stiamo
                // cercando.
                vDSP_vsmul(magnitudes, 1, &gamma, magnitudes, 1, vDSP_Length(half))
                vDSP_vsadd(magnitudes, 1, &one, magnitudes, 1, vDSP_Length(half))
                vvlogf(magnitudes, magnitudes, [Int32(half)])

                // Solo gli aumenti: una nota che si spegne non è un colpo.
                vDSP_vsub(previous, 1, magnitudes, 1, difference, 1, vDSP_Length(half))
                vDSP_vthres(difference, 1, &zero, difference, 1, vDSP_Length(half))

                var total: Float = 0
                var lowTotal: Float = 0
                for (index, band) in bands.enumerated() {
                    var sum: Float = 0
                    vDSP_sve(difference + band.lowerBound, 1, &sum, vDSP_Length(band.count))
                    // Diviso per la larghezza della banda: senza, le bande alte — che hanno
                    // decine di volte più bin — deciderebbero da sole dove cade la battuta.
                    let mean = sum / Float(band.count)
                    total += mean
                    if index < lowBandCount { lowTotal += mean }
                }
                flux[frame] = total
                low[frame] = lowTotal

                previous.update(from: magnitudes, count: half)

                if frame % progressStep == 0 {
                    onProgress?(Double(frame) / Double(frameCount))
                }
            }
        }
        onProgress?(1)
        return OnsetCurve(flux: flux, low: low)
    }

    /// Toglie alla curva la sua media mobile e tiene solo ciò che resta positivo.
    ///
    /// È il passaggio che rende l'autocorrelazione leggibile: senza, il profilo lento del brano —
    /// intro piano, ritornello forte — domina il segnale e il picco del periodo ci si perde
    /// dentro. Le somme cumulate rendono il costo indipendente dalla larghezza della finestra.
    static func subtractMovingAverage(_ curve: inout [Float], halfWindow: Int) {
        let count = curve.count
        guard count > 0, halfWindow > 0 else { return }

        var prefix = [Float](repeating: 0, count: count + 1)
        for index in 0..<count { prefix[index + 1] = prefix[index] + curve[index] }

        for index in 0..<count {
            let start = max(0, index - halfWindow)
            let end = min(count, index + halfWindow + 1)
            let mean = (prefix[end] - prefix[start]) / Float(end - start)
            curve[index] = max(0, curve[index] - mean)
        }
    }

    // MARK: - Periodo

    /// Autocorrelazione normalizzata, indicizzata per ritardo in frame.
    ///
    /// Stima **polarizzata** di proposito: non si divide per il numero di campioni sovrapposti,
    /// quindi i ritardi lunghi valgono meno di quelli corti. Non è un difetto da correggere, è
    /// ciò che fa preferire il periodo alla sua metà quando entrambi cadono su un picco.
    static func autocorrelation(_ curve: [Float]) -> [Float]? {
        let count = curve.count
        guard count > 4 else { return nil }

        var log2n: vDSP_Length = 0
        var length = 1
        while length < count * 2 {
            length <<= 1
            log2n += 1
        }
        let half = length / 2

        var mean: Float = 0
        vDSP_meanv(curve, 1, &mean, vDSP_Length(count))

        // La media si toglie solo dentro il segnale: il riempimento resta a zero, che è ciò che
        // rende lineare — e non circolare — l'autocorrelazione che ne esce.
        var padded = [Float](repeating: 0, count: length)
        var negated = -mean
        curve.withUnsafeBufferPointer { source in
            vDSP_vsadd(source.baseAddress!, 1, &negated, &padded, 1, vDSP_Length(count))
        }

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var realp = [Float](repeating: 0, count: half)
        var imagp = [Float](repeating: 0, count: half)
        var result = [Float](repeating: 0, count: length)

        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(
                    realp: realBuffer.baseAddress!,
                    imagp: imagBuffer.baseAddress!
                )
                padded.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Spettro di potenza. L'indice 0 è speciale: tiene la continua nella parte reale
                // e Nyquist nell'immaginaria, e le due vanno elevate al quadrato separatamente.
                let dc = realBuffer[0]
                let nyquist = imagBuffer[0]
                for index in 1..<half {
                    let re = realBuffer[index]
                    let im = imagBuffer[index]
                    realBuffer[index] = re * re + im * im
                    imagBuffer[index] = 0
                }
                realBuffer[0] = dc * dc
                imagBuffer[0] = nyquist * nyquist

                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                result.withUnsafeMutableBufferPointer { output in
                    output.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(half))
                    }
                }
            }
        }

        // Normalizzando sul ritardo zero le costanti di scala della FFT spariscono da sole, e
        // non c'è nessun fattore da ricordare.
        let peak = result[0]
        guard peak > 0, peak.isFinite else { return nil }
        var scale = 1 / peak
        result.withUnsafeMutableBufferPointer { buffer in
            vDSP_vsmul(buffer.baseAddress!, 1, &scale, buffer.baseAddress!, 1, vDSP_Length(count))
        }
        return Array(result[0..<count])
    }

    struct Period {
        var frames: Double
        var confidence: Double
    }

    /// Sceglie il periodo fra i candidati ammessi dal range di BPM.
    static func pickPeriod(_ correlation: [Float], curveRate: Double) -> Period? {
        let shortest = 60 * curveRate / maximumBPM
        let longest = 60 * curveRate / minimumBPM
        let first = max(2, Int(shortest.rounded(.down)))
        let last = min(correlation.count - 1, Int(longest.rounded(.up)))
        guard first < last else { return nil }

        var bestLag = first
        var bestScore = -Float.greatestFiniteMagnitude

        for lag in first...last {
            let score = Float(harmonicScore(correlation, lag: Double(lag), curveRate: curveRate))
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestScore > 0 else { return nil }

        // Parabola sui tre campioni attorno al massimo: il periodo vero cade quasi sempre fra
        // due frame, e mezzo frame di errore a 128 BPM sono già 0,8 BPM.
        let refined = Double(bestLag) + parabolicOffset(
            correlation[max(0, bestLag - 1)],
            correlation[bestLag],
            correlation[min(correlation.count - 1, bestLag + 1)]
        )
        let lag = refineOnLongLag(correlation, coarse: refined) ?? refined
        guard lag > 0 else { return nil }

        return Period(
            frames: lag,
            confidence: Double(min(1, max(0, correlation[bestLag])))
        )
    }

    /// Punteggio di un periodo: l'autocorrelazione ai suoi multipli, pesata `1/h`, per la
    /// preferenza sui tempi da ballare.
    static func harmonicScore(_ correlation: [Float], lag: Double, curveRate: Double) -> Double {
        var score = 0.0
        for harmonic in 1...harmonicCount {
            let position = lag * Double(harmonic)
            guard position < Double(correlation.count - 1) else { break }
            score += sample(correlation, at: position) / Double(harmonic)
        }
        let bpm = 60 * curveRate / lag
        return score * preference(forBPM: bpm)
    }

    /// Preferenza morbida attorno a `preferredBPM`, gaussiana sul logaritmo del tempo.
    ///
    /// Sul logaritmo e non sul BPM perché la simmetria che conta è quella fra un tempo e il suo
    /// doppio: 63 e 252 devono essere sfavoriti allo stesso modo rispetto a 126.
    static func preference(forBPM bpm: Double) -> Double {
        guard bpm > 0 else { return 0 }
        let octaves = log2(bpm / preferredBPM) / preferenceOctaves
        return exp(-0.5 * octaves * octaves)
    }

    /// Ripete la misura su un ritardo lungo, dove lo stesso errore in frame pesa molte volte meno.
    ///
    /// Il picco a venti battute di distanza sta a venti periodi dall'origine: individuarlo con la
    /// stessa precisione di mezzo frame e dividere per venti porta l'errore sul BPM da qualche
    /// decimo a qualche millesimo. È ciò che tiene la griglia allineata anche in fondo a un brano
    /// di sei minuti, dove 0,1 BPM di errore sono già un quarto di secondo di scarto.
    static func refineOnLongLag(_ correlation: [Float], coarse: Double) -> Double? {
        guard coarse > 1 else { return nil }
        let limit = Double(correlation.count - 2)
        let multiple = min(32, Int((limit / coarse).rounded(.down)))
        guard multiple >= 2 else { return nil }

        let target = coarse * Double(multiple)
        let window = max(1, Int((coarse / 3).rounded()))
        let first = max(1, Int(target.rounded()) - window)
        let last = min(correlation.count - 2, Int(target.rounded()) + window)
        guard first < last else { return nil }

        var bestIndex = first
        for index in first...last where correlation[index] > correlation[bestIndex] {
            bestIndex = index
        }
        let refined = Double(bestIndex) + parabolicOffset(
            correlation[bestIndex - 1],
            correlation[bestIndex],
            correlation[bestIndex + 1]
        )
        let period = refined / Double(multiple)

        // Se il picco lungo non è dove il periodo grossolano lo prevedeva, la traccia non ha un
        // tempo abbastanza fisso perché questa raffinatura significhi qualcosa: si tiene la
        // misura corta, che è meno precisa ma non è sbagliata.
        guard abs(period - coarse) < coarse * 0.02 else { return nil }
        return period
    }

    // MARK: - Ottava

    /// Guarda in mezzo alle battute trovate e, se anche lì ci sono colpi, dimezza il periodo.
    ///
    /// L'autocorrelazione da sola sbaglia sistematicamente in questa direzione, e non per un
    /// difetto dell'implementazione: un pezzo a 174 con la cassa sull'uno e colpi più leggeri
    /// sugli altri quarti si autocorrela **meglio** a due quarti di distanza, dove il colpo forte
    /// ricade sul colpo forte, che a un quarto. La somma armonica accentua la cosa, perché il
    /// candidato lento raccoglie proprio quei multipli.
    ///
    /// La domanda che scioglie il dubbio non è quanto si somiglia il segnale a se stesso, ma se
    /// **fra una battuta e l'altra c'è un colpo**: se c'è, quella è una battuta anche lei. È la
    /// stessa cosa che si fa contando a orecchio.
    ///
    /// Resta ambiguo il caso opposto — 87 BPM con i charleston in levare suona come 174 con la
    /// cassa su ogni quarto — che è ambiguo anche per un orecchio umano. Lì la soglia decide in
    /// base a **quanto** sono più deboli i colpi intermedi, e se sbaglia ci sono i pulsanti ×2 e
    /// ÷2 nell'editor della griglia.
    static func resolveOctave(
        _ flux: [Float],
        periodFrames: Double,
        curveRate: Double
    ) -> Double {
        var period = periodFrames
        // Al massimo due dimezzamenti: dal quarto al sedicesimo. Oltre non c'è musica, c'è
        // rumore che si autocorrela.
        for _ in 0..<2 {
            let halved = period / 2
            guard 60 * curveRate / halved <= maximumBPM else { break }

            let phase = bestPhase(flux, periodFrames: period)
            let onBeat = combScore(flux, phase: phase, period: period)
            let between = combScore(flux, phase: phase + halved, period: period)
            guard onBeat > 0, between / onBeat >= octaveSplitRatio else { break }
            period = halved
        }
        return period
    }

    // MARK: - Fase

    /// Trova la fase della griglia e, dentro la misura, quale battuta è l'uno.
    ///
    /// La fase si cerca su tutta la curva di flusso: si somma il valore sulle battute che ogni
    /// candidato produrrebbe, e vince quella che raccoglie più colpi. L'uno della misura si
    /// sceglie poi fra le quattro battute con la stessa somma fatta sulle sole bande basse — la
    /// regione dove il cambio di armonia e il colpo di cassa segnano l'inizio della misura. È
    /// un'euristica, e su un pezzo con la cassa identica su tutti e quattro i quarti può scegliere
    /// la battuta sbagliata: sposta la linea di misura, non le battute, e si corregge trascinando
    /// la griglia.
    static func pickPhase(_ curve: OnsetCurve, periodFrames: Double) -> Double {
        let refined = bestPhase(curve.flux, periodFrames: periodFrames)

        // Quale delle quattro battute è l'uno.
        var bestBar = 0
        var bestBarScore = -Double.greatestFiniteMagnitude
        for beat in 0..<Beatgrid.beatsPerBar {
            let phase = refined + Double(beat) * periodFrames
            let score = combScore(
                curve.low,
                phase: phase,
                period: periodFrames * Double(Beatgrid.beatsPerBar)
            )
            if score > bestBarScore {
                bestBarScore = score
                bestBar = beat
            }
        }

        let downbeat = refined + Double(bestBar) * periodFrames
        let bar = periodFrames * Double(Beatgrid.beatsPerBar)
        return downbeat - bar * (downbeat / bar).rounded(.down)
    }

    /// La fase che raccoglie più colpi, provate tutte quelle dentro un periodo.
    ///
    /// Il massimo si affina con una parabola sui punteggi vicini: la battuta cade quasi sempre
    /// fra due frame, e un frame sono 5,8 ms — visibili sulla griglia alla massima zoomata.
    static func bestPhase(_ flux: [Float], periodFrames: Double) -> Double {
        let period = Int(periodFrames.rounded())
        guard period >= 2, flux.count > period else { return 0 }

        var scores = [Double](repeating: 0, count: period)
        for phase in 0..<period {
            scores[phase] = combScore(flux, phase: Double(phase), period: periodFrames)
        }

        var best = 0
        for phase in 0..<period where scores[phase] > scores[best] { best = phase }

        // I punteggi sono circolari: la fase 0 confina con l'ultima, non con il nulla.
        return Double(best) + parabolicOffset(
            Float(scores[(best - 1 + period) % period]),
            Float(scores[best]),
            Float(scores[(best + 1) % period])
        )
    }

    /// Media della curva sui battiti generati da una fase e un periodo.
    private static func combScore(_ curve: [Float], phase: Double, period: Double) -> Double {
        guard period >= 1 else { return 0 }
        var total = 0.0
        var count = 0
        var position = phase - period * (phase / period).rounded(.down)
        let limit = Double(curve.count - 2)
        while position <= limit {
            if position >= 0 {
                total += sample(curve, at: position)
                count += 1
            }
            position += period
        }
        return count > 0 ? total / Double(count) : 0
    }

    // MARK: - Interpolazioni

    /// Vertice della parabola per tre campioni consecutivi, come scostamento da quello centrale.
    /// Limitato a mezzo campione: fuori di lì il massimo non è quello centrale e la formula non
    /// vuol dire più niente.
    static func parabolicOffset(_ before: Float, _ center: Float, _ after: Float) -> Double {
        let denominator = Double(before - 2 * center + after)
        guard abs(denominator) > 1e-12 else { return 0 }
        let offset = 0.5 * Double(before - after) / denominator
        return min(0.5, max(-0.5, offset))
    }

    private static func sample(_ curve: [Float], at position: Double) -> Double {
        guard position >= 0 else { return 0 }
        let index = Int(position)
        guard index >= 0, index + 1 < curve.count else { return 0 }
        let fraction = position - Double(index)
        return Double(curve[index]) * (1 - fraction) + Double(curve[index + 1]) * fraction
    }
}
