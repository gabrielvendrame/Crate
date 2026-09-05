// Digita testo con eventi sintetici.
//
//   swiftc -O Scripts/ui-type.swift -o /tmp/ui-type
//   /tmp/ui-type "yamaha girl"
//
// Non passa da System Events, che per digitare porta in primo piano un'altra app e fa perdere il
// fuoco al campo appena cliccato. Gli eventi qui hanno **keyCode 0** e una stringa unicode: vanno
// bene per i campi di testo, non per le scorciatoie a tasto nudo dei deck, che si riconoscono dal
// codice fisico — per quelle c'è `ui-key.swift`.

import CoreGraphics
import Foundation

let text = CommandLine.arguments.dropFirst().joined(separator: " ")
for character in text.utf16 {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { continue }
        var unit = character
        event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
        event.post(tap: .cghidEventTap)
    }
    usleep(12_000)
}
