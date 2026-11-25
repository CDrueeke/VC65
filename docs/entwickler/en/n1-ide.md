<!-- SPDX-License-Identifier: MIT-0 -->
# VC65 as one program: editor and assembler (`src/ide`)

> **Language (as of 2026-11-24):** All texts of the program (menus, messages, input lines, debugger screen) are **English**; older German quotations of program texts in this developer documentation are obsolete (current texts: `src/ide/chrome.asm`, `src/editor/disp.asm`, `src/ide/ide.asm`, `src/debug/dbgui.asm`). Documentation and website stay German and English.

German version: [../de/n1-ide.md](../de/n1-ide.md). Sources: `src/ide/vc65.asm` (main program), `src/ide/ide.asm` (glue).

## Flow
`vc65.asm` includes all assembler modules, editor, display layer and file routines into **one** PRG (start with `RUN`, base page `$1F00`) and calls `ed_run`. The display layer has two hooks, set by `ide_init`:
- **Ctrl+E** (`SP_ASM`, key `$05`) → `ide_asm`: copy the editor text (without the gap) to `$0800_0000`, end marker 0, clear the include file table (`$0820_0000`), enable the file loader (drive 8), `asm_run`. Success: message "OK 123 Byte", output at `$0005_0000`, length `ed_olen`, load address `ed_ldadr` (the first `.org` before any output, `ldadr` in the assembler). Error: message "E204 Zeile 12 Spalte 5" (first error in the list) and the cursor jumps to the error line; errors in an include file show "in Datei n" instead of a column and do not jump.
- **Ctrl+F** (`SP_PRG`) → input line `Datei:` → `ide_prg`: writes the load address (2 bytes) and the output as a PRG under the name in `ed_oname`. Without assembling first it reports "Erst uebersetzen".
The key codes are provisional and unchecked on the device. The message appears in the status line from column 20 (message kind `MSG_DYN`, text in `dz_mbuf`).

## Start from bank 4 (`src/ide/boot.asm`)
Concept section 7: bank 0 belongs to the test program. BASIC loads the PRG into bank 0; `boot` copies the image (`$2000` to `IMG_END`) through 32-bit pointers to `$0004_2000`, uses `MAP` (A=`$00`, X=`$E4`, Y=`$00`, Z=`$34`) to show bank 4 at CPU addresses `$2000–$BFFF` and continues there; afterwards bank 0 is free. The **bridge** (bank 0 from `$1660`, about 380 bytes, always visible) restores the default map (`$00,$00,$00,$83`) for KERNAL calls:
- `KSETNAM` … `KREADST`: jump stubs named after the KERNAL routines; registers A, X, Y and flags pass through. `KSETNAM` copies the file name to bank 0 (`kname`) because the KERNAL reads it there.
- `kernal_getin`: waits for a key (interrupts enabled only meanwhile); `krun`: calls the test program (`kr_t`); `kdefault`/`kide`: switch the map.
**Lessons (all found in Xemu):** (1) 32-bit pointers (`[zp],z`) do not see through `MAP`: reading image data that way needs the bank 4 address. (2) The KERNAL requires Z = 0 and may enable interrupts; the bridge sets Z and then `sei` again, otherwise an IRQ jumps through the vector at `$FFFE` into nothing (the IDE map hides the ROM at `$E000`). (3) Self-modifying code in the bridge needs a 16-bit placeholder (`$0100,x`), otherwise `$0000,x` becomes a zero-page instruction. (4) Bank 1 holds BASIC data from `$1_0000`: tests may only write small result areas there; test output therefore goes to bank 4 below the image (`$0004_0000`).
The assembler's stage-2 data lives in bank 5 in the IDE (`IDE_BUILD`, `S2BANK = 5`), the output in the Attic from `$0850_0000`.

## Run program (Ctrl+R)
`ide_run` (hook `SP_RUN`, key `$12`) copies the output from the Attic to bank 0 at the load address (not below `$2000`), jumps to the SYS address for a `.basicstub`, else to the load address, and calls via `krun` (default map, interrupts enabled). If the program returns with `RTS` the IDE reports "Programm beendet"; bank 4 with the IDE stays untouched. A program that does not return needs a reset (emergency key comes with the debugger). Test: `tools/idetest.py` starts a program that writes `$42` to `$C500`.

