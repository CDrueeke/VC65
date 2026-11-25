<!-- SPDX-License-Identifier: MIT-0 -->
# Stage N2: Assembler level 1 (status and structure)

German version: [../de/n2-assembler.md](../de/n2-assembler.md). Goal (concept, sections 6, 9, 16): a VCASM-compatible assembler for the 45GS02, level 1 (all instructions and addressing modes, labels, expressions, core directives, multiple passes, error list), producing the same bytes as `vcc`.

## Modules (all in `src/asm/`, written in VCASM, run on the MEGA65)

| File | Contents | Status |
|---|---|---|
| `zp.asm` | Zero-page allocation (each cell once), error codes | done |
| `src.asm` | Reading source text via a 32-bit pointer (`[SRC],z`), skipping blanks | done |
| `optab.asm` | Opcode table, **generated** by `tools/gen_optab.py` from `vendor/vintagecoder/data/cpus/45gs02.cpu.json` | done (145 mnemonics) |
| `mnfind.asm` | Mnemonic search (binary search); `NOP` maps to `EOM` (as in `vcc`) | done, tested |
| `sym.asm` | Identifiers, symbol table (hash, Attic from `$0810_0000`), local names (`.name` → `global.name`) | done |
| `expr.asm` | Expressions, signed 32 bit, precedence as in `vcc`; numbers `$`/`0x`/`%`/decimal/`'c'`, `*` | done, 74 cases |
| `enc.asm` | Reading operands, choosing the addressing mode (zero page/absolute/relative, quad, 32-bit pointer), long branches | done |
| `asm.asm` | Driver (passes until symbols are stable, at most 16), lines, labels (global, local, anonymous `-`/`+`), directives | subset, see below |
| `stage2.asm`, `dir2.asm`, `text2.asm`, `func.asm`, `charnames.asm` | Level 2: variables, loops, macros, scopes, more directives, special characters in text | see [n4-assembler-stage2.md](n4-assembler-stage2.md) |

Supported directives: `.org` / `*=` (gaps in raw output filled with 0), `.byte`, `.word`, `.dword`, `.be16`, `.be32`, `.rta`, `.hex`, `.fill`, `.align`, `.text`, `.petscii`, `.screen`, `.null`, `.ptext`, `.shift`, `.encoding`, `.const`/`.equ` and `name = expression`, `.basicstub`, `.branchlong auto`, `.target mega65`, `.cpu …`; suffixes `.z` and `.a` on instructions.

Still open for level 1: Attic instead of bank 5.

Level 2 (stage N4) is largely built: see [n4-assembler-stage2.md](n4-assembler-stage2.md). Still open: folders and long names of the SD card (Hyppo, N6) (currently without effect) and file access.

## Encoding rules taken from `vcc` (read only)

- Quad instructions (`LDQ` … `NEGQ`) use the opcodes of their base instruction with prefix `$42 $42`; only modes imp, acc, zp, zpx, abs, abx and izz are allowed, otherwise `E206`.
- 32-bit pointers `[zp]` and `[zp],z` put the prefix `$EA` before the izz form (after the quad prefix).
- Plain operands choose zero page if the value is **known** and 0…255, otherwise absolute. A symbol defined later counts as unknown in the first pass (large form); in the next pass its now-known value counts. Hence the source is assembled until no symbol value changes any more.
- Relative branches: offset = target − (instruction address + prefix length + 2); `BBR`/`BBS`: target − (… + 3). With `.branchlong auto` a branch that is too far becomes the long form (`LBNE` …); once long, always long.
- A `.name` without a following colon is a directive, with a colon a local label.

## Self-hosting (milestone 2026-11-23)

The native assembler assembles **its own source** (test program plus all modules from `src/asm`; at the milestone 3801 lines and 8598 bytes, with level 2 now 7555 lines and 18024 bytes, merged into one file by `tools/flatten.py`, placed in the Attic at `$0800_0000`) in Xemu and produces the same bytes as `vcc` (`tools/selfhost.py`). This required reproducing the pass logic of `vcc` exactly:

