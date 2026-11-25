.target mega65
.cpu 45gs02 { illegals = deny }
.org $2000
.const K = 5
G:      lda #K
.loop:  dex
        bne .loop
H:      dex
.loop:  bne .loop
        jmp G.loop
        jmp H.loop
