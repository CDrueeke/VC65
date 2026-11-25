<!-- SPDX-License-Identifier: MIT-0 -->
# 12 Glossary

German version: [../de/12-glossar.md](../de/12-glossar.md). Back to the [overview](README.md). Prerelease 0.1.0-Alpha.

Terms used in the manual, in alphabetical order.

| Term | Explanation |
|---|---|
| **45GS02** | The CPU of the MEGA65. It understands the instruction set of the 6502 and the 65CE02 and brings additional registers (Z, B, Q). |
| **Alpha** | Stage of development: the program certainly still contains errors and has not been fully checked. |
| **Anonymous label** | A label without a name: `-` and `+` (also `--`, `++`). `bne -` branches back to the nearest `-` label, `beq +` forward to the nearest `+` label. |
| **Assembler** | A program that translates source text made of instruction names (mnemonics) into machine code. In VC65 with **Ctrl+E**. |
| **B register** | Base page register of the 45GS02. When programs start it is 0; change it only deliberately. |
| **Bank** | A memory area of 64 KB. VC65 runs in bank 4; your test program runs in bank 0. |
| **BASIC stub** | A BASIC line `10 SYS <address>` at the start of a program, created with `.basicstub`, so that the program starts with `RUN`. |
| **Boot D81** | The disk with VC65, the debugger, the tools and the system files (drive 8). |
| **Breakpoint** | A place in the program where the debugger stops (**Ctrl+G**). |
| **Chip symbols** | Names for the chip registers of the MEGA65, for example `vic2.border` for `$D020`. They are in `MEG.CHIPS`. |
| **CHROUT** | KERNAL routine at `$FFD2`: prints a character. |
| **D81** | Image of a 3.5-inch disk of the MEGA65 (800 KB). |
| **Debugger** | Tool for running a program step by step, showing registers, memory and source line (**Ctrl+D**). |
| **Directive** | A command to the assembler that does not produce a machine instruction: `.org`, `.byte`, `.if` etc. It begins with a dot. |
| **DMA** | Direct Memory Access: the MEGA65 can copy or fill memory without the CPU (DMAgic). |
| **E/W code** | Identifier of an assembler message: `E…` error, `W…` warning ([chapter 11](11-error-codes.md)). |
| **Emergency key** | The **RESTORE key**: interrupts a running program and returns to the IDE. |
| **Emulator (Xemu)** | A program that imitates a MEGA65. VC65 has so far been tested only there. |
| **Hex** | Hexadecimal numbers with `$`, for example `$D020`. |
| **Include** | Including another file: `.include "file"` (project drive) or `#include <path>` (system library). |
| **KERNAL** | The operating system in the ROM of the MEGA65 with fixed entry addresses (`CHROUT`, `GETIN`, …). |
| **Label** | A name for an address in the source text, for example `loop:`. |
| **Macro** | A named text block that the assembler inserts at each call (`.macro` … `.endmacro`). |
| **Mnemonic** | Short name of a machine instruction, for example `lda`, `sta`, `jsr`. |
| **Overlay** | A part of the program that is loaded from the disk into a fixed memory area when needed (`VC65D`, `VC65X`, `VC65T`). |
| **PRG** | File format with two bytes of load address followed by the program. |
| **Problems bar** | Lines below the text with the messages of the last assembly. |
| **Project drive** | The drive (8 or 9) from which source texts are loaded and to which they are saved (**Ctrl+A**). |
| **Q register** | 32-bit register of the 45GS02 made of Z, Y, X and A; used with the Q instructions (`ldq`, `stq`, `inq`, …). |
| **Scope** | A namespace in `{ … }`; labels in it can be reached from outside only with the scope name. |
| **Segment** | A contiguous block of the output starting at an address (`.org`, `.segment`). |
| **SID** | The sound chip of the C64. The MEGA65 has four of them. |
| **Status line** | Line at the bottom of the editor with messages and the cursor position (`L nnnn C nnnn`). |
| **System disk** | The boot D81 in drive 8, from which VC65 reads libraries and overlays. |
| **System library** | Ready-made include files with constants and macros for the MEGA65 (`<mega65/…>`). |
| **VCASM** | The assembly language of VintageCoder; VC65 understands it for the MEGA65. The language is free to use. |
| **vcc** | The assembler of VintageCoder on the command line; for MEGA65 source texts VC65 gives the same result. |
| **VIC-IV** | The graphics chip of the MEGA65 with palettes of 256 colours each, full-colour characters and further modes. |
| **Z register** | Additional index register of the 45GS02. With `sta [$40],z` a 32-bit pointer is used. |
| **Zero page** | The first 256 bytes of memory (`$00` to `$FF`) with particularly fast access. |
