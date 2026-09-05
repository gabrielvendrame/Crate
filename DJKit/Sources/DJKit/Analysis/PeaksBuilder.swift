import Accelerate
import Foundation

/// Costruisce la cache della waveform: quattro livelli di zoom, ognuno con sagoma e colore.
///
/// Come è fatto, e perché:
///
/// - la **sagoma** (min/max) si misura sui sample veri al livello più fine e sale per
///   aggregazione, così `max` di un bin grosso è esattamente il `max` dei bin piccoli che
///   contiene: nessuna approssimazione fra un livello di zoom e l'altro;
/// - il **colore** (le tre bande) si misura una volta sola con una STFT a passo 256 e finestra
///   1024, e sale anch'esso per aggregazione. La finestra da 1024 dà 43 Hz di risoluzione —
///   abbastanza per piazzare il taglio a 200 Hz — e 23 ms di durata, abbastanza corta da non
///   spalmare l'attacco della cassa, che è proprio ciò che si vuole riconoscere a colpo d'occhio.
///   Una FFT sul bin da 64 sample darebbe 689 Hz di risoluzione: inutilizzabile sui bassi.
///   Il livello da 64 eredita il colore dal bin da 256 che lo contiene: 5,8 ms di quantizzazione
///   del colore, sotto il pixel anche alla massima zoomata.
public enum PeaksBuilder {
    /// Dal più fine al più grosso. Ogni livello è quattro volte il precedente: l'aggregazione è
    /// esatta e la tabella dei livelli resta corta.
    public static let binSizes = [64, 256, 1024, 4096]
    /// Passo a cui si misurano le bande, cioè il secondo livello.
    public static let bandBinSize = 256
    public static let fftSize = 1024

    public static let lowCrossoverHz = 200.0
    public static let highCrossoverHz = 4000.0

    public static func build(
        _ audio: DecodedAudio,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) -> Peaks {
        let mono = audio.makeMono()
        let frameCount = mono.count

        guard frameCount > 0 else {
            return Peaks(
                sampleRate: audio.sampleRate,
                frameCount: 0,
                channelCount: audio.channelCount,
                levels: binSizes.map { PeaksLevel(binSize: $0, bins: []) }
            )
        }

        let finestSize = binSizes[0]
        let ratio = bandBinSize / finestSize

        let shape = extremes(mono, binSize: finestSize)
        onProgress?(0.1)

        let bandCount = binCount(frameCount: frameCount, binSize: bandBinSize)
        let bands = bandLevels(
            mono,
            sampleRate: audio.sampleRate,
            hop: bandBinSize,
            count: bandCount,
            onProgress: { onProgress?(0.1 + 0.8 * $0) }
        )

        // Livello 64: sagoma esatta, colore preso dal bin da 256 che lo contiene.
        var finest = [PeakBin]()
        finest.reserveCapacity(shape.minimums.count)
        for index in shape.minimums.indices {
            let band = min(index / ratio, bandCount - 1)
            finest.append(
                PeakBin(
                    minimum: shape.minimums[index],
                    maximum: shape.maximums[index],
                    low: bands.low[band],
                    mid: bands.mid[band],
                    high: bands.high[band]
                )
            )
        }

        // Livello 256: sagoma aggregata dai quattro bin sotto, colore misurato direttamente.
        var second = [PeakBin]()
        second.reserveCapacity(bandCount)
        for index in 0..<bandCount {
            let start = index * ratio
            let end = min(start + ratio, finest.count)
            var minimum: Float = 0
            var maximum: Float = 0
            if start < end {
                minimum = finest[start].minimum
                maximum = finest[start].maximum
                for inner in (start + 1)..<end {
                    minimum = min(minimum, finest[inner].minimum)
                    maximum = max(maximum, finest[inner].maximum)
                }
            }
            second.append(
                PeakBin(
                    minimum: minimum,
                    maximum: maximum,
                    low: bands.low[index],
                    mid: bands.mid[index],
                    high: bands.high[index]
                )
            )
        }

        let third = aggregate(second, factor: 4)
        let fourth = aggregate(third, factor: 4)
        onProgress?(1)

        return Peaks(
            sampleRate: audio.sampleRate,
            frameCount: frameCount,
            channelCount: audio.channelCount,
            levels: [
                PeaksLevel(binSize: binSizes[0], bins: finest),
                PeaksLevel(binSize: binSizes[1], bins: second),
                PeaksLevel(binSize: binSizes[2], bins: third),
                PeaksLevel(binSize: binSizes[3], bins: fourth),
            ]
        )
    }

    public static func binCount(frameCount: Int, binSize: Int) -> Int {
        guard frameCount > 0, binSize > 0 else { return 0 }
        return (frameCount + binSize - 1) / binSize
    }

    // MARK: - Sagoma

