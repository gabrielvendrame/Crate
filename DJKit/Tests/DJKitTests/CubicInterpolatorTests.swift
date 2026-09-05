import Testing
@testable import DJKit

@Suite("Interpolazione cubica")
struct CubicInterpolatorTests {
    @Test("A t=0 e t=1 restituisce esattamente i punti di controllo")
    func passesThroughControlPoints() {
        #expect(CubicInterpolator.sample(-1, 2, 5, 9, 0) == 2)
        #expect(abs(CubicInterpolator.sample(-1, 2, 5, 9, 1) - 5) < 1e-5)
    }

    /// Su una rampa lineare la Catmull-Rom è esatta: è la proprietà su cui poggiano i test del
    /// render, che verificano il varispeed contro una rampa.
    @Test("Su dati lineari coincide con l'interpolazione lineare")
    func exactOnLinearData() {
        for step in stride(from: 0.0, through: 1.0, by: 0.125) {
            let t = Float(step)
            let value = CubicInterpolator.sample(10, 20, 30, 40, t)
            #expect(abs(value - (20 + 10 * t)) < 1e-4)
        }
    }

    @Test("Su un segnale costante non introduce oscillazioni")
    func constantStaysConstant() {
        for step in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(abs(CubicInterpolator.sample(0.4, 0.4, 0.4, 0.4, Float(step)) - 0.4) < 1e-6)
        }
    }

    /// L'overshoot della Catmull-Rom su un gradino è noto e limitato: serve sapere che resta
    /// piccolo, perché su un transiente forte finisce nel segnale in uscita.
    @Test("Su un gradino l'overshoot resta contenuto")
    func boundedOvershoot() {
        var peak: Float = 0
        for step in stride(from: 0.0, through: 1.0, by: 0.01) {
            peak = max(peak, CubicInterpolator.sample(0, 0, 1, 1, Float(step)))
        }
        #expect(peak <= 1.2)
    }
}
