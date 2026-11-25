<!-- SPDX-License-Identifier: MIT-0 -->
# VC65 als ein Programm: Editor und Assembler (`src/ide`)

> **Sprache (Stand 2026-11-24):** Alle Texte des Programms (Menüs, Meldungen, Eingabezeilen, Debuggerbild) sind **englisch**; ältere deutsche Zitate von Programmtexten in dieser Entwicklerdokumentation sind überholt (neue Texte: `src/ide/chrome.asm`, `src/editor/disp.asm`, `src/ide/ide.asm`, `src/debug/dbgui.asm`). Dokumentation und Website bleiben Deutsch und Englisch.

Englische Fassung: [../en/n1-ide.md](../en/n1-ide.md). Quellen: `src/ide/vc65.asm` (Hauptprogramm), `src/ide/ide.asm` (Verbindung).

## Ablauf
`vc65.asm` bindet alle Assemblermodule, Editor, Anzeigeschicht und Dateiroutinen in **ein** PRG (Start mit `RUN`, Basisseite `$1F00`) und ruft `ed_run`. Die Anzeigeschicht kennt zwei Haken, die `ide_init` setzt:
- **Strg+E** (`SP_ASM`, Taste `$05`) → `ide_asm`: Editortext (ohne Lücke) nach `$0800_0000` kopieren, Endemarke 0, Dateitabelle für Includes leeren (`$0820_0000`), Dateilader einschalten (Laufwerk 8), `asm_run`. Erfolg: Meldung „OK 123 Byte“, Ausgabe ab `$0005_0000`, Länge `ed_olen`, Ladeadresse `ed_ldadr` (das erste `.org` vor jeder Ausgabe, im Assembler `ldadr`). Fehler: Meldung „E204 Zeile 12 Spalte 5“ (erster Fehler der Liste) und der Cursor springt in die Fehlerzeile; Fehler in einer Include-Datei zeigen „in Datei n“ statt Spalte und springen nicht.
- **Strg+F** (`SP_PRG`) → Eingabezeile `Datei:` → `ide_prg`: schreibt Ladeadresse (2 Byte) und Ausgabe als PRG unter dem Namen aus `ed_oname`. Ohne vorheriges Übersetzen meldet sie „Erst uebersetzen“.
Die Tastencodes sind vorläufig und am Gerät ungeprüft. Die Meldung steht in der Statuszeile ab Spalte 20 (Meldungsart `MSG_DYN`, Text in `dz_mbuf`).

## Start aus Bank 4 (`src/ide/boot.asm`)
Konzept Abschnitt 7: Bank 0 gehört dem Testprogramm. BASIC lädt das PRG nach Bank 0; `boot` kopiert das Abbild (`$2000` bis `IMG_END`) über 32-Bit-Zeiger nach `$0004_2000`, blendet mit `MAP` (A=`$00`, X=`$E4`, Y=`$00`, Z=`$34`) die CPU-Adressen `$2000–$BFFF` auf Bank 4 und läuft dort weiter; danach ist Bank 0 frei. Die **Brücke** (Bank 0 ab `$1660`, etwa 380 Byte, immer sichtbar) stellt für KERNAL-Aufrufe die Standardabbildung her (`$00,$00,$00,$83`):
- `KSETNAM` … `KREADST`: Sprungstücke mit den Namen der KERNAL-Routinen; Register A, X, Y und Flags gehen durch. `KSETNAM` kopiert den Dateinamen nach Bank 0 (`kname`), weil das KERNAL ihn dort liest.
- `kernal_getin`: wartet auf eine Taste (Interrupts nur währenddessen frei); `krun`: ruft das Testprogramm (`kr_t`) auf; `kdefault`/`kide`: Abbildung umschalten.
**Lehren (alle in Xemu gefunden):** (1) 32-Bit-Zeiger (`[zp],z`) sehen nicht durch `MAP`: wer Daten des Abbilds so liest, muss Bank 4 angeben. (2) Das KERNAL verlangt Z = 0 und kann Interrupts freigeben; die Brücke setzt Z und danach wieder `sei`, sonst springt ein IRQ über den Vektor `$FFFE` ins Leere (die IDE-Abbildung blendet das ROM bei `$E000` aus). (3) Selbstverändernder Code in der Brücke braucht eine 16-Bit-Platzhalteradresse (`$0100,x`), sonst wird `$0000,x` zum Nullseitenbefehl. (4) Bank 1 enthält BASIC-Daten ab `$1_0000`: Tests dürfen dort nur kleine Ergebnisbereiche beschreiben; die Testausgabe geht deshalb nach Bank 4 unter das Abbild (`$0004_0000`).
Stufe-2-Daten des Assemblers liegen in der IDE in Bank 5 (`IDE_BUILD`, `S2BANK = 5`), die Ausgabe im Attic ab `$0850_0000`.

