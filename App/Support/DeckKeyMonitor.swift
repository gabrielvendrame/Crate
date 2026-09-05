import AppKit
import DJKit

/// Intercetta i tasti **senza modificatori** che pilotano i deck.
///
/// Non sono voci di menu con una scorciatoia: su macOS le *key equivalent* dei menu vengono
/// valutate **prima** del first responder, quindi un tasto nudo scavalcherebbe i campi di testo —
/// digitare "1" nel campo dell'URL farebbe scattare un hot cue. Con un monitor locale l'evento si
/// può guardare e lasciar passare, che è ciò che serve.
///
/// Ed è anche l'unico modo di avere il **CUE tenuto premuto**: quel tasto ha bisogno di `keyDown`
/// *e* `keyUp` — press-and-hold, non una singola attivazione — e `keyboardShortcut` di SwiftUI il
/// rilascio non lo dà.
///
/// **Il prezzo è la selezione per digitazione nelle tabelle**: premendo "d" in libreria non si
/// salta più al primo brano che comincia per D, perché quel tasto se lo prende il deck. È il
/// motivo per cui in M7 è arrivata la ricerca (⌘F), che quel bisogno lo copre meglio.
///
/// L'elenco di ciò che risponde sta in `KeyboardShortcuts`, che è quanto legge il pannello di
/// aiuto: aggiungendo un tasto qui va aggiunta la riga anche là.
@MainActor
final class DeckKeyMonitor {
    /// Cosa fa un tasto. I casi sono azioni del deck, non nomi di tasti.
    enum Action: Equatable {
        case hotCue(Int)
        case togglePlay
        case cue
        case nudge(forward: Bool)
        case switchDeck
        case beatgrid
        case zoom(closer: Bool)
    }

    /// In che momento della pressione siamo.
    ///
    /// Le tre fasi servono perché il nudge da tastiera deve fare **due cose diverse**, come il suo
    /// pulsante: un colpo secco alla pressione, e la spinta tenuta quando il tasto resta giù. La
    /// ripetizione automatica del sistema è il segnale che il tasto è *tenuto*, e arriva dopo la
    /// pausa che macOS usa per distinguere un tocco da una pressione — che è esattamente la
    /// distinzione che serve.
    enum Phase { case down, held, up }

    /// I tasti che si riconoscono dalla **posizione fisica**, perché con `⇧` il carattere cambia:
    /// `⇧1` su una tastiera italiana non produce `1` ma `!`, e leggere i caratteri farebbe
    /// fallire proprio la combinazione che cancella l'hot cue.
    private static let actionByKeyCode: [UInt16: Action] = [
        18: .hotCue(1), 19: .hotCue(2), 20: .hotCue(3), 21: .hotCue(4),
        23: .hotCue(5), 22: .hotCue(6), 26: .hotCue(7), 28: .hotCue(8),
        83: .hotCue(1), 84: .hotCue(2), 85: .hotCue(3), 86: .hotCue(4),
        87: .hotCue(5), 88: .hotCue(6), 89: .hotCue(7), 91: .hotCue(8),
        49: .togglePlay,
    ]

    /// I tasti che si riconoscono dal **carattere stampato sopra**, che è come li si cerca con le
    /// dita. Nessuno di questi si usa con `⇧`, quindi il carattere è stabile; e `-` o `+` cambiano
    /// posizione fra un layout e l'altro, mentre il simbolo no.
    private static let actionByCharacter: [String: Action] = [
        "c": .cue,
        "z": .nudge(forward: false),
        "x": .nudge(forward: true),
        "d": .switchDeck,
        "g": .beatgrid,
        "-": .zoom(closer: false), "_": .zoom(closer: false),
        "+": .zoom(closer: true), "=": .zoom(closer: true),
    ]

    /// Quali azioni hanno bisogno anche del rilascio e della pressione tenuta.
    private static func isHoldable(_ action: Action) -> Bool {
        switch action {
        case .cue, .nudge: true
        default: false
        }
    }

    /// `isShifted` serve solo agli hot cue, dove significa "cancella".
    private let onAction: (Action, Phase, _ isShifted: Bool) -> Void

    /// Toccato solo da `install()` e dal `deinit`, che non è isolato: da qui il `nonisolated`.
    nonisolated(unsafe) private var monitor: Any?
    /// I tasti la cui pressione abbiamo consumato, per non mandare un rilascio spaiato — cosa che
    /// succede tenendo premuto C e cliccando altrove: il `keyUp` arriva comunque.
    private var pressed: Set<UInt16> = []
    /// I tasti già passati alla fase "tenuto": la ripetizione automatica arriva molte volte al
    /// secondo e la spinta va avviata una volta sola.
    private var held: Set<UInt16> = []

    init(onAction: @escaping (Action, Phase, Bool) -> Void) {
        self.onAction = onAction
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            // `NSEvent` non è `Sendable`, quindi oltre il confine dell'isolamento passano solo i
            // pochi valori che servono.
            let keyCode = event.keyCode
            let characters = event.charactersIgnoringModifiers ?? ""
            let rawModifiers = event.modifierFlags.rawValue
            let isDown = event.type == .keyDown
            let isRepeat = isDown && event.isARepeat
            // I monitor locali arrivano sempre sul thread principale.
            let consumed = MainActor.assumeIsolated {
                self.handle(
                    keyCode: keyCode,
                    characters: characters,
                    rawModifiers: rawModifiers,
                    isDown: isDown,
                    isRepeat: isRepeat
                )
            }
            return consumed ? nil : event
        }
    }

    /// `true` se l'evento è stato consumato.
    private func handle(
        keyCode: UInt16,
        characters: String,
        rawModifiers: UInt,
        isDown: Bool,
        isRepeat: Bool
    ) -> Bool {
        let flags = NSEvent.ModifierFlags(rawValue: rawModifiers)
        let modifiers = flags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.shift, .capsLock, .function, .numericPad])
        guard modifiers.isEmpty else { return false }

        guard let action = Self.actionByKeyCode[keyCode]
            ?? Self.actionByCharacter[characters.lowercased()]
        else { return false }

        if !isDown {
            // Il rilascio si manda solo se la pressione era stata presa da noi: altrimenti si
            // fermerebbe un'anteprima che non abbiamo avviato.
            let wasHeld = held.remove(keyCode) != nil
            guard pressed.remove(keyCode) != nil else { return false }
            guard Self.isHoldable(action) else { return true }
            // Senza pressione tenuta non c'è niente da chiudere: un colpo di nudge è già finito.
            if wasHeld || action == .cue { onAction(action, .up, flags.contains(.shift)) }
            return true
        }

        guard !isEditingText, !isSheetPresented else { return false }

        if isRepeat {
            // Le ripetizioni valgono solo dove tenere premuto ha un senso continuo, e la prima è
            // il momento in cui il tocco diventa pressione.
            guard Self.isHoldable(action), pressed.contains(keyCode) else { return true }
            guard held.insert(keyCode).inserted else { return true }
            onAction(action, .held, flags.contains(.shift))
            return true
        }

        pressed.insert(keyCode)
        onAction(action, .down, flags.contains(.shift))
        return true
    }

    /// Con un campo di testo attivo il first responder è il *field editor*, che è un
    /// `NSTextView`: è così che si riconosce che l'utente sta scrivendo e non pilotando un deck.
    private var isEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    /// Con un foglio aperto — l'import, l'aiuto — i tasti non devono arrivare ai deck.
    private var isSheetPresented: Bool {
        NSApp.windows.contains { $0.attachedSheet != nil }
    }
}
