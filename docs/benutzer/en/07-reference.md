<!-- SPDX-License-Identifier: MIT-0 -->
# 7 Reference

German version: [../de/07-referenz.md](../de/07-referenz.md). Back to the [overview](README.md). Prerelease 0.1.0-Alpha.

> **Note:** All key codes are provisional and unchecked on a real MEGA65; the HELP key (`$84`), ESC, the function keys (VC65 switches off the KERNAL function-key assignment at start) and the menu are tested only in the Xemu emulator.

## Keys in the editor

| Key | Key code | Effect |
|---|---|---|
| STOP | `$03` | end VC65 (in input lines and in the menu: cancel) |
| F1 | `$85` | find (input line) |
| F2 | `$89` | find next |
| F3 | `$86` | go to line (input line) |
| F4 | `$8A` | find backwards |
| F5 | `$87` | mark |
| F6 | `$8B` | copy |
| F7 | `$88` | cut |
| F8 | `$8C` | paste |
| Ctrl+P | `$10` | undo |
| Ctrl+U | `$15` | redo |
| Ctrl+V | `$16` | page up |
| Ctrl+W | `$17` | page down |
| CLR | `$93` | end of line |
| Shift+DEL | `$94` | delete the character under the cursor |
| Ctrl+O | `$0F` | load file |
| Ctrl+K | `$0B` | save file |
| Ctrl+E | `$05` | assemble |
| Ctrl+F | `$06` | save program (PRG) |
| Ctrl+R | `$12` | run program |
| Ctrl+D | `$04` | run program in the debugger |
| Ctrl+G | `$07` | toggle breakpoint on the cursor line |
| Ctrl+A | `$01` | project drive 8 / 9 |
| ESC, HELP | `$1B`, `$84` | open the menu (ESC also closes it) |
| Return, Tab, DEL, cursor keys, Home, printable characters | – | as in chapter 2 |
| RESTORE | – | emergency key (NMI) |

The key codes in the "Key code" column are the values the KERNAL delivers (PETSCII); a Ctrl+letter has the code of the letter minus `$40`.

## Keys in the debugger

| Key | Effect |
|---|---|
| F1 or `s` | single step |
| F3 or `n` | step over (`JSR` runs through) |
| F5 or `c` | continue to the next breakpoint |
| V (or Ctrl+P, `$10`) | program screen until the next key |
| Arrow down / up | scroll memory by 32 bytes |
| F7, `q` or STOP | end the session |

## Keys in the menu

| Key | Effect |
|---|---|
| Left / right | change field |
| Up / down | select entry |
| Return | run entry |
| STOP, ESC or HELP | close the menu |

## Menu

The command bar shows `VC65  File  Edit  Search  Build  Debug    ESC or HELP: Menu`.

| Field | Entry | Key |
|---|---|---|
| File | Load | Ctrl+O |
| | Save | Ctrl+K |
| | Save program | Ctrl+F |
| | Drive | Ctrl+A |
| | About VC65 | |
| | Quit | STOP |
| Edit | Undo | Ctrl+P |
| | Redo | Ctrl+U |
| | Mark | F5 |
| | Copy | F6 |
| | Cut | F7 |
| | Paste | F8 |
| | Align line | menu only |
| | Align all | menu only |
| | Hex calculator | menu only |
| | Insert data | menu only |
| Search | Find | F1 |
| | Find next | F2 |
| | Find previous | F4 |
| | Go to line | F3 |
| | Replace | menu only |
| | Find label | menu only |
| | Set mark | menu only |
| | Go to mark | menu only |
| Build | Assemble | Ctrl+E |
| | Run | Ctrl+R |
| Debug | Debugger | Ctrl+D |
| | Breakpoint | Ctrl+G |

## Status line messages

The cursor position `L nnnn C nnnn` (L = line, C = column) is shown at the right of the status line.

| Message | Meaning |
|---|---|
| OK n bytes | assembly succeeded, output n bytes |
| Ennn line z col s | first error of the assembly; for include files `in file n` instead of the column |
| Assemble first | no current output available (Ctrl+F, Ctrl+R, Ctrl+G) |
| Program saved | Ctrl+F succeeded |
| Error saving | saving failed |
| Error loading | loading failed |
| Saved | Ctrl+K succeeded |
| Program ended | the program returned with `RTS` |
| Program interrupted (emergency key) | interrupted with RESTORE |
| Load address below $2000 | the program cannot be started |
| File VC65D missing | the debugger cannot be loaded |
| File VC65X missing | the tools overlay (align, hex calculator, insert data) cannot be loaded |
| No output here | breakpoint on a line without output |
| Breakpoint set / removed | breakpoint set / removed (Ctrl+G) |
| Too many breakpoints | breakpoint limit reached |
| Project drive n | Ctrl+A |
| n replaced | replace: number of replacements |
| Mark set / Mark not set | marks |
| Label not found | find label without a hit |
| No problems | problems bar without entries |

## Error and warning codes

The assembler reports errors as `Ennn` and warnings as `Wnnn`, each with line and column; errors are red in the problems bar, warnings yellow. All codes with their meaning and typical cause are in [chapter 11](11-error-codes.md).
