import Foundation

/// Formattazione dei tempi mostrati a schermo.
enum Timecode {
    /// `m:ss` per liste e durate.
    static func short(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// `m:ss.d` per la posizione su un deck: il decimo di secondo serve a capire dove si è
    /// finiti dopo uno scrub.
    static func precise(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.0" }
        let total = Int(seconds)
        let tenths = Int((seconds - Double(total)) * 10)
        return String(format: "%d:%02d.%d", total / 60, total % 60, tenths)
    }
}
