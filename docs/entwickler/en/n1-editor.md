<!-- SPDX-License-Identifier: MIT-0 -->
# Editor (N1): core and display

German version: [../de/n1-editor.md](../de/n1-editor.md). Source: `src/editor/ed.asm`.

## Structure
- **Gap buffer in Attic** (`$0830_0000`, 768 KB): text with LF line ends, 32-bit positions, byte 0 never occurs in text.
- **Input and output are separate**: `ed_key` takes a key code, `ed_view` draws into a screen buffer (`ed_scr`, colours `ed_attr`). Keyboard and VIC-IV hookup come later.
- **Screen**: 80 columns, 25 or 50 rows, 5-column line-number gutter, last row = status line. Colouring by a lexer (comment, string, number, directive, label, mnemonic via `mn_find`).
- **Keys**: characters, Return (auto-indent), Tab (to multiples of 4), Backspace, Delete, arrows, Home/End, PgUp/PgDn, `$1A` undo, `$19` redo.

## Undo / redo
Every change (insert or delete one byte) is logged in the history (`$083C_0000`, 16 bytes per entry: kind, byte, group, position, cursor before, cursor after). Consecutive keys of the same kind (characters/Tab, Return, Backspace, Delete) form a **group**; any other key starts a new one. Undo reverts the whole last group, redo replays it. A new edit discards the redo steps. `ed_load` does not log and clears the history. After undo/redo the line number is recounted (`ed_recount`).

## Search and go-to-line
Both are routines for the future input line (the UI follows with the display layer), not keys yet.
- `ed_find_next` / `ed_find_prev`: pattern in `ed_pat` (up to 32 bytes), length in `ed_patn`. Searching starts after (before) the cursor and wraps around the end (start) of the text; case is ignored. Hit: carry set, cursor on the match; otherwise carry clear and cursor unchanged. An empty pattern or empty text finds nothing.
- `ed_goto`: line number in `ed_garg`; 0 means 1, past the last line the cursor lands at the start of the last line.
- Both end the current undo group (like a key without a change) and recount the line number.
- Test: the differential test uses commands in the key script (`$FE` + `g lo hi`, `f n pattern`, `n`, `p`).

## Selection and clipboard
- **Selection** = range between anchor (`ed_anc`) and cursor while `ed_sel` is set. `$02` (Ctrl+B) sets the anchor at the cursor or clears the selection; movement keys extend it. Selected characters get the bit `SELF` (`$20`, reverse video) in their colour byte.
- **Clipboard** in Attic (`$0870_0000`, at most 64 KB, length `ed_cblen`): `$03` copy (clears the selection), `$18` cut, `$16` paste (an active selection is replaced). If the selection is too large or the buffer full, nothing happens.
- Backspace/Delete remove an active selection; characters, Return, Tab, undo and redo clear it. Cut, paste and removing a selection are each **one** undo group.
- The clipboard survives loading a new text (paste between files).

## Display layer (`src/editor/disp.asm`)
Connects the core to the MEGA65: screen buffer to the screen, keyboard, input line. The caller defines `ed_scr`/`ed_attr` (2000 bytes each, bank 0), calls `ed_init` (25 rows) and `ed_load`, then `ed_run` (returns on STOP).
- **Screen**: standard text mode 80×25; screen codes to `$0800`, colour RAM through the 32-bit pointer `$0FF8_0000` (lesson from spike N0). `disp_init` sets border/background black and the attribute mode (`$D031` bit 5). The `SELF` bit (`$20`) acts as reverse video (checked in Xemu with screenshots: `$20` inverts, `$40` blinks/tints, `$10` hides). In the IDE map the I/O area is hidden; `disp_init` therefore calls the bridge routine `kvic` (border, background, `$D031`) and switches to the upper/lower-case character set through the KERNAL with PETSCII `$0E` (status line: `Z`/`S` as capitals `$5A`/`$53`). The text cursor is the same bit on its cell, toggled so it stays visible inside a selection.
- **Keyboard**: KERNAL GETIN (PETSCII), blocking, with base page 0 and interrupts enabled only meanwhile; replaceable through the pointer `disp_keyv` (tests feed a key script). Letters are converted PETSCII→ASCII.
- **Key map** (table `kmap_in`/`kmap_out`): F1 find (input line), F2 find next, F3 go to (input line), F4 find backwards, F5 mark, F6 copy, F7 cut, F8 paste, `$10`/`$15` undo/redo, `$16`/`$17` page up/down, CLR end of line, Shift+DEL delete forward, STOP quit; cursor keys, Home, Return, Tab, DEL and printable characters go to the core unchanged.
- **Input line**: replaces the status line (`Suche: …` / `Zeile: …`), Return accepts, STOP cancels, DEL removes a character; find edits the last pattern (up to 32 characters), go-to takes at most 4 digits.
- **50 rows**: connected in the IDE (VIC-IV V400, screen `$0004_D000`), see [n1-ide.md](n1-ide.md). **Not yet**: messages ("not found"), load/save, menu. The hardware mapping (F-key codes, reverse bit) cannot be checked in Xemu and belongs to the hand test.
- **Test**: `tools/disptest.py [count] [start]` (`src/test/disptest.asm`) plays PETSCII key scripts and compares screen codes and colour RAM of the final frame (also with an open input line) and the core state against a Python model. Status: seeds 1–40 and 200–239 identical.

