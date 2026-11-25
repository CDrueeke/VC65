#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Baut die VCASM-Quellen von VC65 (Target mega65) nach build/ mit dem in tools/vcc.version festgelegten vcc.
# Aufruf: tools/build.sh [datei.asm ...]      (ohne Argument: alle src/**/*.asm mit .org)
# Umgebung: VCC = Pfad der vcc-Datei, VCC_DATA = zugehoeriger data-Ordner (Standard: Ordner der vcc-Datei).
set -e
cd "$(dirname "$0")/.."
. tools/vcc.version
VCC="${VCC:-$HOME/Development/vcc-bin/${VCC_COMMIT:0:8}/vcc}"
VCC_DATA="${VCC_DATA:-$(dirname "$VCC")/data}"
[ -x "$VCC" ] || { echo "vcc nicht gefunden: $VCC (VCC setzen)"; exit 1; }
got=$(shasum -a 256 "$VCC" | cut -d' ' -f1)
[ "$got" = "$VCC_SHA256_MAC_ARM64" ] || echo "WARNUNG: vcc-Pruefsumme weicht ab ($got)"
mkdir -p build
files=("$@")
[ ${#files[@]} -eq 0 ] && files=($(grep -rl '^\.org' src --include=*.asm))
for f in "${files[@]}"; do
  n=$(basename "$f" .asm)
  "$VCC" asm "$f" --target mega65 --data-dir "$VCC_DATA" -o "build/$n.prg"
done