## Programm starten (Strg+R)
`ide_run` (Hook `SP_RUN`, Taste `$12`) kopiert die Ausgabe aus dem Attic nach Bank 0 an die Ladeadresse (nicht unter `$2000`), springt bei einem `.basicstub` an die SYS-Adresse, sonst an die Ladeadresse, und ruft per `krun` auf (Standardabbildung, Interrupts frei). Kehrt das Programm per `RTS` zurück, meldet die IDE „Programm beendet“; Bank 4 mit der IDE bleibt unberührt. Ein Programm, das nicht zurückkehrt, braucht Reset (Notfalltaste folgt mit dem Debugger). Test: `tools/idetest.py` startet ein Programm, das `$42` nach `$C500` schreibt.

## Speicherplan (Bank 0)
| Bereich | Inhalt |
|---|---|
| `$0800–$0FCF` | Bildschirm; der Kern zeichnet **direkt** hinein (`ed_scr = $0800`) |
| `$1000–$11FF` | **nicht benutzbar**: Überschreiben hängt BASIC beim Rückkehren (System des ROMs) |
| `$1200–$17FF` | Puffer des Assemblers (`curgstk`, `onelist`, `cynames`, `cyrep`, `inname`, `inpath`, `inpath2`, `filebase`, `fr`) |
| `$1800–$1EFF` | `fnames` (1 KB), `ptbl`, `ldbuf`, `fbuf` |
| `$1F00–$1FFF` | Basisseite (Zeropage-Umlagerung) |
| `$2001–$BFFF` | frei für das Testprogramm (die IDE läuft aus Bank 4, siehe oben; ihr Abbild endet bei etwa `$BD`xx) |
| `$C000–$CFFF` | **nicht für Code**: das ROM überdeckt beim Lesen diesen Bereich (Schreiben ginge ins RAM) |
Farben: `ED_ATTR32 = $0FF8_0000` (Farb-RAM, `DISP_DIRECT = 1`); die Tests nutzen stattdessen einen Puffer in Bank 0 und lassen die Anzeigeschicht kopieren. Attic: Quelltext `$0800_0000`, Symbole `$0810_0000`, Sprungtabelle `$0812_0000`, Dateitabelle `$0820_0000`, Editortexte und Verläufe der Reiter `$0830_0000`–`$084F_FFFF` (je 256 KB), Zwischenablage `$0870_0000`, Reiterdatensätze `$0870_8000`. Bank 4: Stufe-2-Daten des Assemblers, Bank 5: Ausgabe.

**Lehre:** Der Code liegt nahe an der Grenze von Bank 0 (`$C000`). Wächst das Programm weiter, braucht es Bankumschaltung (`MAP`) oder ein Auslagern von Tabellen; das ist der nächste Architekturschritt (Brückenstück, Konzept Abschnitt 7).

**Nachtrag (Debugger):** Die IDE-Abbildung zeigt jetzt Bank 4 auf `$2000–$FFFF` (MAP X=`$E4`, Z=`$F4`), das Hauptprogramm darf bis `$CFFF` reichen (Stand etwa `$C4A0`), darüber liegt das Overlay `VC65D` ab `$D000`. Die Bank-4-Bereiche `$0004_0000–$0004_1FFF` bleiben frei (Testausgabe). Bau: `tools/build_ide.py`. Details: [n8-debugger.md](n8-debugger.md).


