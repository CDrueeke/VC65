<!-- SPDX-License-Identifier: MIT-0 -->
# 3 Assembler

Englische Fassung: [../en/03-assembler.md](../en/03-assembler.md). Zurück zur [Übersicht](README.md). Vorabversion 0.1.1-Alpha.

> **Hinweis:** Der Assembler ist im Emulator Xemu getestet (Vergleich Byte für Byte mit `vcc`, dem Assembler der Desktop-Fassung von VintageCoder). Am echten MEGA65 ist er ungeprüft.

## Ziel und Sprache

Der Assembler übersetzt für den **45GS02** des MEGA65. Er versteht VCASM, die Sprache von VintageCoder, und soll für Quelltexte, die nur den MEGA65 betreffen, dasselbe Ergebnis liefern wie `vcc`.

- Einziges Ziel ist `mega65`. Die Zeile `.target mega65` ist **optional** und wird akzeptiert. Jedes andere Ziel meldet den Fehler **E207**. Quelltexte aus VintageCoder mit `.target mega65` laufen unverändert.
- Es gibt kein C64-Ziel.
- Der Assembler arbeitet in mehreren Durchläufen, bricht bei einem Fehler nicht ab, sondern merkt ihn, überspringt den Rest der Zeile und übersetzt weiter. Die Fehlerliste gehört dem letzten Durchlauf.

## Was unterstützt wird

| Bereich | Umfang |
|---|---|
| Variablen | `.var`, `.set`, `name = …`, `name op= …` (`+ - * / % & \| ^ << >>`); der Wert gilt ab der Zeile, in der er gesetzt wird |
| Wiederholen | `.repeat n [, var]`, `.for i = a, bedingung, schritt`, `.for i in range(…)`, `.for c in [liste]`, `.next`, `.break`, `.continue` |
| Makros | `.macro`/`.endmacro`, Parameter (auch mit Vorgabewerten `p=wert`), Aufruf mit und ohne Klammern, Aufruf vor der Definition, `@label` je Aufruf eindeutig, `.exitmacro`, Schachtelung bis 64 Rahmen |
| Scopes | `{ }` (benannt durch die Marke in der Zeile, sonst anonym), `.namespace name {`; `scope.name` von außen; lokale Marken je Scope |
| Weitere Direktiven | `.segment "NAME"[, von, bis]` (benennt ein Segment und prüft den Bereich, E301), `.bank` (nur Bank 0), `.page [n]`, `.pseudopc`/`.endpseudopc`/`.realpc`, `.fill`, `.lohifill`, `.struct`, `.enum`, `.rta`, `.basicstub ziel, zeile, "text"`, `.assert`, `.error`, `.warning`, Aliase `.db .dw .dbyt .long`, `//`-Kommentare |
| Kanonische Namen | unter anderem `.relocate/.endrelocate`, `.retaddr`, `.lohitable`, `.screencode`, `.textnull/.textlen/.textshift`, `.addr`, `.endfor`, `.scope/.endscope`, `.align n, füllbyte\|skip` |
| Funktionen | eingebaut: `abs sign min max int floor ceil round next align pow sqrt sin cos tan asin acos atan atan2 exp log log2 log10 len range`; eigene: `.function name(a, b) = ausdruck` (ein Ausdruck, bis 16 Ebenen tief, keine Rekursion) |
| Kommazahlen | `2.5`, `1e3`, `1.5e-2`, `pi`; Rechnen, Vergleiche, `&& \|\| !`; an Stellen, die eine Ganzzahl brauchen, wird zur Null hin gekürzt |
| Listen | `[a, b, c]`, `t[i]`, `t[-1]`, `t[a:b]`, `t[:n]`, `t[n:]`, `Liste + Liste`, `Liste * n`, `len`, `range`; `.byte`/`.word`/`.dword` geben Listen flach aus; `.var t = []` mit `t += [..]` |
| Text | `{name}`, `{$hh}`, `{nnn}`, `{name*n}`, `{{` in Zeichenketten; `.encoding "name" { … }` |
| Marken | lokale und anonyme Marken (`jmp ++`, `bne --`) |

Außerdem: Includes und Systembibliotheken (siehe unten), die Befehle des 45GS02 einschließlich der Q-Register-Befehle (zum Beispiel `ldq`, `aslq q`, `lsrq q`).

## Includes und Systembibliotheken