**Direct drawing:** the core writes character codes to `ed_scr` and colours through the 32-bit pointer `ED_ATTR32` (`dw_attrptr`); with `DISP_DIRECT = 1` (IDE) `ed_scr` is the screen and `ED_ATTR32` the colour RAM, so the display layer copies nothing. The tests set `DISP_DIRECT = 0` and a buffer in bank 0.

## Load and save (`src/editor/file.asm`)
Through the KERNAL file routines (drive `ed_fdev`, default 8: SD card or D81), plain file names only (folders and long names follow with direct Hyppo access, as with the assembler's file loader). Name in `ed_fname` (at most 16 characters, length `ed_fnl`); lower-case letters are upper-cased for the drive.
- `ed_fload`: replaces the text (`ed_clear`: text, history, selection, view; clipboard and search pattern are kept). Line ends CR, CRLF and LF become LF, NUL bytes are dropped. If opening or the first read fails (file missing) the text stays unchanged. Return: carry clear = ok, else `A` = 1 error, 2 text too large (start loaded), 3 read error mid-file (partial text). An **empty file** is reported by the drive as a read error: it cannot be loaded.
- `ed_fsave`: writes the text unchanged (LF) as a PRG file and replaces an existing one (`@0:NAME,P,W`). In the test, replacing a PRG file made by `vcc disk` failed with type `S` and works with `P`; an existing SEQ file is unchecked.
- **Use** (display layer): Ctrl+O (`$0F`) loads, Ctrl+K (`$0B`) saves. Both open the input line `Datei: …` with the last name for editing; Return executes, STOP cancels. Afterwards the status line shows "Gespeichert", "Fehler beim Laden" or "Fehler beim Speichern" from column 20 until the next key. The key codes are provisional and unchecked on the device.
- **Test**: `tools/disptest.py files [count] [start]` emulates the drive as a D81 in Xemu, plays key scripts with load and save (CR/CRLF/LF, NUL bytes, missing files, overwriting, multiple blocks) and compares screen, core state and the files read back from the D81 image against the Python model. Status: seeds 1–8 and 10–39 identical.

## One file (no tabs, as of 2026-11-24)
- The editor works with **one** file; multiple tabs no longer exist (`src/editor/tabs.asm` was removed to save space). The text buffer is in the Attic at `$0830_0000` (768 KB of text), the history at `$083C_0000`.
- The former key assignments Ctrl+N/L/J are free. `.include`/`#include` always read from disk (project drive, system disk); the file table at `$0820_0000` stays empty.
- **Test:** `tools/disptest.py` (Python model, random sequences with file and input keys, also load/save).

## Replace and align (menu, as of 2026-11-24)
- **Replace** (menu Search > Replace, `SP_REPL`): input lines "Suche:" and "Ersatz:", then all hits **from the cursor to the end of the text** are replaced (no wrap-around, case-insensitive, `ed_repl_all`); message "n ersetzt". For each hit the core deletes the pattern with backspace and inserts the replacement like key presses, so undo works step by step.
- **Align** (menu Edit > align line / align all, `ed_fmt_line` / `ed_fmt_all`, an idea from Turbo Macro Pro): label column 0, instruction column 8, operand at 8 + max(4, instruction length + 1), comment column 32 (or one space after the operand if there is no room). Unchanged: comment lines, lines with `.` or `#` in column 0 and constants with `=`; trailing whitespace is removed; lines of 100 characters or more are left alone; quotes protect `;` inside operands.
- **Marks and label jump** (menu Search, an idea from Turbo Macro Pro): *set mark* and *go to mark* ask for a digit 1-9 (a mark is the line number of the cursor line; it does not move when lines are inserted before it), *find label* asks for a name and jumps to the line that begins with the name followed by a colon, whitespace or the end of the line (`ed_find_label`, case-insensitive, overwrites the search pattern). Tests: `tools/edtest.py` (random sequences and "label suchen feste Beispiele" against `Ed.find_label`), `tools/idetest.py` (`marke`, `marke_leer`, `label`).
- **Test:** `tools/edtest.py` (random sequences with replace and align against the Python model `Ed.fmt`/`replace_all`, fixed examples "format feste Beispiele"), `tools/idetest.py` (`ersetzen`, `ausrichten` via the menu).

## Test
`tools/edtest.py [count] [start]` compares the core in Xemu (`src/test/edtest.asm`) with a Python reference editor (text, cursor, viewport, screen, colours) on random scripts including undo/redo. Status: seeds 1–30 and 100–129 identical.
