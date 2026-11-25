<!-- SPDX-License-Identifier: MIT-0 -->
# Etappe N2: Assembler Stufe 1 (Stand und Aufbau)

Englische Fassung: [../en/n2-assembler.md](../en/n2-assembler.md). Ziel (Konzept, Abschnitte 6, 9, 16): VCASM-kompatibler Assembler für den 45GS02, Stufe 1 (alle Befehle und Adressierungsarten, Marken, Ausdrücke, Direktiven des Kerns, zwei Läufe, Fehlerliste), gleiche Ergebnisse wie `vcc`.

## Bausteine (alle in `src/asm/`, VCASM, laufen auf dem MEGA65)

| Datei | Inhalt | Stand |
|---|---|---|
| `zp.asm` | Zeropage-Belegung (jede Zelle einmal), Fehlercodes | fertig |
| `src.asm` | Quelltext lesen über 32-Bit-Zeiger (`[SRC],z`), Leerraum überspringen | fertig |
| `optab.asm` | Opcode-Tabelle, **erzeugt** von `tools/gen_optab.py` aus `vendor/vintagecoder/data/cpus/45gs02.cpu.json` | fertig (145 Mnemoniken) |
| `mnfind.asm` | Mnemonik-Suche (binäre Suche); `NOP` wird zu `EOM` (wie `vcc`) | fertig, getestet |
| `sym.asm` | Bezeichner, Symboltabelle (Hash, Attic ab `$0810_0000`), lokale Namen (`.name` → `global.name`) | fertig |
| `expr.asm` | Ausdrücke, 32 Bit mit Vorzeichen, Vorrang wie `vcc`; Zahlen `$`/`0x`/`%`/Dezimal/`'c'`, `*` | fertig, 74 Fälle |
| `enc.asm` | Operanden lesen, Adressierungsart wählen (Zeropage/absolut/relativ, Quad, 32-Bit-Zeiger), lange Sprünge | fertig |
| `asm.asm` | Treiber (Durchläufe bis die Symbole stabil sind, höchstens 16), Zeilen, Marken (global, lokal, anonym `-`/`+`), Direktiven | Teilmenge, siehe unten |
| `stage2.asm`, `dir2.asm`, `text2.asm`, `func.asm`, `charnames.asm` | Stufe 2: Variablen, Schleifen, Makros, Scopes, weitere Direktiven, Sonderzeichen in Texten | siehe [n4-assembler-stufe2.md](n4-assembler-stufe2.md) |

Unterstützte Direktiven: `.org` / `*=` (Lücken im Rohformat mit 0 gefüllt), `.byte`, `.word`, `.dword`, `.be16`, `.be32`, `.rta`, `.hex`, `.fill`, `.align`, `.text`, `.petscii`, `.screen`, `.null`, `.ptext`, `.shift`, `.encoding`, `.const`/`.equ` und `name = ausdruck`, `.basicstub`, `.branchlong auto`, `.target mega65`, `.cpu …`; Suffixe `.z` und `.a` an Befehlen.

Noch offen für Stufe 1: Attic statt Bank 5.

Stufe 2 (Etappe N4) ist weitgehend gebaut: siehe [n4-assembler-stufe2.md](n4-assembler-stufe2.md). Offen bleiben Ordner und lange Namen der SD-Karte (Hyppo, N6) (derzeit ohne Wirkung) und der Dateizugriff.

## Regeln aus `vcc` (nur gelesen) für die Codierung

- Quad-Befehle (`LDQ` … `NEGQ`) tragen die Opcodes ihres Grundbefehls mit Präfix `$42 $42`; erlaubt sind nur die Adressierungsarten imp, acc, zp, zpx, abs, abx und izz, sonst `E206`.
- 32-Bit-Zeiger `[zp]` und `[zp],z` setzen das Präfix `$EA` vor die izz-Form (nach dem Quad-Präfix).
- Plain-Operanden wählen Zeropage, wenn der Wert **bekannt** und 0…255 ist, sonst absolut. Ein Symbol, das erst später definiert wird, gilt im ersten Durchlauf als unbekannt (große Form); im nächsten Durchlauf zählt sein dann bekannter Wert. Darum wird so oft übersetzt, bis sich kein Symbolwert mehr ändert.
- Relative Sprünge: Weite = Ziel − (Adresse des Befehls + Präfixlänge + 2); `BBR`/`BBS`: Ziel − (… + 3). Mit `.branchlong auto` wird ein zu weiter Sprung zur langen Form (`LBNE` …), einmal lang bleibt lang.
- Eine Direktive `.name` ohne folgenden Doppelpunkt ist eine Direktive, mit Doppelpunkt ein lokales Label.