    private static func extremes(
        _ samples: [Float],
        binSize: Int
    ) -> (minimums: [Float], maximums: [Float]) {
        let count = binCount(frameCount: samples.count, binSize: binSize)
        var minimums = [Float](repeating: 0, count: count)
        var maximums = [Float](repeating: 0, count: count)

        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            for index in 0..<count {
                let start = index * binSize
                let length = min(binSize, samples.count - start)
                vDSP_minv(base + start, 1, &minimums[index], vDSP_Length(length))
                vDSP_maxv(base + start, 1, &maximums[index], vDSP_Length(length))
            }
        }
        return (minimums, maximums)
    }

    /// Unisce `factor` bin in uno: gli estremi si propagano, i livelli di banda si combinano in
    /// RMS (radice della media dei quadrati), che è il modo corretto di sommare energie.
    private static func aggregate(_ bins: [PeakBin], factor: Int) -> [PeakBin] {
        guard factor > 1, !bins.isEmpty else { return bins }
        let count = (bins.count + factor - 1) / factor
        var result = [PeakBin]()
        result.reserveCapacity(count)

        for index in 0..<count {
            let start = index * factor
            let end = min(start + factor, bins.count)
            var minimum = bins[start].minimum
            var maximum = bins[start].maximum
            var low: Float = 0
            var mid: Float = 0
            var high: Float = 0

            for inner in start..<end {
                let source = bins[inner]
                minimum = min(minimum, source.minimum)
                maximum = max(maximum, source.maximum)
                low += source.low * source.low
                mid += source.mid * source.mid
                high += source.high * source.high
            }

            let divisor = Float(end - start)
            result.append(
                PeakBin(
                    minimum: minimum,
                    maximum: maximum,
                    low: (low / divisor).squareRoot(),
                    mid: (mid / divisor).squareRoot(),
                    high: (high / divisor).squareRoot()
                )
            )
        }
        return result
    }

    // MARK: - Bande di frequenza

    /// STFT a passo `hop` con finestra `fftSize` centrata sul bin, e livello RMS nelle tre bande.
    ///
    /// La normalizzazione riporta la somma delle potenze di banda al valore RMS del segnale **non
    /// finestrato**: `Σw²/N = 0,375` per la finestra di Hann, e vDSP restituisce l'uscita reale
    /// scalata di 2. Messe insieme danno il divisore `N·√0,75`, per cui una sinusoide a fondo
    /// scala tutta dentro una banda vale 0,707 — il suo RMS vero.
    private static func bandLevels(
        _ samples: [Float],
        sampleRate: Double,
        hop: Int,
        count: Int,
        onProgress: (Double) -> Void
    ) -> (low: [Float], mid: [Float], high: [Float]) {
        var low = [Float](repeating: 0, count: count)
        var mid = [Float](repeating: 0, count: count)
        var high = [Float](repeating: 0, count: count)
        guard count > 0, sampleRate > 0 else { return (low, mid, high) }

        let size = fftSize
        let half = size / 2
        let log2n = vDSP_Length(log2(Double(size)).rounded())
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return (low, mid, high)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        // L'indice 0 dell'uscita impacchettata contiene DC e Nyquist insieme: le bande partono da
        // 1, così l'eventuale offset continuo non finisce nei bassi.
        let binHz = sampleRate / Double(size)
        let lowEnd = min(half, max(1, Int((lowCrossoverHz / binHz).rounded())))
        let highStart = min(half, max(lowEnd, Int((highCrossoverHz / binHz).rounded())))
        let ranges = [1..<max(1, lowEnd), lowEnd..<highStart, highStart..<half]

        let window = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let windowed = UnsafeMutablePointer<Float>.allocate(capacity: size)
        let realp = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let imagp = UnsafeMutablePointer<Float>.allocate(capacity: half)
        let magnitudes = UnsafeMutablePointer<Float>.allocate(capacity: half)
        defer {
            window.deallocate()
            windowed.deallocate()
            realp.deallocate()
            imagp.deallocate()
            magnitudes.deallocate()
        }
        vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_DENORM))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        let normalizer = 1 / (Float(size) * (0.75 as Float).squareRoot())
        let sampleCount = samples.count
        let progressStep = max(1, count / 50)

        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }

            for index in 0..<count {
                // La finestra è centrata sul bin: il colore appartiene al centro dell'intervallo,
                // non al suo inizio.
                let start = index * hop + hop / 2 - size / 2

                if start >= 0, start + size <= sampleCount {
                    vDSP_vmul(base + start, 1, window, 1, windowed, 1, vDSP_Length(size))
                } else {
                    // Ai bordi della traccia il fuori-brano è silenzio.
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
                vDSP_zvmags(&split, 1, magnitudes, 1, vDSP_Length(half))

                low[index] = bandLevel(magnitudes, ranges[0], normalizer)
                mid[index] = bandLevel(magnitudes, ranges[1], normalizer)
                high[index] = bandLevel(magnitudes, ranges[2], normalizer)

                if index % progressStep == 0 {
                    onProgress(Double(index) / Double(count))
                }
            }
        }
        onProgress(1)
        return (low, mid, high)
    }

    private static func bandLevel(
        _ magnitudes: UnsafePointer<Float>,
        _ range: Range<Int>,
        _ normalizer: Float
    ) -> Float {
        guard !range.isEmpty else { return 0 }
        var sum: Float = 0
        vDSP_sve(magnitudes + range.lowerBound, 1, &sum, vDSP_Length(range.count))
        return min(1, sum.squareRoot() * normalizer)
    }
}
