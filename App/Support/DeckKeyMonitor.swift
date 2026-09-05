import AppKit
import DJKit

/// Intercetta i tasti `1`–`8` per gli hot cue del deck che ha il fuoco.
///
/// Non sono voci di menu con una scorciatoia: su macOS le *key equivalent* dei menu vengono
/// valutate **prima** del first responder, quindi una cifra senza modificatori scavalcherebbe i
/// campi di testo — digitare "1" nel campo dell'URL farebbe scattare un hot cue. Con un monitor
/// locale l'evento si può guardare e lasciar passare, che è ciò che serve.
///
/// Serve anche da appoggio per M7: il tasto CUE da tastiera ha bisogno di `keyDown` **e**
/// `keyUp`, che `keyboardShortcut` non sa dare.
@MainActor
final class DeckKeyMonitor {
    /// Codici dei tasti della riga dei numeri e del tastierino.
    ///
    /// Sono **posizioni fisiche**, non caratteri, e questo è il punto: con lo shift premuto
    /// `charactersIgnoringModifiers` restituisce `!` invece di `1` (e su un layout italiano
    /// altre cose ancora), quindi leggere i caratteri farebbe fallire proprio la combinazione
    /// che cancella l'hot cue.
    private static let slotByKeyCode: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8,
    ]

    /// Slot da 1 a 8, e se lo shift era premuto (cioè: cancella).
    private let onHotCue: (Int, Bool) -> Void
    /// Toccato solo da `install()` e dal `deinit`, che non è isolato: da qui il `nonisolated`.
    nonisolated(unsafe) private var monitor: Any?

    init(onHotCue: @escaping (Int, Bool) -> Void) {
        self.onHotCue = onHotCue
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // `NSEvent` non è `Sendable`, quindi oltre il confine dell'isolamento passano solo il
            // codice del tasto e i modificatori — che è tutto ciò che serve.
            let keyCode = event.keyCode
            let rawModifiers = event.modifierFlags.rawValue
            // I monitor locali arrivano sempre sul thread principale.
            let consumed = MainActor.assumeIsolated {
                self.handle(keyCode: keyCode, rawModifiers: rawModifiers)
            }
            return consumed ? nil : event
        }
    }

    /// `true` se l'evento è stato consumato.
    private func handle(keyCode: UInt16, rawModifiers: UInt) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: rawModifiers)
        let modifiers = flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.shift, .capsLock, .function, .numericPad])
        guard modifiers.isEmpty else { return false }
        guard let slot = Self.slotByKeyCode[keyCode] else { return false }
        guard !isEditingText, !isSheetPresented else { return false }

        onHotCue(slot, flags.contains(.shift))
        return true
    }

    /// Con un campo di testo attivo il first responder è il *field editor*, che è un
    /// `NSTextView`: è così che si riconosce che l'utente sta scrivendo e non pilotando un deck.
    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    /// Con un foglio aperto — l'import, per esempio — i tasti non devono arrivare ai deck.
    private var isSheetPresented: Bool {
        NSApp.windows.contains { $0.attachedSheet != nil }
    }
}
