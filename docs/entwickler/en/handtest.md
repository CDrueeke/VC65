<!-- SPDX-License-Identifier: MIT-0 -->
# Hand test, spike N0, on a real MEGA65

German version: [../de/handtest.md](../de/handtest.md). Purpose: check what Xemu cannot show reliably (Attic speed, reset behaviour, logo colours, `BRK`). Please report the results in this table or to the VC65 session.

## Preparation

1. Build the package (Mac, in the repository): `tools/handtest.sh` creates `build/VC65TEST.D81` (all programs) and `build/VC65AUTO.D81` (reset test as autoboot).
2. Copy both files to the MEGA65 SD card (e.g. into a folder `VC65`).
3. On the MEGA65 mount `VC65TEST.D81` (disk menu), drive 8. The original ROM is assumed.
4. Load and run with `LOAD "NAME",8` and `RUN` (or `DLOAD "NAME"`, then `RUN`).

## Checks

| No | Program | Expected output | Result |
|---|---|---|---|
| 1 | `SPEED` | Four lines with ticks (`HAUPT SCHREIB`, `HAUPT LESEN`, `ATTIC SCHREIB`, `ATTIC LESEN`) and `FEHLER: 00`. **Write down the four values.** If the Attic lines are clearly larger than the main-memory lines, Attic is slower. Decision N-E11 | |
| 2 | `RUN` | `START UND RUECKKEHR OK` | |
| 3 | `RUNDMA` | `DMA, START UND RUECKKEHR OK` | |
| 4 | `BRK` | `BRK-RUECKKEHR OK` (if the machine hangs or lands in the monitor, please note it) | |
| 5 | `SD` | `DATEI GESCHRIEBEN UND GELESEN: OK`; afterwards the file `VC65TEST` is in the directory (`DIRECTORY`) | |
| 6 | `LOGO` | Logo "VC65." in 7 rows, light-blue blocks, yellow dot, black background; **judge colours and sharpness**. Any key quits | |
| 7 | Reset | Mount `VC65AUTO.D81` and restart the machine (autoboot runs `RESET`: `KENNUNG GESCHRIEBEN`). **Press the reset button**: if autoboot then reports `ATTIC ERHALTEN, LAUF NR 2`, the Attic survives the reset button. Then do a **cold start** (power off and on): `NR` should be 1 again, otherwise note it. Decision N-E10 | |

Notes: `SPEED` and `LOGO` need the normal start from BASIC 65. If a program stops without output, press the reset button and load it again. The programs write only to bank 0 from `$4000`, to the Attic (from `$8000000`, banks 1 and 8) and to drive 8; they touch the SD card only through the mounted D81. (Message texts in the programs are German.)

## Not yet checked on the device (IDE, as of 2026-11-24)

Everything below runs in Xemu but is **not** checked on a real MEGA65 and does not count as done:

| No | Item | Expected | Result |
|---|---|---|---|
| A | HELP key (code `$84`) opens the menu | drop-down appears; arrows, Return, STOP as described | |
| B | All menu items (File, Edit, Search, Build, Debug, Replace, Align) | run the command like the key shortcuts | |
| C | 50-row screen, header rows, problems panel, colours (light blue bar, grey bars, red error lines) | readable, right colours, no leftovers after returning from a program/the debugger | |
| D | Loading the file `VC65T` (instruction table) at start from disk | IDE starts; if the file is missing VC65 returns to BASIC | |
| E | Automatic check on line change | speed at every line change, texts up to 16 KB, no noticeable stall, no cursor jump | |
| F | Two D81 images (system disk and project drive), Ctrl+A switches 8/9 | libraries and project files are found | |
| G | Search menu: set mark / go to mark, find label; replace; align | work as described | |
| H | Bearb menu: hex calculator, insert data (file `VC65X`, loaded on first use) | result and inserted `.byte` lines are correct | |

## Xemu version
Checked with Xemu of **2026-01-29** (Mac, `xmega65`). With Xemu of **2024-09** (Windows) `prallball` shows a broken background and does not react to RESTORE (finding of the Windows session, presumably too old for full-colour characters and audio DMA; not yet cross-checked with a newer Windows build). The minimum version is fixed only after a newer Windows build has been checked.
