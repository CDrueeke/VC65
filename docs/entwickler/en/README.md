<!-- SPDX-License-Identifier: MIT-0 -->
# VC65 Developer Documentation (English)

German version: [../de/README.md](../de/README.md).

| Page | Contents | Status |
|---|---|---|
| Spike N0 | Measurements and lessons from Xemu and hardware | [../spike-n0.md](../spike-n0.md) (German only, to be translated) |
| Assembler level 1 | Structure, rules taken from vcc, self-hosting, tests | [n2-assembler.md](n2-assembler.md) |
| Assembler level 2 | Variables, loops, macros, scopes, structures, text | [n4-assembler-stage2.md](n4-assembler-stage2.md) |
| Editor (N1) | Gap buffer, screen, colouring, undo/redo, test | [n1-editor.md](n1-editor.md) |
| IDE (editor + assembler) | one program, memory map, assembling from the editor, test | [n1-ide.md](n1-ide.md) |
| Debugger (N8) | BRK trap, stepping, breakpoints, disassembler, line table, overlay VC65D | [n8-debugger.md](n8-debugger.md) |
| VCASM changes | List of language changes from VintageCoder and their status in VC65 | [vcasm-aenderungen.md](vcasm-aenderungen.md) |
| Bank plan | One role per bank, memory map, addresses | planned (from concept, section 7, after the spike) |
| Hardware values | VIC-IV, DMA, Hyppo, colour RAM (`$0FF8_0000`), verified registers | planned |
| Interfaces | Bridge stub, call and return, debugger core | planned |
| Build and test | `tools/build.sh`, `tools/vcc.version`, Xemu runs, autoboot D81, hand test | planned |
| VCASM compatibility | Levels, conformance examples, list of known differences | planned |
| Hand test | Instructions for testing on a real MEGA65 | [handtest.md](handtest.md) |
