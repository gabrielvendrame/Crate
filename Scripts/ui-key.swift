// Preme un tasto per **codice fisico**, che è come li riconosce `DeckKeyMonitor`: un evento
// costruito con una stringa unicode ha keyCode 0 e non corrisponderebbe a niente.
//
//   swiftc -O Scripts/ui-key.swift -o /tmp/ui-key
//   /tmp/ui-key 49          preme e rilascia lo spazio (play/pausa)
//   /tmp/ui-key 8 hold 1.5  tiene premuto C — l'anteprima del CUE, che è la cosa che serve
//                           poter provare: press-and-hold non si verifica in altro modo
//
// Codici utili: 49 spazio · 8 C · 6 Z · 7 X · 2 D · 5 G · 18–28 i numeri 1–8.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let code = CGKeyCode(UInt16(args[1])!)
let hold = args.count > 3 ? Double(args[3]) ?? 0 : 0

func post(_ down: Bool, repeated: Bool = false) {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return }
    if repeated { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    event.post(tap: .cghidEventTap)
}

post(true)
if hold > 0 {
    // La ripetizione la genera il sistema su un tasto tenuto: qui va simulata.
    usleep(400_000)
    var elapsed = 0.4
    while elapsed < hold {
        post(true, repeated: true)
        usleep(60_000)
        elapsed += 0.06
    }
}
usleep(60_000)
post(false)