**Speicherplan der IDE-Abbildung (Bank 4, CPU-Adressen; Stand 2026-11-24):** `$2000–$CFFF` Hauptprogramm `VC65` (Grenze `$D000`, weil BASIC darüber wegen der Ein-/Ausgabe nicht laden kann; Stand `$CE32`, 462 Byte Luft), `$D000–$DF9F` 50-Zeilen-Bildschirm des Editors, **zugleich** Puffer und Bild des Debuggers (`DV_I` `$D000`, `DV_T` `$D080`, `DV_D` `$D100`, `DV_S` `$D200`; der Editor zeichnet nach der Sitzung neu), `$E000–$F5FF` Overlay `VC65D`, `$F500–$FFC9` Tabellendatei `VC65T` (Befehlstabelle `optab.asm`, rund 2,3 KB, und beschreibbare Puffer aus `src/ide/tbss.asm`: Ausrichten, Suchmuster, Ersatztext, Meldung, Eingabezeile; in den Quellen unter `.ifndef IDE_BSS`), `$FFFA–$FFFF` Vektoren. `VC65T` lädt `ide_ldtab` beim Start über dieselbe Routine wie das Overlay (`ov_get`); fehlt die Datei, kehrt VC65 zu BASIC zurück. `tools/build_ide.py` baut `VC65T` zuerst und schreibt `build/optabsyms.asm` (alle Namen als Konstanten), die das Hauptprogramm statt `optab.asm` einbindet; die Testprogramme der IDE (`tools/idetest.py`, `tools/ide50test.py`) gehen denselben Weg.

## 50-Zeilen-Bild (VIC-IV, Stand 2026-11-24)

Der Editor zeigt in der IDE **80 × 50** Zeichen (`IDE_ROWS = 50` in `src/ide/vc65.asm`; `IDE_ROWS = 25` baut das alte 80×25-Bild mit dem Bildschirm bei `$0800`). Die Anzeige (`src/editor/disp.asm`: `disp_mode`, `disp_vic`) schaltet dazu den VIC-IV um. Alle Angaben zu Registern stammen aus der **MEGA65 Chipset Reference** (Abschnitt „VIC-IV / MEGA65 Specific Registers“, Seiten 26–30 und 55–58 der Ausgabe `mega65-chipset-reference_cnFcKB.pdf`) und wurden in **Xemu** (Stand 2024-09-26) nachgemessen (Messprogramme `src/spike/vicprobe.asm` und `src/spike/flatio.asm`, Auswertung über den Xemu-Monitor `tools/xmon.py`); am echten MEGA65 sind sie noch zu prüfen (Handtest unten).

| Register | Bedeutung (Quelle) | Gemessen in Xemu |
|---|---|---|
| `$D031` Bit 3 `V400` | 400 senkrechte Pixel. „Heißes“ Register: jeder Schreibzugriff auf `$D011`, `$D016`, `$D018`, `$D031` oder die Bank-Bits von `$DD00` lässt den VIC-IV seine Anzeigeregister neu berechnen (S. 28–30) | Start `$E0` (H640, FAST, ATTR); mit V400 `$E8` |
| `$D07B` `DISPROWS` | Zeilen des Textbildes minus 1: Hot-Register setzt 24 (V200) oder 49 (V400) (S. 29) | `$18` → `$31` |
| `$D05B` `CHRYSCL` | senkrechte Skalierung der Zeichen, wird vom Hot-Register ebenfalls gesetzt (S. 29; der Text nennt „0 für V200, 1 für V400“ und beschreibt gleichzeitig „1 oder 2 Pixel hoch“, die beiden Angaben passen nicht zusammen) | bleibt `$00` (Xemu rechnet nicht mit); **am MEGA65 prüfen** |
| `$D058/$D059` `LINESTEP` | Bytes je Textzeile; Hot-Register setzt 80 bei H640 (S. 30) | `$0050` |
| `$D05E` `CHRCOUNT` | Zeichen je Zeile; Hot-Register setzt 80 bei H640 | `$50` |
| `$D060–$D062` `SCRNPTR` | Adresse des Bildschirmspeichers (24 Bit, S. 26); das Hot-Register setzt sie auf den Wert aus `$D018`/`$DD00` zurück | `$000800` bei Start; nach Schreiben von `$D031` wieder `$0800` |
| `$D064/$D065` `COLPTR` | Versatz im Farb-RAM (S. 27); Hot-Register setzt 0 zurück | 0 |
| `$D02F` | Freischaltung des VIC-IV: `$47`, dann `$53` | – |

