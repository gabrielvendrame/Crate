import Foundation
import GRDB

/// Stato di avanzamento di una traccia lungo la pipeline di import e analisi.
public enum AnalysisState: String, Codable, Sendable, CaseIterable {
    /// Riga creata, in attesa che la coda la prenda in carico.
    case pending
    /// yt-dlp sta scaricando l'audio.
    case downloading
    /// Audio presente, calcolo di peaks e tempo in corso.
    case analyzing
    /// Traccia utilizzabile: audio, peaks e metadati sono a posto.
    case ready
    /// Qualcosa è andato storto; il motivo sta in `Track.analysisError`.
    case failed

    /// La traccia è caricabile su un deck.
    public var isPlayable: Bool { self == .ready }
}

extension AnalysisState: DatabaseValueConvertible {}