## Selbstübersetzung (Meilenstein 2026-11-23)

Der native Assembler übersetzt **seinen eigenen Quelltext** (Prüfprogramm samt allen Modulen aus `src/asm`; beim Meilenstein 3801 Zeilen und 8598 Byte, mit Stufe 2 jetzt 7555 Zeilen und 18024 Byte, mit `tools/flatten.py` zu einer Datei zusammengefasst, im Attic ab `$0800_0000` abgelegt) in Xemu und liefert dieselben Bytes wie `vcc` (`tools/selfhost.py`). Voraussetzung dafür war, die Durchlauflogik von `vcc` genau nachzubilden:

- Beim Nachschlagen im Ausdruck gilt immer der Wert des **vorigen** Durchlaufs (`syms`); definiert wird in die Tabelle des **aktuellen** Durchlaufs (`new_syms`). Im ersten Durchlauf ist darum **jedes** Symbol unbekannt, auch ein weiter oben definiertes. Das bestimmt, welche Verzweigungen zur langen Form werden (einmal lang, bleibt lang). Ausnahme: das zurückliegende `-` benutzt den neuen Wert; `.ifdef`/`.ifndef` zählen nur im aktuellen Durchlauf bereits definierte Symbole.
- Jeder Symboleintrag trägt deshalb den alten und den neuen Wert und zwei Flags. Am Ende jedes Durchlaufs wird neu zu alt; ändert sich dabei ein Wert oder die Menge der Symbole, folgt ein weiterer Durchlauf (höchstens 16).
- Wertfehler (`E202`, `E203`, Sprungweite) sind „weich“: Der Durchlauf läuft weiter, nur ein Fehler des letzten, stabilen Durchlaufs zählt (wie `strict` bei `vcc`). Syntaxfehler brechen sofort ab.

## Fehlerliste (`err.asm`)

Der Assembler bricht bei einem Fehler nicht mehr ab: Er vermerkt Code und Stelle, überspringt den Rest der Zeile und übersetzt weiter (bis 100 Fehler). Die Liste gehört dem **letzten, stabilen Durchlauf** (sie wird zu Beginn jedes Durchlaufs geleert), so wie `vcc` nur die Fehler des letzten Durchlaufs meldet. Eintrag in Bank 4 `$6000` ff.: Code (1 Byte), 3 frei, Quelltextstelle (32 Bit); `ERR`/`SRC` zeigen den ersten Fehler. `err_linecol` (Eintragsnummer in A) liefert Zeile und Spalte ab 1. Fehler in einem Makroaufruf werden der Aufrufzeile zugeschrieben. Nach einem Fehler setzt `al_recover` den Stapel zurück und liest hinter der Zeile weiter; nur „Block nicht geschlossen“ am Quelltextende (`E210`/`E213`) bricht ab. Neue Codes: `E204` (Symbol doppelt mit anderem Wert), `E214` (kein passendes `-`/`+`), `E215` (`.z`/`.a` nicht möglich), `E218` (`.basicstub` nicht am Anfang), `E208` bei unbekannter `.encoding`. `tools/errtest.py` vergleicht Code und Zeile aller Fehler mit `vcc` (eigene Fälle und alle `asm fehler`-Beispiele der Hilfe: 20 von 20 gleich).

Lehre: Die Tabelle der langen Sprünge liegt jetzt im Attic (`$0812_0000`); bei großen Programmen (Ausgabe über 28 KB) überschrieb die Ausgabe sie in Bank 5 und erzeugte falsche lange Sprünge.

## Include (`inc.asm`)

