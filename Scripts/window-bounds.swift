// Limiti della finestra di un'app sullo schermo, per catturarne uno screenshot.
//
//   swiftc -O Scripts/window-bounds.swift -o /tmp/window-bounds
//   screencapture -x -R"$(/tmp/window-bounds Crate)" crate.png
//
// Legge `CGWindowListCopyWindowInfo`, quindi richiede la sola **registrazione dello schermo** e
// non l'Accessibilità. Catturare la finestra e non tutto lo schermo è anche una questione di
// riservatezza: sullo schermo di Gabriel c'è il suo lavoro.
//
// La finestra va portata in primo piano prima di catturare, altrimenti si fotografa ciò che le
// sta davanti: `osascript -e 'tell application "Crate" to activate'`.

import CoreGraphics
import Foundation

// Limiti della finestra di un'app, da CoreGraphics: serve solo la registrazione dello schermo.
let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Crate"
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for window in list {
    guard let owner = window[kCGWindowOwnerName as String] as? String, owner == name,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          let width = bounds["Width"], width > 200
    else { continue }
    print("\(Int(bounds["X"]!)),\(Int(bounds["Y"]!)),\(Int(width)),\(Int(bounds["Height"]!))")
    exit(0)
}
exit(2)