- When an expression looks up a symbol, the value of the **previous** pass counts (`syms`); definitions go into the table of the **current** pass (`new_syms`). So in the first pass **every** symbol is unknown, even one defined further up. This decides which branches become long (once long, always long). Exceptions: a backward `-` uses the new value; `.ifdef`/`.ifndef` only count symbols already defined in the current pass.
- Each symbol entry therefore carries the old and the new value and two flags. At the end of each pass new becomes old; if a value or the set of symbols changed, another pass follows (at most 16).
- Value errors (`E202`, `E203`, branch range) are "soft": the pass continues, only an error in the last, stable pass counts (like `strict` in `vcc`). Syntax errors stop immediately.

## Error list (`err.asm`)

On an error the assembler no longer stops: it records code and position, skips the rest of the line and keeps assembling (up to 100 errors). The list belongs to the **last, stable pass** (it is cleared at the start of every pass), just as `vcc` reports only the errors of the last pass. Entry in bank 4 from `$6000`: code (1 byte), 3 unused, source position (32 bit); `ERR`/`SRC` point to the first error. `err_linecol` (entry number in A) returns line and column from 1. Errors in a macro call are attributed to the calling line. After an error `al_recover` resets the stack and continues behind the line; only "block not closed" at the end of the source (`E210`/`E213`) aborts. New codes: `E204` (symbol defined twice with a different value), `E214` (no matching `-`/`+`), `E215` (`.z`/`.a` impossible), `E218` (`.basicstub` not at the start), `E208` for an unknown `.encoding`. `tools/errtest.py` compares code and line of all errors with `vcc` (own cases and all `asm fehler` examples of the help: 20 of 20 equal).

Lesson: the long-branch table now lives in the Attic (`$0812_0000`); for large programs (output over 28 KB) the output overwrote it in bank 5 and produced wrong long branches.

## Include (`inc.asm`)

`.include "file"`, `.include "file" as name`, `#include "file"` (once per file and namespace, like `#pragma once`), `#include <path>` (system library: looks for `sys/path`) and `.incbin "file" [, offset [, length]]`. The assembler does not access the SD card itself but queries a **file table in the Attic** (`$0820_0000`) supplied by the caller: in tests the tool `tools/asmtest.py` (`one_inc`), later in the environment the file loader (stage N6, Hyppo access). Entry: name length (1), name (path with `/`, relative to the main program), length (4 bytes, low first), contents, a 0 byte; end of table: name length 0. The search goes first to the folder of the including file (`..` and `.` are resolved), then unchanged. Not found: `E212`.

An included file is, like a macro call, a frame on the source stack (`FT_INC`): `SRC` points into the file contents, at its end reading continues behind the `.include` line; `as name` opens a scope for it. The pre-scan for macros follows the `.include` lines (up to 6 levels), so macros from include files can be called even before the `.include`. Every error entry carries the file number (up to 16 files); `err_linecol` counts line and column from the start of that file. `tools/inctest.py` compares with `vcc` (9 cases: paths, `as`, `#include` once, `.incbin`, macros, errors in include files). Difference: `vcc` also reports a missing file inside a `.if` that does not apply; the native assembler does not.

The base page of the tests is now at `$0200` (interrupts disabled) because the code grows beyond `$9F00`; test sources always live in the Attic.

## Counting cycles (`cyc.asm`) and warning list

`.cycles [name] [max=budget]` … `.endcycles` counts, like `vcc`, the cycles of all instructions **assembled** in between (each as often as it is assembled; no program flow, jumps are not followed). **min** is the sum of the base cycles, **max** the worst case (conditional branch taken +2). The numbers per opcode are in the tables `cyc_base`/`cyc_worst` at the end of `optab.asm` (generated by `tools/gen_optab.py` from `45gs02.cpu.json`); `encode` calls `cyc_add`. Blocks may be nested (8 levels). Each block yields a report (`cyrep`, up to 16: min, max, budget, name length). If max exceeds the budget there is the warning `W201`; `.endcycles` without `.cycles` and an unclosed block are `E210` (the open block is reported at its `.cycles` line).

