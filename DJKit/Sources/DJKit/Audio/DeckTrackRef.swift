/// La descrizione della traccia in suono, nella forma in cui la legge il thread audio: solo
/// puntatori e numeri, niente riferimenti a oggetti.
///
/// Serve a tenere ARC **fuori** dal render callback. Se il callback dovesse risalire al
/// `DecodedTrack` da un `Unmanaged`, il solo fatto di legarlo a una variabile locale genererebbe
/// una retain/release: una chiamata di runtime che può bloccarsi su un lock interno, cioè
/// esattamente ciò che non può accadere in un thread real-time. Il main actor pubblica un
/// descrittore già risolto e tiene lui il riferimento forte all'oggetto.
struct DeckTrackRef {
    var left: UnsafePointer<Float>?
    /// `nil` per un file mono: il canale sinistro finisce su entrambe le uscite.
    var right: UnsafePointer<Float>?
    var frameCount: Int
    /// Di quanto avanza il playhead per ogni frame di uscita a pitch zero, cioè il rapporto fra
    /// la frequenza di campionamento del file e quella del grafo. A 44,1 kHz su un grafo a
    /// 48 kHz vale 0,919: il resampling è gratis, lo fa la stessa interpolazione del varispeed.
    var baseStep: Double
    var sampleRate: Double
}