**Zugriff:** über die flache Adresse `$0FFD30xx` (32-Bit-Zeiger `CP` mit `[CP],z`), also ohne die E/A-Abbildung bei `$D000` (in der IDE-Abbildung ist sie ausgeblendet). In Xemu gemessen: `$D031`, `$D07B` und `SCRNPTR` lassen sich so lesen und schreiben.

**Platz:** 80 × 50 sind 4000 Byte Zeichen und 4000 Byte Farbe. Bei `$0800` ist das nicht möglich (`$1000–$11FF` darf nicht beschrieben werden, `$1200–$17FF` gehört dem Assembler, die Brücke liegt bei `$1648`). Der Bildschirm liegt deshalb bei **`$0004_D000–$0004_DF9F`** (Bank 4, im IDE-Abbild als CPU-Adresse `$D000` sichtbar, `ed_scr = $D000`); `SCRNPTR` zeigt darauf (`ED_SCRPHYS`). Das Hauptprogramm muss unter `$D000` bleiben (Stand `IMG_END` = `$CC61`, Grenze von `build_ide.py` nicht geprüft: bei Wachstum `IMG_END` kontrollieren). Die Farben liegen im Farb-RAM ab `$0FF8_0000` (3999 Byte, `COLPTR` = 0). Das Overlay des Debuggers beginnt erst bei `$E000`.

**Rückschalten:**
- *Programme* (Strg+R, Strg+D): `krun` löscht V400 (`$D031` Bit 3) in der Standardabbildung. Das Hot-Register setzt `DISPROWS` 24, `SCRNPTR` `$0800` und `COLPTR` 0 zurück; das Programm sieht den üblichen 80×25-Bildschirm. Nach der Rückkehr (`ide_run`) stellt `disp_mode` das 50-Zeilen-Bild wieder ein.
- *Debugger:* sein Bildschirm hat 25 Zeilen (`$0004_D200`, Farben ab Farb-RAM `$1000`, vorher `$0800`: das lag im Farb-RAM des 50-Zeilen-Editors). `dv_start` sichert den IDE-Zustand (`DV_I`, 50 Zeilen), schaltet V400 kurz aus, lässt die Hardware die Register für 25 Zeilen berechnen und sichert diesen Zustand als Grundlage von `DV_D` (so steht `CHRYSCL` ohne Annahme richtig), stellt `DV_I` wieder her und setzt die Zeiger auf den Debuggerbildschirm. `dv_end` bringt die IDE (50 Zeilen) zurück.
- *Ende:* `main` stellt vor der Rückkehr nach BASIC 25 Zeilen ein.
- **`SCRNPTR` wird verstellt:** Jeder Diskettenzugriff (Hypervisor, D81-Abbild) setzt `$D061` zurück (in Xemu gemessen: Strg+E mit Zugriff auf das D81, `$D061` `$D0` → `$10`; Ursache nicht im Quelltext gefunden). `disp_flush` setzt darum `SCRNPTR` vor jedem Neuzeichnen neu (`disp_vic`), und `dv_start` tut es vor dem Merken des IDE-Zustands.

**Test:** `tools/ide50test.py` (Xemu mit UART-Monitor, `tools/xmon.py`, ohne `-prgexit`): Bild (Zeichen und Farben gegen das Python-Modell, 50 Zeilen), Blättern, Programmlauf (das Programm sieht V400 aus, `DISPROWS` 24, `SCRNPTR` `$0800`; danach 50 Zeilen), Debugger (25 Zeilen, nach `c` wieder 50). Stand: alle Fälle bestanden. Die 25-Zeilen-Fassung (`IDE_ROWS = 25`) startet unverändert (Xemu: `$D031` `$E0`, `DISPROWS` 24, Bildschirm `$0800`). Die vorhandenen Tests (`idetest.py`, `dbgtest.py` usw.) wurden hier nicht ausgeführt (der Xemu-Stand 2024-09 kennt `-prgexit` nicht); `idetest.asm` bleibt bei 25 Zeilen und nutzt den Stellvertreter `disp_vic: rts`.