## Memory map (bank 0)
| Area | Contents |
|---|---|
| `$0800–$0FCF` | screen; the core draws **directly** into it (`ed_scr = $0800`) |
| `$1000–$11FF` | **unusable**: overwriting it hangs BASIC on return (ROM system area) |
| `$1200–$17FF` | assembler buffers (`curgstk`, `onelist`, `cynames`, `cyrep`, `inname`, `inpath`, `inpath2`, `filebase`, `fr`) |
| `$1800–$1EFF` | `fnames` (1 KB), `ptbl`, `ldbuf`, `fbuf` |
| `$1F00–$1FFF` | base page (zero page relocation) |
| `$2001–$BFFF` | free for the test program (the IDE runs from bank 4, see above; its image ends around `$BDxx`) |
| `$C000–$CFFF` | **not for code**: the ROM covers this area when reading (writes would go to RAM) |
Colours: `ED_ATTR32 = $0FF8_0000` (colour RAM, `DISP_DIRECT = 1`); the tests use a buffer in bank 0 instead and let the display layer copy it. Attic: source `$0800_0000`, symbols `$0810_0000`, jump table `$0812_0000`, file table `$0820_0000`, editor texts and histories of the tabs `$0830_0000`–`$084F_FFFF` (256 KB each), clipboard `$0870_0000`, tab records `$0870_8000`. Bank 4: stage-2 data of the assembler, bank 5: output.

**Lesson:** the code is close to the bank 0 limit (`$C000`). If the program grows it needs bank switching (`MAP`) or moving tables out; that is the next architectural step (bridge stub, concept section 7).

**Addendum (debugger):** the IDE map now shows bank 4 at `$2000–$FFFF` (MAP X=`$E4`, Z=`$F4`), the main program may reach `$CFFF` (currently about `$C4A0`), above it lies the overlay `VC65D` from `$D000`. Bank 4 `$0004_0000–$0004_1FFF` stays free (test output). Build: `tools/build_ide.py`. Details: [n8-debugger.md](n8-debugger.md).


**Memory plan of the IDE image (bank 4, CPU addresses; as of 2026-11-24):** `$2000–$CFFF` main program `VC65` (limit `$D000`, because BASIC cannot load above it due to the I/O area; now ends at `$CE32`, 462 bytes to spare), `$D000–$DF9F` the editor's 50-row screen, **shared** with the debugger's buffers and screen (`DV_I` `$D000`, `DV_T` `$D080`, `DV_D` `$D100`, `DV_S` `$D200`; the editor redraws after the session), `$E000–$F5FF` overlay `VC65D`, `$F500–$FFC9` table file `VC65T` (instruction table `optab.asm`, about 2.3 KB, and writable buffers from `src/ide/tbss.asm`: align, search pattern, replacement, message, input line; in the sources under `.ifndef IDE_BSS`), `$FFFA–$FFFF` vectors. `ide_ldtab` loads `VC65T` at start with the same routine as the overlay (`ov_get`); if the file is missing, VC65 returns to BASIC. `tools/build_ide.py` builds `VC65T` first and writes `build/optabsyms.asm` (all names as constants), which the main program includes instead of `optab.asm`; the IDE test programs (`tools/idetest.py`, `tools/ide50test.py`) take the same route.

## 50-row screen (VIC-IV, as of 2026-11-24)

In the IDE the editor shows **80 × 50** characters (`IDE_ROWS = 50` in `src/ide/vc65.asm`; `IDE_ROWS = 25` builds the old 80×25 screen at `$0800`). The display layer (`src/editor/disp.asm`: `disp_mode`, `disp_vic`) switches the VIC-IV for this. All register facts come from the **MEGA65 Chipset Reference** (section "VIC-IV / MEGA65 Specific Registers", pages 26–30 and 55–58 of the edition `mega65-chipset-reference_cnFcKB.pdf`) and were measured in **Xemu** (build 2024-09-26) (probe programs `src/spike/vicprobe.asm` and `src/spike/flatio.asm`, evaluated through the Xemu monitor `tools/xmon.py`); they still have to be checked on a real MEGA65 (hand test below).

| Register | Meaning (source) | Measured in Xemu |
|---|---|---|
| `$D031` bit 3 `V400` | 400 vertical pixels. "Hot" register: every write to `$D011`, `$D016`, `$D018`, `$D031` or the bank bits of `$DD00` makes the VIC-IV recompute its display registers (p. 28–30) | start `$E0` (H640, FAST, ATTR); with V400 `$E8` |
| `$D07B` `DISPROWS` | text rows minus 1: the hot register sets 24 (V200) or 49 (V400) (p. 29) | `$18` → `$31` |
| `$D05B` `CHRYSCL` | vertical character scale, also set by the hot register (p. 29; the text says "0 for V200, 1 for V400" and at the same time "1 or 2 pixels tall"; the two statements do not agree) | stays `$00` (Xemu does not model it); **check on the MEGA65** |
| `$D058/$D059` `LINESTEP` | bytes per text row; the hot register sets 80 with H640 (p. 30) | `$0050` |
| `$D05E` `CHRCOUNT` | characters per row; the hot register sets 80 with H640 | `$50` |
| `$D060–$D062` `SCRNPTR` | screen RAM address (24 bit, p. 26); the hot register resets it to the value derived from `$D018`/`$DD00` | `$000800` at start; `$0800` again after writing `$D031` |
| `$D064/$D065` `COLPTR` | offset into colour RAM (p. 27); the hot register resets it to 0 | 0 |
| `$D02F` | VIC-IV unlock: `$47`, then `$53` | – |