- `.include "datei"` und `#include` lesen immer von der **Diskette**: Dateien des Anwenders vom **Projektlaufwerk**, Bibliotheken von der **Systemdisk**.
- Bibliotheken wie `<mega65/vic4.asm>` liegen als flache Namen `ORD.NAME` auf der Systemdisk (siehe [Kapitel 1](01-einstieg.md#namen-der-systembibliotheken)).
- Pfade, die über die Projektwurzel hinausführen (`../../common/…`), werden zu `common/…` vereinfacht.
- Ab der 17. Datei in einem Projekt teilen sich die Dateien einen Namensplatz; davon leidet nur die Zuordnung eines Fehlers zur Datei.
- Fehler in einer Include-Datei zeigen `in file n` statt der Spalte; der Cursor springt dann nicht.

### Chip-Symbole

Die Chip-Symbole des MEGA65 (zum Beispiel `vic2.border`) stehen in der Datei `MEG.CHIPS` der Systemdisk. Der Assembler bindet sie bei jedem Durchlauf selbst ein. Fehlt die Datei, gibt es nur keine Chip-Symbole.

## E300: Code vor dem ersten `.org`

Wie `vcc` meldet VC65 den Fehler **E300**, wenn vor dem ersten `.org` (oder `*=`) ein Byte ausgegeben oder eine Marke definiert wird. Erlaubt bleiben Konstanten, Makrodefinitionen und ein `.align` ohne Wirkung.

## Grenzen

- **Nicht-ASCII-Zeichen (UTF-8, Umlaute):** In Kommentaren und in Zeichenketten für `.text`, `.petscii` und `.byte` übersetzt VC65 wie `vcc` (byte-gleich). **Abweichungen von `vcc`:** Labels, Konstanten und Zeichenliterale (`'ü'`) mit Nicht-ASCII-Zeichen meldet VC65 als Fehler (E205 beziehungsweise E201), `vcc` nimmt sie an; `.screencode` mit Nicht-ASCII-Zeichen ergibt anderen Code (zum Beispiel `$C3` statt `$43` für das erste Byte von ü). Empfehlung: Umlaute nur in Kommentaren und in Zeichenketten für `.text`, `.petscii` und `.byte`; Bezeichner und `.screencode` nur mit ASCII. Der Editor zeigt jedes Byte über 127 als Punkt (ein ü als zwei Punkte); gespeichert werden die Bytes unverändert.
- **Makros:** höchstens **16 Parameter** je Makro (Grenze von VC65; `vcc` kennt keine). Mehr Parameter melden **E900**. Ein Aufruf mit mehr Argumenten als das Makro Parameter hat meldet wie bei `vcc` E209.
- **Kommazahlen sind Festkomma 32.32**, nicht IEEE-Double wie in `vcc`: Auflösung 2,3·10⁻¹⁰, Ganzzahlteil 32 Bit. Winkel-, Logarithmus- und Wurzelfunktionen liefern bis auf Rundungsfehler um 10⁻⁸ dasselbe; Ergebnisse, die bis auf etwa 2⁻²² ganzzahlig sind, werden auf die ganze Zahl gesetzt. Grenzfälle können abweichen.
- **Ganzzahlen sind 32 Bit** (`vcc`: 64 Bit).
- Eine Liste mit mehr als etwa 900 Elementen sprengt den Listenspeicher (8 KB, Fehler E211). `x += [..]` kopiert die Liste jedes Mal.
- `.run` wird gelesen, hat aber keine Wirkung (W206). `.atascii` und `.cartridge` gibt es nicht (E208), ebenso keine Systemdateien anderer Ziele; `.bank` kennt nur Bank 0 (andere Bank: E901).
- `.fill` und `.lohifill` werten den Ausdruck je Element aus; bei sehr großen Tabellen ist das langsamer.
- Verschachtelungstiefe: 64 Rahmen, 7 Scopes, Namen bis 31 Zeichen samt Scope-Pfad (sonst E211).
- Struct-Felder vom Typ einer Struktur mit Anzahl größer 1 legen die Unterfelder nur für das erste Element an (wie `vcc`).
- Ein fehlendes Makro-Argument ohne Vorgabewert meldet E209.
- `.assert` und `.error` melden E207 erst im letzten, stabilen Durchlauf.
- Haltepunkte in Makrorümpfen und Include-Dateien sind nicht möglich (siehe [Kapitel 5](05-debugger.md)).
- Im Vergleich mit `vcc` über rund 500 Quelltext-Schnipsel der VCASM-Hilfe stimmen rund 98,7 % überein, die Warnungen sind identisch. Die Reste sind Randfälle, vor allem bei Fehlerfolgen, und bewusste Ausnahmen (`.atascii`, `.cartridge`, Systemdateien anderer Ziele).

Die Rechengeschwindigkeit: Eine Selbstübersetzung (8477 Zeilen, 4 Durchläufe) dauerte in Xemu bei 40 MHz 5,8 s, rund 0,7 s je 1000 Zeilen über alle Durchläufe. Am echten MEGA65 ist die Geschwindigkeit ungeprüft.
