<!-- SPDX-License-Identifier: MIT-0 -->
# 10 Troubleshooting and frequently asked questions

German version: [../de/10-fehlersuche.md](../de/10-fehlersuche.md). Back to the [overview](README.md). Prerelease 0.1.1-Alpha.

This chapter collects problems that can occur when working with VC65, with cause and remedy. The messages of the program are in English and appear here in code format. Everything is tested only in the Xemu emulator.

## Start and disks

**VC65 does not start, BASIC reports an error at `DLOAD"VC65"`.**
The boot D81 is not attached in drive 8, or the image is damaged. Check the checksum with `SHA256SUMS` (Linux: `sha256sum -c`, macOS: `shasum -a 256 -c`).

**The message `File VC65D missing` or `File VC65X missing` appears.**
The overlay files `VC65D` (debugger) and `VC65X` (align, hex calculator, insert data, message boxes) must be on the system disk in drive 8. They are loaded when needed; without them these tools are not available. Check that the boot D81 is in drive 8 and has not been swapped for another disk.

**Loading a file reports `Error loading`.**
The name is wrong, the file is not on the project drive, or the file is empty. An **empty file** cannot be loaded (the drive reports it as a read error). Use **Ctrl+A** to check which drive is currently the project drive (on the right in the file line).

**`Error saving` when saving.**
Check whether the disk is full or write-protected and whether the name has at most 16 characters. Names must not contain folders.

## Keyboard

**The underscore `_` cannot be typed.**
On some keyboards (for example a Mac keyboard in the emulator), `_` is not passed on to the MEGA65. Use letters and digits in your own names (this is also why the examples are called `paldemo.asm` and `musicdemo.asm`).

**Ctrl+letter does nothing.**
The emulator or the operating system of your computer may intercept a key combination before it reaches the MEGA65. In that case use the menu (**ESC** or **HELP**), which offers the same commands.

## Assembling

**`E205` (unknown instruction).**
Usually a typing mistake in the mnemonic, a label without a colon at the start of the line, or an undefined macro. The cursor jumps to the error line.

**`E202` (error in an expression).**
An unknown symbol (label misspelled or not yet defined, include missing), a missing parenthesis, division by 0 or a wrong number of arguments for a function.

**`E300` (code or label before the first `.org`).**
A byte was emitted or a label defined before the first `.org` or `*=`. Put `.org` at the beginning, before the first label and the first instruction. Constants, macro definitions and `#include` before it are allowed.

**`E207` with `.target`.**
VC65 assembles only for the MEGA65. Remove the line or write `.target mega65`.

**Errors are in an include file: `in file n` instead of the column, and the cursor does not jump.**
The error is in the file that is included with `.include` or `#include`. Load that file and assemble it there to see the line.

**The message `Assemble first` appears at Ctrl+F, Ctrl+R or Ctrl+G.**
There is no current output: you changed the text since the last assembly or never assembled. Press Ctrl+E first.

**A program for another computer (C64, Atari, …) cannot be assembled.**
VC65 is a pure MEGA65 assembler. System files of other targets (for example `<c64/kernal.asm>`) are not on the system disk, and the directives `.atascii` and `.cartridge` do not exist.

## Running

**`Load address below $2000`.**
The program lies below `$2000` and would overwrite the IDE; VC65 does not start it. Place the program at an address from `$2000` on with `.org $2001` (with `.basicstub`) or `.org $2000`.

**The program starts, the screen hangs.**
A program that never returns stays where it is. With the **RESTORE key** you return to the IDE (`Program interrupted (emergency key)`). This does not apply to programs that destroy the stack or zero page or have their own IRQ/NMI operation.

**The text of my program is gone immediately after the end.**
If a program returns with `RTS`, VC65 switches back to the 50-line screen at once. Make the program wait for a key (see [chapter 8](08-first-program.md)).

**There is no sound.**
The emulator needs an audio output device. In a remote session without audio (for example RDP without sound forwarding) nothing can be heard.

## Debugger

**`Assemble first` at Ctrl+G (breakpoint).**
Breakpoints need the line table of the last assembly. Assemble with Ctrl+E first.

**`No output here`.**
The line produces no output (comment, blank line, directive without bytes). Put the breakpoint on an instruction line.

**`Too many breakpoints`.**
The number of breakpoints is limited; remove ones you do not need with Ctrl+G.

**The debugger shows `(no line info)`.**
The program counter is in an area without line information (for example ROM, macro or include file). Breakpoints in macro bodies and include files are not possible.

## Limits and alpha stage

- VC65 is an **alpha program**. It certainly still contains errors and is tested only in the Xemu emulator, **not on a real MEGA65**.
- The program is **English**; the manual exists in German and English.
- The key assignment is provisional and may change.
- Errors and wishes: see `README.md` and `SECURITY.md` in the package.