**Handtest am echten MEGA65 (offen):**
1. IDE starten: 50 Zeilen sichtbar (Zeilen gleichmäßig, letzte Zeile = Statuszeile), Zeichenhöhe 8 Pixel, kein Flackern.
2. Strg+E (mit Disketten-Includes) und Strg+K (Speichern auf die Diskette): bleibt der Bildschirm stehen, oder springt er (SCRNPTR-Reset, siehe oben)?
3. Strg+R: das Programm läuft im 80×25-Standard; danach ist das 50-Zeilen-Bild zurück. Strg+D: Debuggerbild lesbar mit 25 Zeilen, Zeichenhöhe normal (prüft `CHRYSCL`/Zeichenhöhe der Hardware), Taste V zeigt das Programmbild, Ende zurück in 50 Zeilen.
4. PAL und NTSC, Anzeige am Monitor/Fernseher (Ränder: 50 Zeilen × 8 Pixel = 400 Rasterlinien, wie V400).

## IDE-Rahmen: Befehlsleiste, Dateizeile, Probleme-Leiste (`src/ide/chrome.asm`, Stand 2026-11-24)

Angenähert an die Entwürfe in `docs/mockups` (Entwurf; die Menüs mit Aufklappfeldern gibt es noch nicht). Bild mit 50 Zeilen: Zeile 0 **Befehlsleiste** (umgekehrt, zeigt die Strg-Tasten: Laden, Sichern, Bauen, Start, Debug, Haltepunkt, Laufwerk), Zeile 1 **Dateizeile** (Name der Datei und Projektlaufwerk; es gibt keine Reiter), dann der Text, darunter die **Probleme-Leiste** (4 Zeilen: Kopf und bis zu drei Einträge des letzten Übersetzens, Fehler rot `E205 Zeile 10 Spalte 13`, Warnungen gelb `W206 …`, sonst „Keine Probleme“), zuletzt die Statuszeile. **Menü** (HELP-Taste, `chrome_menu`): Aufklappfelder Datei, Bearb, Suchen, Bauen, Debug; links/rechts wechselt, auf/ab wählt, Return führt aus (der Befehl geht wie eine Taste an die Hauptschleife, Haken `disp_menuv`, Code `SP_MENU`), STOP/HELP schließt; die Felder zeigen die Tastenkürzel. Der Code `$84` der HELP-Taste ist am Gerät ungeprüft (Test mit Tastenskript in `tools/idetest.py`: `menue_*`). **Automatische Prüfung** (`ide_auto`, Haken `disp_autov`): Wechselt die Cursorzeile und hat sich der Text seit dem letzten Übersetzen geändert, übersetzt die IDE selbst, still (wie Strg+E, aber ohne Meldung und ohne Cursorsprung); Probleme-Leiste und rote Zeilen sind danach aktuell, die Ausgabe ebenfalls. Nur bei Texten unter 16 KB (je Lauf rund 0,2 s mit Systemdatei in Xemu); größere Texte weiter mit Strg+E. Tests `auto_ok`, `auto_fehler` in `tools/idetest.py`. **Fehlerzeilen** (nur mit `ed_deco`): nach Strg+E erscheinen die Zeilen mit Fehlern im Hauptprogramm (bis 16, `ide_emark`) rot (`er_chk`); die Färbung gilt, solange sich der Text nicht ändert (`ed_ehp` = `hp` beim Übersetzen). **Schmuck** (`ed_deco`, nur in der IDE): senkrechter Strich hinter den Zeilennummern, die Cursorzeile trägt `>` und eine gelbe Nummer, Befehlsleiste hellblau, Kopf der Probleme-Leiste und Statuszeile als graue Leisten (umgekehrte Darstellung). Im 25-Zeilen-Bild gibt es nur die beiden Kopfzeilen.

