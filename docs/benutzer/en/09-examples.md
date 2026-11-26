<!-- SPDX-License-Identifier: MIT-0 -->
# 9 The example programs

German version: [../de/09-beispiele.md](../de/09-beispiele.md). Back to the [overview](README.md). Prerelease 0.1.1-Alpha.

The examples D81 (`VC65-Beispiele-0.1.1-alpha.d81`) contains four MEGA65 programs from VintageCoder as source text. They are under the MIT-0 license: you may use, change and pass them on without conditions. Each main file begins with a detailed header comment (what the program shows, operation, hardware, memory). Read it first.

> **Note:** Assembling in VC65 gives the same bytes as `vcc`; running is checked only in the Xemu emulator, not on a real MEGA65.

## How to load an example

1. Attach the examples D81 as **drive 9**.
2. In VC65, press **Ctrl+A** (`Project drive 9`).
3. **Ctrl+O**, type the name of the main file (for example `hello.asm`), Return.
4. **Ctrl+E** assembles, **Ctrl+R** runs.
5. End programs that do not return (endless loop) with the **RESTORE key**.

There are no folders on the disk, so all files have unique names. The underscore `_` cannot be typed on some keyboards in the emulator; that is why the main files are called `paldemo.asm` and `musicdemo.asm`.

## hello.asm: the smallest program

| | |
|---|---|
| Size | 63 bytes |
| Shows | red border, unlocking the VIC-IV, 32-bit pointer, Q instructions |
| Start | BASIC line (`.basicstub`), from the IDE with Ctrl+R |

The program unlocks the **VIC-IV** (first `$47`, then `$53` to `$D02F`; without this step the extended registers from `$D030` are not reachable) and turns the border red (`vic2.border`, colour 2). Then it writes a byte through a **32-bit pointer** (`sta [$40],z`) into the chip RAM of bank 1 (`$0001_0000`), which the CPU cannot reach with 16-bit addresses, and increments the pointer as a whole 32-bit word with the **Q instructions** `ldq`, `inq`, `stq`. At the end is an endless loop: you get back into the IDE with RESTORE.

Good for learning: the special features of the 45GS02 (Z register, 32-bit pointer, Q register) in a few lines.

## paldemo.asm: a 256-colour palette

| | |
|---|---|
| Files | `paldemo.asm` (main file), `vic4.inc`, `pal65.asm` |
| Size | 867 bytes, load address `$2000` (no BASIC starter) |
| Shows | the palette of the VIC-IV: four banks of 256 colours each with 8 bits of red, green and blue |

Instead of the 16 fixed colours of the C64, the VIC-IV has **four palettes of 256 entries each**. The program loads the palette `pal65` (entries 0 to 15: the C64 colours, then gradients) into palette bank 1 and selects it for text and bitmap. There is hardly anything to see on the screen; you check the result in the emulator's monitor by reading the register windows `$D100` to `$D3FF`. This program, too, ends in an endless loop.

Good for learning: include files with macros (`vic4.inc`), tables as `.byte`, access to the colour registers.

## musicdemo.asm: tracker song on four SID chips

| | |
|---|---|
| Files | `musicdemo.asm`, `sidmusic.inc` (play routine), `tune4.asm` (song data) |
| Size | 2402 bytes, load address `$2000` |
| Shows | 12 voices on four SID chips, timing via the raster line |

The MEGA65 has **four SID chips** (at `$D400`, `$D420`, `$D440`, `$D460`), each with three voices, twelve voices in total. The program plays the song `tune4`, composed in the VintageCoder tracker, endlessly. The main loop waits for raster line `$FF` and calls the routine `music_play` once per frame; one call is one tick, and the song has six ticks per row. For NTSC machines, insert `.const NTSC = 1` before the include (different frequency table). You hear the music; nothing changes on the screen. Playback is confirmed on a Windows computer with Xemu, unchecked on a real MEGA65.

Good for learning: including song data and a play routine, the raster line as a timer, setting constants before an include.

## prallball.asm: a complete game

| | |
|---|---|
| Files | `prallball.asm` and the files `input.asm`, `rand.asm`, `sound.asm`, `hiscore.asm` plus many `.inc` data files |
| Size | source about 224 KB (7500 lines), assembled about 54 KB |
| Shows | full-colour characters, 16-colour sprites, raster interrupt, four SIDs, DMA audio |

A ball-and-paddle game with 24 levels: the ball bounces off walls, paddle and bricks; when all destructible bricks are gone, the next level begins. Controls: joystick in port 2 **or** keyboard (Z left, X right, space bar fire, R switches the resolution between 320 × 200 and 640 × 400, RUN/STOP aborts to the title). The game writes the high-score list to the file `PRALL.HS` on device 8.

The example shows how a larger program is built from several files: the header comment of `prallball.asm` describes every section. The file is large; the editor holds up to 768 KB. When assembling, VC65 reads the include files from the disk. For test versions, insert a line `.const NAME = value` at the start of the file before the includes (for example `.const AUTOPLAY = 1`, then the computer plays by itself); the names are in the header comment.

> The title page says "ein demospiel von vc65"; this is the only deliberate difference from the original from VintageCoder.

## Developing your own programs from them

- Start with `hello.asm`, change one line, assemble, run. This is how you learn the workflow editor → assemble → run.
- In the debugger ([chapter 5](05-debugger.md)), set a breakpoint on the first line and single-step through `hello.asm`. It is only a few lines.
- Read the comments at the beginning of `musicdemo.asm` and `paldemo.asm`: they explain the registers and the memory layout.
- Never save changes to the supplied examples disk, but to your own D81 ([chapter 6](06-projects-and-files.md)).
