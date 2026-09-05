import Foundation

/// La griglia delle battute di una traccia: **un BPM costante più la posizione del primo
/// downbeat**, esattamente i due numeri che stanno in tabella.
///
/// Niente marker multipli, per scelta di scope: la musica da club che finisce su un piatto è
/// quasi sempre a tempo fisso, e due numeri si possono correggere a mano in un gesto — una
/// griglia a marker no.
///
/// L'`offsetSeconds` è **il primo downbeat**, cioè il primo "uno" della prima battuta di quattro,
/// e sta sempre dentro la prima misura. La griglia però si estende anche all'indietro: gli indici
/// di battuta prima dell'offset sono negativi, e servono perché una traccia che comincia con
/// mezza battuta di anacrusi non abbia un buco davanti.
public struct Beatgrid: Hashable, Sendable {
    /// Quattro quarti: l'unica metrica che questa app disegna. Un pezzo in 3/4 non finisce in un
    /// set da club, e riconoscerlo automaticamente costerebbe molto più di quanto renda.
    public static let beatsPerBar = 4

    public let bpm: Double
    public let offsetSeconds: Double

    /// `nil` per un BPM non utilizzabile: così chi ha una griglia in mano sa che può dividere
    /// senza controllare, e il caso storto si tratta una volta sola qui.
    public init?(bpm: Double, offsetSeconds: Double) {
        guard bpm.isFinite, bpm > 0, offsetSeconds.isFinite else { return nil }
        self.bpm = bpm
        self.offsetSeconds = offsetSeconds
    }

    public var beatDuration: Double { 60 / bpm }
    public var barDuration: Double { beatDuration * Double(Self.beatsPerBar) }

    /// Posizione in battute, frazionaria: 0 è il primo downbeat, 4 il secondo, −1 la battuta
    /// prima dell'inizio della griglia.
    public func beatPosition(atSeconds seconds: Double) -> Double {
        (seconds - offsetSeconds) / beatDuration
    }

    public func seconds(ofBeat position: Double) -> Double {
        offsetSeconds + position * beatDuration
    }

    /// Vero per le battute che cadono sull'uno di una misura. Il resto è preso positivo perché
    /// gli indici prima dell'offset sono negativi, e `-4 % 4` in Swift vale 0 ma `-3 % 4` vale
    /// −3: senza correzione le misure prima dell'inizio della griglia perderebbero l'uno.
    public func isDownbeat(beat: Int) -> Bool {
        let remainder = beat % Self.beatsPerBar
        return (remainder < 0 ? remainder + Self.beatsPerBar : remainder) == 0
    }

    /// Aggancia un istante alla suddivisione più vicina della griglia.
    ///
    /// Il risultato non va mai prima dell'inizio della traccia: un cue piazzato sui primi
    /// millisecondi si aggancia in avanti invece di finire a tempo negativo, dove non si potrebbe
    /// né suonare né vedere.
    public func snap(_ seconds: Double, resolution: QuantizeResolution = .beat) -> Double {
        let step = beatDuration * resolution.beatFraction
        guard step > 0 else { return seconds }
        var snapped = offsetSeconds + ((seconds - offsetSeconds) / step).rounded() * step
        if snapped < 0 {
            snapped += step * (-snapped / step).rounded(.up)
        }
        return snapped
    }

    /// Dove finisce la testina saltando di `beats` battute — negativo all'indietro — agganciata
    /// alla griglia se una risoluzione è data.
    ///
    /// **L'aggancio non è un dettaglio: è ciò che rende il salto ripetibile.** Partendo da un
    /// punto qualsiasi — la testina che gira, o un cue piazzato a mano prima che ci fosse la
    /// griglia — il primo salto porta in battuta e i successivi ci restano. Senza, ogni salto si
    /// porterebbe dietro lo scarto iniziale, e dopo due o tre non si sarebbe più in battuta con
    /// l'altro deck.
    ///
    /// Il risultato può cadere fuori dalla traccia: tenerlo dentro tocca a chi muove la testina,
    /// che è l'unico a sapere quanto dura.
    public func seconds(
        afterJumping beats: Int,
        fromSeconds seconds: Double,
        snappingTo resolution: QuantizeResolution?
    ) -> Double {
        let target = seconds + Double(beats) * beatDuration
        guard let resolution else { return target }
        return snap(target, resolution: resolution)
    }

    /// Sposta il primo downbeat senza toccare il BPM, riportandolo dentro la prima misura.
    ///
    /// Il rientro non è cosmesi: senza, trascinando la griglia in avanti per qualche minuto
    /// l'offset crescerebbe indefinitamente e la stessa griglia sarebbe scritta in tabella con
    /// numeri sempre diversi.
    public func shifted(bySeconds delta: Double) -> Beatgrid {
        Beatgrid(bpm: bpm, offsetSeconds: Self.fold(offsetSeconds + delta, into: barDuration))
            ?? self
    }

    /// La stessa griglia con il primo downbeat portato su un istante scelto a mano.
    public func alignedDownbeat(toSeconds seconds: Double) -> Beatgrid {
        Beatgrid(bpm: bpm, offsetSeconds: Self.fold(seconds, into: barDuration)) ?? self
    }

    public func withBPM(_ newBPM: Double) -> Beatgrid? {
        Beatgrid(bpm: newBPM, offsetSeconds: offsetSeconds)
    }

    /// Riporta un istante dentro `[0, period)` seguendo la griglia.
    private static func fold(_ value: Double, into period: Double) -> Double {
        guard period > 0, value.isFinite else { return value }
        let folded = value.truncatingRemainder(dividingBy: period)
        return folded < 0 ? folded + period : folded
    }
}

/// Quanto fine è l'aggancio del quantize.
///
/// Solo due valori, ed è una scelta: senza loop l'unica cosa da quantizzare sono i cue, e per un
/// cue le suddivisioni sotto la mezza battuta non servono — un sedicesimo a 128 BPM sono 117 ms,
/// più di quanto si sbagli puntando a mano.
public enum QuantizeResolution: String, CaseIterable, Codable, Sendable {
    case beat
    case halfBeat

    public var beatFraction: Double {
        switch self {
        case .beat: 1
        case .halfBeat: 0.5
        }
    }

    /// Come si scrive sul pulsante, con la notazione dei CDJ.
    public var label: String {
        switch self {
        case .beat: "1/1"
        case .halfBeat: "1/2"
        }
    }
}
