#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Startet ein PRG headless in Xemu (Mac) und sichert Bildschirm und Hauptspeicher.
# Aufruf: tools/xrun.sh build/x.prg [Zeitlimit-Sekunden]
# Ergebnis: build/xrun.screen (Text), build/xrun.mem (384 KB Hauptspeicher, Bank 0-5). Exit 0 bei Lauf bis READY.
# Umgebung: XEMU_ARGS (weitere Xemu-Optionen, z. B. -initattic datei), XEMU (Pfad), XEMU_ROM (Pfad zur MEGA65.ROM, liegt nur im Xemu-Ordner, nie im Repository).
set -e
cd "$(dirname "$0")/.."
X="${XEMU:-/Applications/xmega65.app/Contents/MacOS/xmega65}"
R="${XEMU_ROM:-$HOME/Library/Application Support/xemu-lgb/mega65/MEGA65.ROM}"
[ -x "$X" ] || { echo "Xemu nicht gefunden: $X"; exit 2; }
[ -f "$R" ] || { echo "ROM nicht gefunden: $R"; exit 2; }
mkdir -p build
timeout "${2:-60}" "$X" -headless -sleepless -fastboot -besure -rom "$R" -prg "$1" -prgexit \
  -dumpscreen build/xrun.screen -dumpmem build/xrun.mem $XEMU_ARGS > build/xrun.log 2>&1