- **Editorkern**: `ed_layout` (A = Kopfzeilen, X = Fußzeilen) legt fest, wie viele Zeilen oben und unten der Kern überspringt; Textzeilen `ed_trows = ed_rows - 1 - Kopf - Fuß`. `ed_init` stellt 0/0 ein (alle bisherigen Tests unverändert). Seiten blättern und Ansicht richten sich nach `ed_trows`; der Cursor liegt um `ed_hdr` Zeilen tiefer (`disp_show`).
- **Zeichnen**: `chrome_init` (nach `ed_init`) setzt 2 Kopfzeilen und bei 50 Zeilen 4 Fußzeilen und hängt `chrome_draw` in den Haken `disp_tabdv`; es läuft nach jedem Zeichnen des Kerns.
- **Probleme**: `ide_plist` (nach `asm_run`) schreibt bis zu drei Zeilen aus der Fehler- und der Warnungsliste (zuerst Fehler) mit dem Text der Meldung (`ia_msg`, ohne Cursorsprung) nach `PQ_BASE` (`$0870_F000`, Attic, 64 Byte je Zeile).
- **Platz**: **Platz**: siehe Speicherplan oben (die Befehlstabelle liegt in `VC65T`); `tools/build_ide.py` bricht über der Grenze `$D000` ab.
- **Test**: `tools/edtest.py` prüft Kopf-/Fußzeilen (Seeds 100/101: Zustand und Textzeilen wie ein Editor mit weniger Zeilen); Bildschirmfotos mit Rahmen: `tools/screens.py --50`.

## Test
`tools/idetest.py` lädt Quelltexte in den Editor (über das Attic), drückt Strg+E (und Strg+F), und vergleicht in Xemu: Ausgabebytes und die gespeicherte PRG-Datei (aus dem D81 gelesen) mit vcc, Fehlercode und -zeile sowie die Cursorzeile bei Fehlern; dazu ein Include-Fall über das D81. Stand: alle Fälle identisch. Die übrigen Tests (30 Assemblertests, Include, Zyklen, Fehlerliste, Selbstübersetzung, Konformität, Editor und Anzeige) laufen unverändert.

## Systemdisk und Projektlaufwerk

Die Systemdateien des MEGA65 (`<mega65/…>`, `<common/…>`, `<c64/hardware.asm>`, dazu die Chip-Symbole `vic2.border` usw.) liegen auf der **Systemdisk**, der D81 mit VC65 selbst (Laufwerk 8, `ed_sdev`). Der Quelltext liegt auf einer **zweiten D81** (Projektlaufwerk `ed_fdev`, Vorgabe 8, mit **Strg+A** (`$01`) zwischen 8 und 9 umschaltbar, Meldung „Projektlaufwerk 9“). Laden, Speichern und die Includes des Anwenders (`.include "datei"`) gehen an das Projektlaufwerk, Bibliotheken und das Overlay VC65D an die Systemdisk.

Namensabbildung (D81-Namen sind höchstens 16 Zeichen, ohne Ordner): `<ordner/name.endung>` → `ORD.NAME` aus den ersten drei Zeichen des Ordners und dem Namen ohne Endung, Großbuchstaben, z. B. `<mega65/vic4.asm>` → `MEG.VIC4`, `<common/tiles.asm>` → `COM.TILES`, `<c64/hardware.asm>` → `C64.HARDWARE`. Die Chipdatei (`sys/mega65/chips.asm`, erzeugt von `tools/gen_chips.py`) heißt `MEG.CHIPS` und wird bei jedem Durchlauf selbst eingebunden; fehlt sie, gibt es nur keine Chip-Symbole.

`tools/mksysdisk.py` baut die Systemdisk (14 Dateien, rund 150 KB). `tools/systest.py` prüft in Xemu mit zwei D81 (Systemdisk in Laufwerk 8, Projektdisk in Laufwerk 9), dass das Ergebnis byte-identisch zu `vcc` ist. Ungeprüft am echten MEGA65: das Einlegen zweier Images und die Geräteumschaltung des KERNAL.