For this there is now a **warning list** next to the error list (`WLIST`, bank 4 `$6400`, counter `wcnt`, `warn_add`), built the same way and also cleared every pass; warnings do not change the outcome. `tools/cyctest.py` compares reports (min, max, budget) and `W201` lines with `vcc` (8 cases, including quad instructions, long branches, `.if`, `.repeat`, nesting).

The output of the tests now starts at `$0005_0000` (64 KB) because self-hosting outputs more than 32 KB.

## File loader (`loader.asm`, stage N6 first step)

If a file is missing from the file table, the loader fetches it through the **KERNAL file routines** from device `lddev` (default 8: SD card or mounted D81) and appends it to the table when `ldon` is non-zero (the environment sets it). After that everything works as for a preloaded file (`fs_resolve` searches again). Sequence: name = last part of the path in upper case; `SETNAM`/`SETLFS`/`OPEN` on channel 2; reading with `CHRIN` into a 256-byte buffer, `READST` after every byte: bit 6 = last byte, other bits (file not found reports `$42`, device missing `$80`) = error; each buffer is copied into the Attic behind the table header; finally header (name length, full resolved name, length), the 0 byte and the end of the table are written. For the KERNAL calls the loader switches the base page `B` to 0 and back afterwards (the assembler keeps its zero page elsewhere).

Limits: only file names without folders and at most 32 characters; subfolders and long names of the SD card follow with direct Hyppo access (spike N0, part 2, on a real MEGA65). The error channel is not read: a `CLOSE 15` closes all files of the device. `tools/inctest.py` runs every case additionally with `asmtest.one_disk`: the include files lie on a D81 built with `vcc disk d81` in drive 8 (Xemu `-8`), including files over 256 bytes and exactly 512 bytes; 15 cases equal to `vcc` in both modes.

## Memory

Bank plan (concept section 7): code and tables later in bank 4, working data in bank 5, source text, output and symbols in the Attic. For now (tests) source text and code are in bank 0, output at `$0005_0000` and symbols at `$0810_0000` in the Attic, the long-branch table at `$0812_0000` in the Attic; all accesses already use 32-bit pointers, so moving to the Attic only changes base addresses.

**Important (45GS02):** there is no `LDA zp,Y`; the assembler turns it into `abs,Y`, which then reads the **real** zero page, not the base page `B`. The tests set `B` to `$0200`; always index zero-page tables with `X` or via `(zp),Y`.

## Testing

| Tool | Purpose |
|---|---|
| `tools/xrun.sh x.prg` | Run a PRG headless in Xemu (Mac), save screen and 384 KB of main memory |
| `tools/asmtest.py [name …]` | Differential test: assemble each `tests/asm/*.asm` with `vcc` (raw bytes) and with the native assembler in Xemu, compare bytes (currently **30 of 30**) |
| `tools/conform.py` | Conformance report over the example blocks of the VCASM help (`vendor/vintagecoder/help/`): identical to `vcc` (currently **61 of 67**; the rest needs floating-point numbers, lists, functions, `.cycles`, `.include` or is Atari specific) |
| `tools/fuzzenc.py` | Encoding test over all mnemonics and addressing modes of the 45GS02 (396 lines accepted by `vcc` must be byte-identical; the 34 rejected ones must also give `E206`) |
| `tools/inctest.py` | Include: paths, `as`, `#include`, `.incbin`, macros, errors in include files against `vcc` |
| `tools/cyctest.py` | `.cycles`: reports and W201 against `vcc` |
| `tools/errtest.py` | Error list: code and line of all errors against `vcc` |
| `src/test/expr_test.asm` | Expression evaluator, 74 cases (`tools/gen_exprtests.py`) |
| `src/test/mnfind_test.asm` | Mnemonic search |

All runs so far only in Xemu; not checked on a real MEGA65.
