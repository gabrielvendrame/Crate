// Clic e trascinamenti sintetici, per provare l'interfaccia invece di ragionarci sopra.
//
//   swiftc -O Scripts/ui-mouse.swift -o /tmp/ui-mouse
//   /tmp/ui-mouse click 648 204
//   /tmp/ui-mouse drag 648 204 648 122 30
//
// Le coordinate sono **punti dello schermo globale**, gli stessi che restituisce
// `Scripts/ui-ax-dump.swift`: prenderle da lì e non misurarle su uno screenshot.
//
// Richiede l'**Accessibilità** per `claude` (Impostazioni di Sistema → Privacy e sicurezza →
// Accessibilità). Il trascinamento ha bisogno di una pausa dopo il mouse down e di parecchi
// passi intermedi, altrimenti la sessione di drag non parte nemmeno.

import CoreGraphics
import Foundation

// Clic e trascinamenti sintetici, in punti dello schermo globale.
func post(_ type: CGEventType, _ point: CGPoint, _ button: CGMouseButton = .left) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
        .post(tap: .cghidEventTap)
}

let args = CommandLine.arguments
func number(_ index: Int) -> Double { Double(args[index]) ?? 0 }

switch args.first.map({ _ in args[1] }) ?? "" {
case "click":
    let point = CGPoint(x: number(2), y: number(3))
    post(.mouseMoved, point)
    usleep(120_000)
    post(.leftMouseDown, point)
    usleep(60_000)
    post(.leftMouseUp, point)

case "doubleclick":
    let point = CGPoint(x: number(2), y: number(3))
    post(.mouseMoved, point)
    usleep(120_000)
    for _ in 0..<2 {
        post(.leftMouseDown, point)
        usleep(40_000)
        post(.leftMouseUp, point)
        usleep(60_000)
    }

case "drag":
    let from = CGPoint(x: number(2), y: number(3))
    let to = CGPoint(x: number(4), y: number(5))
    let steps = args.count > 6 ? Int(args[6]) ?? 25 : 25

    post(.mouseMoved, from)
    usleep(200_000)
    post(.leftMouseDown, from)
    usleep(300_000)              // il tempo di far partire la sessione di drag
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        post(.leftMouseDragged, point)
        usleep(35_000)
    }
    usleep(400_000)              // fermo sul bersaglio, perché la lista mostri l'indicatore
    post(.leftMouseUp, to)

default:
    print("uso: mouse click|doubleclick x y  ·  mouse drag x1 y1 x2 y2 [passi]")
    exit(1)
}
