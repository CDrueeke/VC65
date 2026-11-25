#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Baut das Handtest-Paket fuer den echten MEGA65 nach build/: VC65TEST.D81 (alle Spike-Programme) und
# VC65AUTO.D81 (reset.prg als AUTOBOOT.C65 fuer den Reset-Test). Anleitung: docs/entwickler/de/handtest.md
set -e
cd "$(dirname "$0")/.."
. tools/vcc.version
VCC="${VCC:-$HOME/Development/vcc-bin/${VCC_COMMIT:0:8}/vcc}"
VCC_DATA="${VCC_DATA:-$(dirname "$VCC")/data}"
tools/build.sh
args=()
for n in speed run rundma brk sd logo reset; do args+=(--add "build/$n.prg:$(echo $n | tr a-z A-Z)"); done
"$VCC" disk d81 --data-dir "$VCC_DATA" -o build/VC65TEST.D81 --name VC65TEST --id 65 "${args[@]}"
"$VCC" disk d81 --data-dir "$VCC_DATA" -o build/VC65AUTO.D81 --name VC65AUTO --id 65 --add build/reset.prg:AUTOBOOT.C65