`.include "datei"`, `.include "datei" as name`, `#include "datei"` (nur einmal je Datei und Namensraum, wie `#pragma once`), `#include <pfad>` (Systembibliothek: gesucht wird `sys/pfad`) und `.incbin "datei" [, offset [, länge]]`. Der Assembler greift nicht selbst auf die SD-Karte zu, sondern fragt eine **Dateitabelle im Attic** ab (`$0820_0000`); die stellt der Aufrufer bereit: im Test das Werkzeug `tools/asmtest.py` (`one_inc`), in der Entwicklungsumgebung später der Dateilader (Etappe N6, Hyppo-Zugriff). Eintrag: Namenslänge (1), Name (Pfad mit `/`, relativ zum Hauptprogramm), Länge (4 Byte, tief zuerst), Inhalt, ein 0-Byte; Ende der Tabelle: Namenslänge 0. Gesucht wird zuerst im Ordner der einbindenden Datei (`..` und `.` werden aufgelöst), dann unverändert. Nicht gefunden: `E212`.

Eine eingebundene Datei ist wie ein Makroaufruf ein Rahmen auf dem Quelltext-Stapel (`FT_INC`): `SRC` zeigt in den Dateiinhalt, an dessen Ende geht es hinter der `.include`-Zeile weiter; `as name` öffnet dazu einen Scope. Die Vorabsuche nach Makros folgt den `.include`-Zeilen (bis 6 Ebenen), so dass Makros aus Include-Dateien auch vor dem `.include` aufrufbar sind. Jeder Fehlereintrag trägt die Dateinummer (bis 16 Dateien); `err_linecol` rechnet Zeile und Spalte ab dem Anfang dieser Datei. `tools/inctest.py` vergleicht mit `vcc` (9 Fälle: Pfade, `as`, `#include` einmal, `.incbin`, Makros, Fehler in Include-Dateien). Abweichung: `vcc` meldet auch in einem nicht geltenden `.if` eine fehlende Datei, der native Assembler nicht.

Die Basisseite der Tests liegt jetzt bei `$0200` (Interrupts gesperrt), weil der Code über `$9F00` hinauswächst; Quelltexte liegen in den Tests immer im Attic.

## Zyklen zählen (`cyc.asm`) und Warnungsliste

`.cycles [name] [max=budget]` … `.endcycles` zählt wie `vcc` die Zyklen aller dazwischen **übersetzten** Befehle (jeden so oft, wie er übersetzt wird; kein Programmablauf, Sprünge werden nicht verfolgt). **min** ist die Summe der Grundzyklen, **max** der ungünstigste Fall (bedingter Sprung genommen +2). Die Zahlen je Opcode stehen in den Tabellen `cyc_base`/`cyc_worst` am Ende von `optab.asm` (von `tools/gen_optab.py` aus `45gs02.cpu.json` erzeugt); `encode` ruft `cyc_add`. Blöcke dürfen verschachtelt sein (8 Ebenen). Je Block entsteht ein Bericht (`cyrep`, bis 16: min, max, Budget, Namenslänge). Überschreitet max das Budget, gibt es die Warnung `W201`; `.endcycles` ohne `.cycles` und ein nicht geschlossener Block sind `E210` (der offene Block wird an seiner `.cycles`-Zeile gemeldet).

Dafür gibt es jetzt neben der Fehlerliste eine **Warnungsliste** (`WLIST`, Bank 4 `$6400`, Zähler `wcnt`, `warn_add`), gleich aufgebaut, gleichfalls je Durchlauf geleert; Warnungen ändern den Ausgang nicht. `tools/cyctest.py` vergleicht Berichte (min, max, Budget) und `W201`-Zeilen mit `vcc` (8 Fälle, auch Quad-Befehle, lange Sprünge, `.if`, `.repeat`, Verschachtelung).

Die Ausgabe der Tests beginnt jetzt bei `$0005_0000` (64 KB), weil die Selbstübersetzung über 32 KB ausgibt.

## Dateilader (`loader.asm`, Etappe N6 erste Stufe)