**Access:** through the flat address `$0FFD30xx` (32-bit pointer `CP`, `[CP],z`), i.e. without the I/O map at `$D000` (hidden in the IDE map). Measured in Xemu: `$D031`, `$D07B` and `SCRNPTR` can be read and written this way.

**Space:** 80 × 50 is 4000 bytes of characters and 4000 bytes of colour. That does not fit at `$0800` (`$1000–$11FF` must not be written, `$1200–$17FF` belongs to the assembler, the bridge is at `$1648`). The screen therefore lives at **`$0004_D000–$0004_DF9F`** (bank 4, visible in the IDE image as CPU address `$D000`, `ed_scr = $D000`); `SCRNPTR` points there (`ED_SCRPHYS`). The main program must stay below `$D000` (currently `IMG_END` = `$CC61`; `build_ide.py` does not check the limit: watch `IMG_END` when the program grows). Colours are in colour RAM from `$0FF8_0000` (3999 bytes, `COLPTR` = 0). The debugger overlay only starts at `$E000`.

**Switching back:**
- *Programs* (Ctrl+R, Ctrl+D): `krun` clears V400 (`$D031` bit 3) in the standard map. The hot register resets `DISPROWS` to 24, `SCRNPTR` to `$0800` and `COLPTR` to 0; the program sees the usual 80×25 screen. After the return (`ide_run`) `disp_mode` sets the 50-row screen again.
- *Debugger:* its screen has 25 rows (`$0004_D200`, colours from colour RAM `$1000`, formerly `$0800`: that was inside the colour RAM of the 50-row editor). `dv_start` saves the IDE state (`DV_I`, 50 rows), briefly clears V400, lets the hardware compute the registers for 25 rows and saves this state as the basis of `DV_D` (so `CHRYSCL` is right without an assumption), restores `DV_I` and sets the pointers to the debugger screen. `dv_end` brings the IDE (50 rows) back.
- *Exit:* `main` selects 25 rows before returning to BASIC.
- **`SCRNPTR` gets reset:** any disk access (hypervisor, D81 image) resets `$D061` (measured in Xemu: Ctrl+E with access to the D81, `$D061` `$D0` → `$10`; cause not found in the source). `disp_flush` therefore sets `SCRNPTR` again before every redraw (`disp_vic`), and `dv_start` does it before remembering the IDE state.

**Test:** `tools/ide50test.py` (Xemu with UART monitor, `tools/xmon.py`, without `-prgexit`): image (characters and colours against the Python model, 50 rows), scrolling, program run (the program sees V400 off, `DISPROWS` 24, `SCRNPTR` `$0800`; afterwards 50 rows), debugger (25 rows, back to 50 after `c`). State: all cases pass. The 25-row build (`IDE_ROWS = 25`) starts unchanged (Xemu: `$D031` `$E0`, `DISPROWS` 24, screen `$0800`). The existing tests (`idetest.py`, `dbgtest.py` etc.) were not run here (the Xemu build 2024-09 does not know `-prgexit`); `idetest.asm` stays at 25 rows and uses the stand-in `disp_vic: rts`.

**Hand test on a real MEGA65 (open):**
1. Start the IDE: 50 rows visible (even rows, last row = status line), character height 8 pixels, no flicker.
2. Ctrl+E (with includes from disk) and Ctrl+K (save to disk): does the screen stay or jump (SCRNPTR reset, see above)?
3. Ctrl+R: the program runs in the 80×25 standard; afterwards the 50-row screen is back. Ctrl+D: debugger screen readable with 25 rows, normal character height (checks `CHRYSCL`/character height of the hardware), key V shows the program screen, quitting returns to 50 rows.
4. PAL and NTSC, display on monitor/TV (borders: 50 rows × 8 pixels = 400 raster lines, as with V400).

## IDE frame: command bar, file line, problems panel (`src/ide/chrome.asm`, as of 2026-11-24)

