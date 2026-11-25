; SPDX-License-Identifier: GPL-3.0-or-later
; =====================================================================================================================
; aoverlay.asm - Overlay A (Datei VC65A): die Funktionen des Assemblers (func.asm), die Rechenroutinen (math.asm) und deren Tabellen
; (mathtab.asm), zusammen rund 4,7 KB, liegen nicht im Hauptprogramm. Sie laufen bei CPU-Adresse $E000 (Bank 4) und teilen sich den
; Platz mit dem Debugger-Overlay VC65D und dem Werkzeug-Overlay VC65X; wer geladen wird, ersetzt die anderen. Die Sprungstuecke im
; Hauptprogramm (src/asm/funcres.asm, oa_chk) laden das Overlay bei Bedarf: beim ersten Mal von der Disk (und merken es im Attic),
; danach per Kopie aus dem Attic.
; Einsprungtabelle (3 Byte je Eintrag, feste Adressen, siehe funcres.asm): $E000 ex_call, $E003 argpush, $E006 arg_get, $E009 f_pass, $E00C d_function.
; Zellen am Overlayanfang (feste Adressen, das Hauptprogramm greift darauf zu): $E010 asp (2), $E012 fnargs, $E013 fi.
; Die Namen des Hauptprogramms kommen aus build/ovsyms_a.asm (tools/build_ide.py, ohne die Namen der Einsprung-Sprungstuecke).
; =====================================================================================================================
.target mega65
.cpu 45gs02 { illegals = deny }
.branchlong auto
OA_BUILD = 1
.org $e000
.include "../../build/ovsyms_a.asm"
oa_tab:
        jmp ex_call                 ; 0
        jmp argpush                 ; 1
        jmp arg_get                 ; 2
        jmp f_pass                  ; 3
        jmp d_function              ; 4  Direktive .function (Direktiventabelle in asm.asm)
        .fill $e010 - *, 0          ; Auffuellen bis $E010
asp:    .word 0                     ; Argumentstapelzeiger (func.asm; gleiche Adresse wie OA_ASP im Hauptprogramm)
fnargs: .byte 0                     ; Argumentzahl des laufenden Aufrufs
fi:     .byte 0                     ; Zaehler
.include "../asm/math.asm"
.include "../asm/mathtab.asm"
.include "../asm/func.asm"