Fehlt eine Datei in der Dateitabelle, holt der Lader sie über die **KERNAL-Dateiroutinen** vom Laufwerk `lddev` (Vorgabe 8: SD-Karte oder eingelegtes D81) und hängt sie an die Tabelle an, wenn `ldon` ungleich 0 ist (die Entwicklungsumgebung setzt es). Danach läuft alles wie bei einer vorgeladenen Datei (`fs_resolve` sucht erneut). Ablauf: Name = letzter Teil des Pfads in Großbuchstaben; `SETNAM`/`SETLFS`/`OPEN` auf Kanal 2; Lesen mit `CHRIN` in einen 256-Byte-Puffer, nach jedem Byte `READST`: Bit 6 = letztes Byte, andere Bits (Datei nicht gefunden meldet `$42`, Gerät fehlt `$80`) = Fehler; der Puffer wird jeweils in den Attic hinter den Tabellenkopf kopiert; zum Schluss werden Kopf (Namenslänge, voller aufgelöster Name, Länge), das 0-Byte und das Tabellenende geschrieben. Für die KERNAL-Aufrufe schaltet der Lader die Basisseite `B` auf 0 und danach zurück (der Assembler hat seine Zeropage woanders).

Grenzen: nur Dateinamen ohne Ordner und höchstens 32 Zeichen; Unterordner und lange Namen der SD-Karte folgen mit dem Hyppo-Direktzugriff (Spike N0, Teil 2, am echten MEGA65). Der Fehlerkanal wird nicht gelesen: ein `CLOSE 15` schließt alle Dateien des Geräts. `tools/inctest.py` läuft jeden Fall zusätzlich mit `asmtest.one_disk`: die Include-Dateien liegen auf einer mit `vcc disk d81` gebauten D81 in Laufwerk 8 (Xemu `-8`), auch Dateien über 256 Byte und genau 512 Byte; 15 Fälle in beiden Betriebsarten gleich zu `vcc`.

## Speicher

Bankplan (Konzept Abschnitt 7): Code und Tabellen später in Bank 4, Arbeitsdaten in Bank 5, Quelltext, Ausgabe und Symbole im Attic. Derzeit (Test) liegen Quelltext und Code in Bank 0, Ausgabe ab `$0005_0000` und Symbole ab `$0810_0000` im Attic, die Tabelle der langen Sprünge ab `$0812_0000` im Attic; alle Zugriffe laufen schon über 32-Bit-Zeiger, die Verschiebung in den Attic ändert nur die Basisadressen.

**Wichtig (45GS02):** `LDA zp,Y` gibt es nicht; der Assembler macht daraus `abs,Y` und greift dann auf die **echte** Nullseite zu, nicht auf die Basisseite `B`. Die Tests setzen `B` auf `$0200`; Indizierung über Zeropage-Tabellen darum immer mit `X` oder über `(zp),Y`.

## Testen

| Werkzeug | Zweck |
|---|---|
| `tools/xrun.sh x.prg` | PRG headless in Xemu (Mac) laufen lassen, Bildschirm und 384 KB Hauptspeicher sichern |
| `tools/asmtest.py [name …]` | Differenztest: jedes `tests/asm/*.asm` mit `vcc` (Rohbytes) und mit dem nativen Assembler in Xemu übersetzen, Bytes vergleichen (aktuell **30 von 30**) |
| `tools/conform.py` | Konformitätsbericht über die Beispielblöcke der VCASM-Hilfe (`vendor/vintagecoder/help/`): identisch mit `vcc` (aktuell **61 von 67**; der Rest braucht Kommazahlen, Listen, Funktionen, `.cycles`, `.include` oder ist Atari-spezifisch) |
| `tools/fuzzenc.py` | Kodierungstest über alle Mnemoniken und Adressierungsarten des 45GS02 (396 von `vcc` akzeptierte Zeilen müssen byte-gleich sein; 34 abgelehnte müssen ebenfalls `E206` ergeben) |
| `tools/inctest.py` | Include: Pfade, `as`, `#include`, `.incbin`, Makros, Fehler in Include-Dateien gegen `vcc` |
| `tools/cyctest.py` | `.cycles`: Berichte und W201 gegen `vcc` |
| `tools/errtest.py` | Fehlerliste: Code und Zeile aller Fehler gegen `vcc` |
| `src/test/expr_test.asm` | Ausdrucksrechner, 74 Fälle (`tools/gen_exprtests.py`) |
| `src/test/mnfind_test.asm` | Mnemonik-Suche |

Alle Läufe bisher nur in Xemu; am echten MEGA65 nicht geprüft.
