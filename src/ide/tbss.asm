; SPDX-License-Identifier: GPL-3.0-or-later
; tbss.asm - beschreibbare Puffer der IDE in der Datei VC65T (Bank 4, CPU $F500..): spart Platz im Hauptprogramm (BASIC laedt nur bis $CFFF).
; In den Quellen stehen die Definitionen unter .ifndef IDE_BSS (Testprogramme ohne IDE behalten sie). Alles Nullen.
; Die Datei wird von tdata.asm hinter optab.asm eingebunden; Reihenfolge und Groesse der Puffer sind ueber optabsyms.asm auch fuer das
; Hauptprogramm verbindlich. Die Puffer sind beim Laden schon 0 (die Datei enthaelt echte Nullbytes).
ed_pat: .fill 32, 0                 ; Suchmuster und Ersatztext (ed.asm)
ed_rep: .fill 32, 0
dz_mbuf: .fill 60, 0                ; freie Meldung der Statuszeile (disp.asm)
pbuf:   .fill 32, 0                 ; Eingabezeile (disp.asm)
