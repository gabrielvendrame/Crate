/// Interpolazione cubica Catmull-Rom fra quattro sample consecutivi.
///
/// È il cuore del varispeed: il playhead avanza a passo frazionario e ogni sample in uscita cade
/// fra due sample della traccia. L'interpolazione lineare, a pitch alzato, aggiunge un ronzio di
/// aliasing sugli alti che su un mixer si sente; la cubica costa tre moltiplicazioni in più per
/// canale e passa esattamente per i punti di controllo.
///
/// Vive in un tipo a parte perché è **l'unico pezzo puro** del render callback: qui si può
/// verificare con `swift test`, dentro il callback no.
public enum CubicInterpolator {
    /// Il valore fra `p1` e `p2`, con `t` da 0 (esattamente `p1`) a 1 (esattamente `p2`).
    /// `p0` e `p3` sono i sample immediatamente prima e dopo, e determinano la pendenza.
    @inline(__always)
    public static func sample(
        _ p0: Float,
        _ p1: Float,
        _ p2: Float,
        _ p3: Float,
        _ t: Float
    ) -> Float {
        let a = -0.5 * p0 + 1.5 * p1 - 1.5 * p2 + 0.5 * p3
        let b = p0 - 2.5 * p1 + 2 * p2 - 0.5 * p3
        let c = -0.5 * p0 + 0.5 * p2
        return ((a * t + b) * t + c) * t + p1
    }
}
