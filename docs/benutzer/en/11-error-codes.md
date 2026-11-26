<!-- SPDX-License-Identifier: MIT-0 -->
# 11 Error and warning codes

German version: [../de/11-fehlercodes.md](../de/11-fehlercodes.md). Back to the [overview](README.md). Prerelease 0.1.1-Alpha.

The assembler of VC65 reports errors as `Ennn` and warnings as `Wnnn`, each with line and column. **Errors** abort the build (the output is then not usable), **warnings** do not. The codes are the same as in `vcc`, the assembler of VintageCoder; VC65 adds its own codes for its limits (range 9xx). Errors appear red in the problems bar, warnings yellow; the status line names the first error (for example `E205 line 9 col 13`).

> **Note:** The texts of the messages in the program are English; the description here is the explanation. Everything is tested only in the Xemu emulator.

## Errors

| Code | Meaning | Typical cause |
|---|---|---|
| **E201** | undocumented opcode not allowed, or the instruction does not exist on this CPU | instruction of another CPU, `illegals = deny` |
| **E202** | error in an expression | unknown symbol, missing parenthesis, division by 0, wrong number of arguments for a function, list instead of number |
| **E203** | value out of range | `lda #256`, `.org` outside 0 to 65535, branch too far, negative count in `.fill`, `.page 0`, range error in `.lohifill` and `.lohitable` |
| **E204** | name defined twice | two identical labels, constant with a new value, duplicate `.struct`, label in `.repeat` without a scope, function with the name of a built-in function |
| **E205** | unknown instruction | typing mistake, label without a colon, macro not defined |
| **E206** | operand does not fit the instruction | `lda` without an operand, `sta #1`, addressing mode not available |
| **E207** | `.assert` failed, `.error` reached, or a target other than `mega65` | own checks, `.target c64` |
| **E208** | wrong notation of a directive | missing quotation marks, invalid name, unknown directive, text directive with anything other than strings, `.lohifill` without an expression, unknown special character `{…}` |
| **E209** | macro: wrong number of arguments or name like an instruction | `m 1, 2` for one parameter, macro named like an instruction |
| **E210** | block structure faulty | `.if` without `.endif`, `.macro` without `.endmacro`, `.break` outside a loop, default value before a required parameter |
| **E211** | nested too deeply, or limit exceeded | macro calls itself, include cycle, list or name too large |
| **E212** | file not found | wrong name in `.include`, `.incbin`, `.encoding` |
| **E213** | scope error | `}` without `{`, scope not closed, dot in the scope name |
| **E214** | anonymous label missing | `bne -` without a `-` before it, `beq +` without a `+` after it |
| **E215** | address mode suffix does not fit | `jmp.z`, `lda.z #1` |
| **E216** | `.set` on something that is not a variable | `.set` on a constant |
| **E217** | loop runs too long | `.for` with more than 65536 passes |
| **E218** | `.basicstub` not at the start of the program | bytes before `.basicstub` |
| **E300** | code or label before the first `.org`; symbols do not converge | `nop` in the first line; a condition depends on an address of its own |
| **E301** | segment overlaps or leaves its range | two `.org` with overlapping content, `.segment` with too small a range, program counter runs past `$FFFF` |
| **E900** | VC65 limit: macro with more than 16 parameters | `vcc` has no such limit |
| **E901** | VC65 limit: `.bank` with a bank other than 0 | VC65 outputs only the 16-bit address space of bank 0 |

## Warnings

| Code | Meaning | Typical cause |
|---|---|---|
| **W104** | undocumented opcode (with `illegals = warn`) | `lax $d020` |
| **W105** | unstable undocumented opcode | `xaa` |
| **W200** | `.warning` reached | own message |
| **W201** | cycle budget exceeded | `.cycles … max=n` |
| **W202** | floating-point number was truncated | `.byte 7 / 2.0` |
| **W203** | branch too far, extended automatically | `.branchlong auto` |
| **W204** | `.basicstub` not at the BASIC start address of the target system | `.org` at an address other than `$2001` |
| **W206** | directive is read but has no effect | `.run` (no effect on the MEGA65) |

## How VC65 handles errors

- The assembler works in several passes. On an error it remembers the message, skips the rest of the line and keeps assembling. The error list belongs to the last pass.
- The problems bar shows up to three entries; lines with errors are coloured red (at most 16 lines).
- Errors in an include file show `in file n` instead of the column; the cursor does not jump then.

## Further notes

- If something fails differently from what is described here, compare with the behaviour of `vcc`: for source texts that concern only the MEGA65, VC65 is meant to give the same result. Known differences are in the developer documentation (`docs/entwickler/de/vcasm-konformitaet-luecken.md`).
- The BASIC translation of VintageCoder has its own error numbers from E301; it is not part of VC65.
