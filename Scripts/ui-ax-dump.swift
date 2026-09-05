// L'albero di accessibilità di un'app: ruoli, posizioni e dimensioni di ogni elemento.
//
//   swiftc -O Scripts/ui-ax-dump.swift -o /tmp/ui-ax-dump
//   /tmp/ui-ax-dump $(pgrep -x Crate)              # tutto, fino a 12 livelli
//   /tmp/ui-ax-dump $(pgrep -x Crate) AXRow 12     # solo le righe
//
// È il modo giusto di trovare dove cliccare: le posizioni sono già in punti dello schermo, da
// passare a `Scripts/ui-mouse.swift`. Misurare i pixel di uno screenshot e riscalarli porta a
// sbagliare bersaglio e a diagnosi false.
//
// Richiede l'**Accessibilità** per `claude`.

import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func string(_ element: AXUIElement, _ name: String) -> String {
    (attribute(element, name) as? String) ?? ""
}

func frame(_ element: AXUIElement) -> String {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = attribute(element, kAXPositionAttribute as String) {
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
    }
    if let value = attribute(element, kAXSizeAttribute as String) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return "(\(Int(position.x)),\(Int(position.y)) \(Int(size.width))×\(Int(size.height)))"
}

let filter = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let maxDepth = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 12

func walk(_ element: AXUIElement, depth: Int) {
    guard depth <= maxDepth else { return }
    let role = string(element, kAXRoleAttribute as String)
    let label = [
        string(element, kAXTitleAttribute as String),
        string(element, kAXDescriptionAttribute as String),
        string(element, kAXValueAttribute as String),
    ].filter { !$0.isEmpty }.joined(separator: " | ")

    let line = "\(String(repeating: "  ", count: depth))\(role) \(frame(element)) \(label)"
    if filter.isEmpty || role.contains(filter) { print(line) }

    for child in (attribute(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] {
        walk(child, depth: depth + 1)
    }
}

let pid = Int32(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
for window in (attribute(app, kAXWindowsAttribute as String) as? [AXUIElement]) ?? [] {
    walk(window, depth: 0)
}
