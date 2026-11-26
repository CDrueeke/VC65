<!-- SPDX-License-Identifier: MIT-0 -->
# 3 Assembler

German version: [../de/03-assembler.md](../de/03-assembler.md). Back to the [overview](README.md). Prerelease 0.1.1-Alpha.

> **Note:** The assembler is tested in the Xemu emulator (byte-for-byte comparison with `vcc`, the assembler of the VintageCoder desktop version). It is unchecked on a real MEGA65.

## Target and language

The assembler assembles for the **45GS02** of the MEGA65. It understands VCASM, the language of VintageCoder, and is meant to give the same result as `vcc` for sources that concern only the MEGA65.

- The only target is `mega65`. The line `.target mega65` is **optional** and accepted. Any other target reports error **E207**. Sources from VintageCoder with `.target mega65` run unchanged.
- There is no C64 target.
- The assembler works in several passes. On an error it does not stop: it notes the error, skips the rest of the line and continues. The error list belongs to the last pass.

## What is supported

| Area | Scope |
|---|---|
| Variables | `.var`, `.set`, `name = …`, `name op= …` (`+ - * / % & \| ^ << >>`); the value applies from the line in which it is set |
| Repetition | `.repeat n [, var]`, `.for i = a, condition, step`, `.for i in range(…)`, `.for c in [list]`, `.next`, `.break`, `.continue` |
| Macros | `.macro`/`.endmacro`, parameters (also with defaults `p=value`), call with and without parentheses, call before the definition, `@label` unique per call, `.exitmacro`, nesting up to 64 frames |
| Scopes | `{ }` (named by the label on the line, otherwise anonymous), `.namespace name {`; `scope.name` from outside; local labels per scope |
| Further directives | `.segment "NAME"[, from, to]` (names a segment and checks the range, E301), `.bank` (bank 0 only), `.page [n]`, `.pseudopc`/`.endpseudopc`/`.realpc`, `.fill`, `.lohifill`, `.struct`, `.enum`, `.rta`, `.basicstub target, line, "text"`, `.assert`, `.error`, `.warning`, aliases `.db .dw .dbyt .long`, `//` comments |
| Canonical names | among others `.relocate/.endrelocate`, `.retaddr`, `.lohitable`, `.screencode`, `.textnull/.textlen/.textshift`, `.addr`, `.endfor`, `.scope/.endscope`, `.align n, fillbyte\|skip` |
| Functions | built in: `abs sign min max int floor ceil round next align pow sqrt sin cos tan asin acos atan atan2 exp log log2 log10 len range`; your own: `.function name(a, b) = expression` (one expression, up to 16 levels deep, no recursion) |
| Fractional numbers | `2.5`, `1e3`, `1.5e-2`, `pi`; arithmetic, comparisons, `&& \|\| !`; where an integer is needed, the value is truncated toward zero |
| Lists | `[a, b, c]`, `t[i]`, `t[-1]`, `t[a:b]`, `t[:n]`, `t[n:]`, `list + list`, `list * n`, `len`, `range`; `.byte`/`.word`/`.dword` output lists flattened; `.var t = []` with `t += [..]` |
| Text | `{name}`, `{$hh}`, `{nnn}`, `{name*n}`, `{{` in strings; `.encoding "name" { … }` |
| Labels | local and anonymous labels (`jmp ++`, `bne --`) |

Also: includes and system libraries (see below) and the 45GS02 instructions including the Q-register instructions (for example `ldq`, `aslq q`, `lsrq q`).

## Includes and system libraries

- `.include "file"` and `#include` always read from the **disk**: files of the user from the **project drive**, libraries from the **system disk**.
- Libraries such as `<mega65/vic4.asm>` are on the system disk as flat names `ORD.NAME` (see [chapter 1](01-getting-started.md#names-of-the-system-libraries)).
- Paths that lead beyond the project root (`../../common/…`) are simplified to `common/…`.
- From the 17th file in a project on, the files share one name slot; only the assignment of an error to its file suffers.
- Errors in an include file show `in file n` instead of the column; the cursor then does not jump.

### Chip symbols

The chip symbols of the MEGA65 (for example `vic2.border`) are in the file `MEG.CHIPS` on the system disk. The assembler includes it itself on every pass. If the file is missing, there are only no chip symbols.

## E300: code before the first `.org`

Like `vcc`, VC65 reports error **E300** when a byte is output or a label is defined before the first `.org` (or `*=`). Constants, macro definitions and an `.align` without effect stay allowed.

## Limits

- **Non-ASCII characters (UTF-8, umlauts):** In comments and in strings for `.text`, `.petscii` and `.byte` VC65 assembles like `vcc` (byte-identical). **Differences from `vcc`:** labels, constants and character literals (`'ü'`) with non-ASCII characters are reported as errors by VC65 (E205 or E201), `vcc` accepts them; `.screencode` with non-ASCII characters gives a different code (for example `$C3` instead of `$43` for the first byte of ü). Recommendation: umlauts only in comments and in strings for `.text`, `.petscii` and `.byte`; identifiers and `.screencode` with ASCII only. The editor shows every byte above 127 as a dot (a ü as two dots); the bytes are saved unchanged.
- **Macros:** at most **16 parameters** per macro (a VC65 limit; `vcc` has none). More parameters report **E900**. A call with more arguments than the macro has parameters reports E209 as in `vcc`.
- **Fractional numbers are 32.32 fixed point**, not IEEE double as in `vcc`: resolution 2.3·10⁻¹⁰, integer part 32 bits. Angle, logarithm and root functions give the same result apart from rounding errors around 10⁻⁸; results that are integral to within about 2⁻²² are set to the whole number. Borderline cases may differ.
- **Integers are 32 bits** (`vcc`: 64 bits).
- A list of more than about 900 elements overflows the list memory (8 KB, error E211). `x += [..]` copies the list each time.
- `.run` is read but has no effect (W206). `.atascii` and `.cartridge` do not exist (E208), nor do system files of other targets; `.bank` knows only bank 0 (any other bank: E901).
- `.fill` and `.lohifill` evaluate the expression per element; this is slower for very large tables.
- Nesting depth: 64 frames, 7 scopes, names up to 31 characters including the scope path (otherwise E211).
- Struct fields of a structure type with a count greater than 1 create the subfields only for the first element (like `vcc`).
- A missing macro argument without a default reports E209.
- `.assert` and `.error` report E207 only in the last, stable pass.
- Breakpoints in macro bodies and include files are not possible (see [chapter 5](05-debugger.md)).
- Compared with `vcc` over about 500 source snippets of the VCASM help, about 98.7 % agree and the warnings are identical. The rest are edge cases, mostly follow-up errors, and deliberate exceptions (`.atascii`, `.cartridge`, system files of other targets).

Speed: a self-assembly (8477 lines, 4 passes) took 5.8 s in Xemu at 40 MHz, about 0.7 s per 1000 lines over all passes. Speed on a real MEGA65 is unchecked.
