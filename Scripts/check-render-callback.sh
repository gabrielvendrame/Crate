#!/bin/bash
# Verifica che nel render callback audio non finiscano chiamate proibite.
#
# La regola più importante di questo progetto — nessuna allocazione, nessun lock, nessuna chiamata
# al runtime Objective-C dentro il callback — è anche la più facile da violare per sbaglio e la più
# difficile da diagnosticare dopo: si manifesta come un click ogni tanto, sotto carico, su una
# macchina e non su un'altra. Un profilo con Instruments la vedrebbe solo se il difetto capita
# proprio mentre si registra.
#
# Qui invece si guarda il **codice generato**: si disassembla la catena di funzioni che parte dal
# render block e si cerca una chiamata a malloc, al retain/release di Swift, a objc_msgSend o a un
# lock. È una prova statica, ripetibile e che non dipende da cosa succede a runtime.
#
#   ./Scripts/check-render-callback.sh
#
# Esce con 1 se trova qualcosa, così può stare in una verifica automatica.
#
# **Che il controllo sappia fallire è stato visto**: includendo per sbaglio anche la fabbrica
# `makeRenderBlock` — che gira una volta sola e lì un retain ci sta — lo script ha segnalato il suo
# `swift_retain`. Un controllo di questo tipo che non ha mai detto di no non è ancora un controllo.

set -euo pipefail
cd "$(dirname "$0")/.."

# **Il binario linkato, non l'oggetto `DJKit.o`.** Nell'oggetto le chiamate non hanno ancora un
# bersaglio — `bl 0x24ccc` e nient'altro — quindi una verifica fatta là non guarda niente e passa
# sempre. È il primo modo in cui questo controllo può mentire.
PRODUCTS="$HOME/Library/Developer/Xcode/DerivedData/Crate-ccwemjglglgepydupulkiluzdkvq/Build/Products/Debug"
BINARY="${1:-}"
if [ -z "$BINARY" ]; then
  for candidate in \
    "$PRODUCTS/Crate.app/Contents/MacOS/Crate.debug.dylib" \
    "$PRODUCTS/Crate.app/Contents/MacOS/Crate"; do
    # `grep -q` esce al primo risultato e manda SIGPIPE a `nm`: con `pipefail` la pipeline
    # risulterebbe fallita proprio quando il simbolo **c'è**. Si conta invece di uscire prima.
    found=$(nm "$candidate" 2>/dev/null | grep -c DeckRenderState || true)
    if [ -f "$candidate" ] && [ "$found" -gt 0 ]; then
      BINARY="$candidate"
      break
    fi
  done
fi

if [ -z "$BINARY" ] || [ ! -f "$BINARY" ]; then
  echo "Binario con i simboli di DJKit non trovato."
  echo "Compila prima: xcodebuild -project Crate.xcodeproj -scheme Crate build"
  exit 2
fi
echo "Binario: $BINARY"

python3 - "$BINARY" <<'PY'
import re, subprocess, sys

binary_path = sys.argv[1]

# Da dove parte la catena: quello che AVAudioSourceNode chiama **a ogni buffer**.
#
# Non la fabbrica `makeRenderBlock`, che gira una volta sola alla costruzione del deck e lì un
# retain per catturare lo stato nella closure è giusto che ci sia. Contano la closure che ne esce
# (`…TtYbcfU_`), il suo forwarder (`…TA`) e il corpo vero del render.
def is_root(name):
    if "DeckRenderStateC6render" in name:
        return True
    if "DeckEngineC15makeRenderBlock" in name:
        return name.endswith("TtYbcfU_") or name.endswith("TA")
    return False

# Cosa non deve comparire. Ognuna di queste è una chiamata che può bloccare o allocare, e sul
# thread audio un blocco di un millisecondo è un buco nel suono.
FORBIDDEN = {
    "swift_retain": "retain di Swift (prende un lock nel runtime)",
    "swift_release": "release di Swift",
    "swift_bridgeObjectRetain": "retain di un bridge object",
    "swift_bridgeObjectRelease": "release di un bridge object",
    "swift_allocObject": "allocazione di un oggetto Swift",
    "swift_slowAlloc": "allocazione",
    "swift_arrayInit": "costruzione di un array",
    "objc_msgSend": "chiamata al runtime Objective-C",
    "objc_retain": "retain Objective-C",
    "objc_release": "release Objective-C",
    "_malloc": "malloc",
    "_calloc": "calloc",
    "_free": "free",
    "os_unfair_lock": "lock",
    "pthread_mutex": "mutex",
    "swift_beginAccess": "controllo di accesso esclusivo (prende un lock globale)",
    "swift_task_": "runtime della concorrenza",
    "dispatch_": "libdispatch",
}

disassembly = subprocess.run(
    ["otool", "-tV", binary_path], capture_output=True, text=True, check=True
).stdout

# `otool -tV` stampa una funzione per volta, con l'etichetta del simbolo su una riga sua.
functions, current = {}, None
for line in disassembly.splitlines():
    if line.startswith("_$s") and line.rstrip().endswith(":"):
        current = line.rstrip()[:-1]
        functions[current] = []
    elif current is not None:
        functions[current].append(line)

def demangle(symbol):
    result = subprocess.run(
        ["swift", "demangle", "-compact", symbol], capture_output=True, text=True
    )
    return result.stdout.strip() or symbol

# Due forme, entrambe presenti nell'output di `otool -tV` su un binario linkato:
#   bl  _$s5DJKit...            chiamata diretta a una funzione con simbolo
#   bl  0x4f5534 ; symbol stub for: _swift_release
CALL = re.compile(r"\bbl\s+(?:0x[0-9a-f]+\s*;\s*symbol stub for:\s*)?([A-Za-z_$][\w$.]*)")

visited, findings, chain = set(), [], []

def walk(name, path):
    if name in visited:
        return
    visited.add(name)
    chain.append((name, path))
    for line in functions.get(name, []):
        match = CALL.search(line)
        if not match:
            continue
        target = match.group(1).lstrip("_")
        for needle, why in FORBIDDEN.items():
            if needle.lstrip("_") in target:
                findings.append((name, target, why, path))
        # Si scende solo dentro DJKit: le funzioni di sistema non si possono ispezionare, e
        # quelle vietate sono già state riconosciute per nome.
        for candidate in (match.group(1), "_" + match.group(1)):
            if candidate in functions:
                walk(candidate, path + [name])

roots = [name for name in functions if is_root(name)]
if not roots:
    print("Nessuna funzione di render trovata: la verifica non ha guardato niente.")
    sys.exit(2)

for root in roots:
    walk(root, [])

# Si stampa cosa è stato guardato: una verifica che non dice cosa ha attraversato non si distingue
# da una che non ha attraversato niente, ed è così che questi controlli mentono.
print(f"Funzioni attraversate a partire dal render callback: {len(visited)}")
for name, _ in sorted(chain):
    print(f"  · {demangle(name)}")
print()
if findings:
    print("\nCHIAMATE PROIBITE NEL PERCORSO DEL RENDER CALLBACK:\n")
    for where, target, why, path in findings:
        print(f"  in  {demangle(where)}")
        print(f"  chiama  {target}  — {why}")
        if path:
            print(f"  raggiunta da: {' → '.join(demangle(p) for p in path)}")
        print()
    sys.exit(1)

print("Nessuna allocazione, nessun lock, nessuna chiamata al runtime.")
PY