Moved closer to the drafts in `docs/mockups` (drafts; the menus with drop-downs do not exist yet). 50-row screen: row 0 **command bar** (reversed, shows the Ctrl keys: load, save, build, run, debug, breakpoint, drive), row 1 **file line** (file name and project drive; there are no tabs), then the text, below it the **problems panel** (4 rows: header and up to three entries of the last build, errors red `E205 Zeile 10 Spalte 13`, warnings yellow `W206 …`, otherwise "Keine Probleme"), last the status line. **Menu** (HELP key, `chrome_menu`): drop-downs File, Edit, Search, Build, Debug (names as in the German bar); left/right switches, up/down selects, Return executes (the command goes to the main loop like a key press, hook `disp_menuv`, code `SP_MENU`), STOP/HELP closes; the boxes show the key shortcuts. The code `$84` of the HELP key is unchecked on the device (key-script test in `tools/idetest.py`: `menue_*`). **Automatic check** (`ide_auto`, hook `disp_autov`): when the cursor line changes and the text has changed since the last assembly, the IDE assembles by itself, silently (like Ctrl+E but without message and without cursor jump); the problems panel and red lines are current afterwards, and so is the output. Only for texts under 16 KB (about 0.2 s per run with a system file in Xemu); larger texts still use Ctrl+E. Tests `auto_ok`, `auto_fehler` in `tools/idetest.py`. **Error lines** (only with `ed_deco`): after Ctrl+E the lines with errors in the main program (up to 16, `ide_emark`) show in red (`er_chk`); the colouring holds until the text changes (`ed_ehp` = `hp` at assembly). **Decoration** (`ed_deco`, IDE only): a vertical rule after the line numbers, the cursor line carries `>` and a yellow number, the command bar is light blue, the problems header and the status line are grey bars (reversed video). The 25-row screen only gets the two header rows.

- **Editor core**: `ed_layout` (A = header rows, X = footer rows) sets how many rows at the top and bottom the core skips; text rows `ed_trows = ed_rows - 1 - header - footer`. `ed_init` sets 0/0 (all earlier tests unchanged). Paging and view follow `ed_trows`; the cursor sits `ed_hdr` rows lower (`disp_show`).
- **Drawing**: `chrome_init` (after `ed_init`) sets 2 header rows and, at 50 rows, 4 footer rows, and hooks `chrome_draw` into `disp_tabdv`; it runs after every core redraw.
- **Problems**: `ide_plist` (after `asm_run`) writes up to three lines from the error and warning lists (errors first) with the text of the message (`ia_msg`, without the cursor jump) to `PQ_BASE` (`$0870_F000`, Attic, 64 bytes per line).
- **Space**: see the memory plan above (the instruction table lives in `VC65T`); `tools/build_ide.py` aborts above the `$D000` limit.
- **Test**: `tools/edtest.py` checks header/footer rows (seeds 100/101: state and text rows like an editor with fewer rows); screenshots with the frame: `tools/screens.py --50`.

## Test
`tools/idetest.py` loads sources into the editor (via the Attic), presses Ctrl+E (and Ctrl+F) and compares in Xemu: output bytes and the saved PRG file (read from the D81) with vcc, error code and line, and the cursor line on errors; plus an include case via the D81. Status: all cases identical. The other tests (30 assembler tests, include, cycles, error list, self-compilation, conformance, editor and display) run unchanged.

## System disk and project drive

The MEGA65 system files (`<mega65/…>`, `<common/…>`, `<c64/hardware.asm>`, plus the chip symbols `vic2.border` etc.) live on the **system disk**, the D81 that holds VC65 itself (drive 8, `ed_sdev`). The source lives on a **second D81** (project drive `ed_fdev`, default 8, switched between 8 and 9 with **Ctrl+A** (`$01`), message "Projektlaufwerk 9"). Loading, saving and the user's includes (`.include "file"`) go to the project drive; libraries and the VC65D overlay go to the system disk.

Name mapping (D81 names are at most 16 characters, no folders): `<folder/name.ext>` → `FLD.NAME` from the first three characters of the folder and the name without extension, upper case, e.g. `<mega65/vic4.asm>` → `MEG.VIC4`, `<common/tiles.asm>` → `COM.TILES`, `<c64/hardware.asm>` → `C64.HARDWARE`. The chip file (`sys/mega65/chips.asm`, generated by `tools/gen_chips.py`) is called `MEG.CHIPS` and is included by the assembler itself in every pass; if it is missing there are just no chip symbols.

`tools/mksysdisk.py` builds the system disk (14 files, about 150 KB). `tools/systest.py` checks in Xemu with two D81 (system disk in drive 8, project disk in drive 9) that the result is byte-identical to `vcc`. Not checked on a real MEGA65: mounting two images and the KERNAL's device switching.
