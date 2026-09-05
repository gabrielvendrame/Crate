import SwiftUI

/// Un tasto di nudge: **un colpetto sposta, tenuto premuto spinge**.
///
/// Sono due gesti diversi perché servono a due cose diverse. Il colpetto sposta la testina di un
/// passo esatto, ed è quello che serve quando si guarda la waveform e si vede di quanto si è
/// fuori. Tenerlo premuto accelera finché lo si tiene, come il dito sul bordo del piatto: sposta
/// la fase senza lo schiocco che dà il salto, ed è quello che serve a orecchio, mentre le due
/// tracce suonano.
///
/// La distinzione è a tempo: sotto un quarto di secondo è un colpetto, oltre è una spinta. Il
/// ritardo prima che la spinta parta non si nota, perché una spinta la si tiene comunque.
struct NudgeButton: View {
    enum Direction {
        case backward
        case forward

        var symbol: String {
            switch self {
            case .backward: "chevron.left"
            case .forward: "chevron.right"
            }
        }
    }

    let direction: Direction
    let isEnabled: Bool
    let onTap: () -> Void
    let onBendStart: () -> Void
    let onBendEnd: () -> Void

    private static let holdThreshold = Duration.milliseconds(250)
    private static let cornerRadius: CGFloat = 4

    @State private var holdTask: Task<Void, Never>?
    @State private var isBending = false

    var body: some View {
        Image(systemName: direction.symbol)
            .font(.caption2.weight(.bold))
            .frame(width: 26, height: 18)
            .background(
                isBending ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .controlColor)),
                in: RoundedRectangle(cornerRadius: Self.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.separator)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .gesture(gesture)
            .help(isEnabled ? "Un colpetto sposta di poco · tieni premuto per spingere" : "Nessun audio caricato")
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled, holdTask == nil, !isBending else { return }
                holdTask = Task { @MainActor in
                    try? await Task.sleep(for: Self.holdThreshold)
                    guard !Task.isCancelled else { return }
                    isBending = true
                    onBendStart()
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                if isBending {
                    isBending = false
                    onBendEnd()
                } else if isEnabled {
                    onTap()
                }
            }
    }
}
