# Hinweise zu Fremdanteilen

Stand: 2026-11-24 (Vorabversion 0.1.0-Alpha).

Enthalten:
- **Aus VintageCoder (GPL-3.0-or-later, derselbe Rechteinhaber)**: die Opcode-Tabelle (`src/asm/optab.asm`, erzeugt von `tools/gen_optab.py` aus den Daten von VintageCoder), die Konformitätsbeispiele (`tests/`) und die **Systemdateien** der Boot-D81 (`<mega65/...>`, `<common/...>`, `<c64/hardware.asm>`, aus dem Datenordner von VintageCoder; sie liegen auf der Disk unter flachen Namen, siehe `tools/mksysdisk.py`). Die Chip-Symbole (`sys/mega65/chips.asm`) sind aus VintageCoder-Daten erzeugt (`tools/gen_chips.py`). Herkunft und Stand: `tools/vcc.version` (festgelegter Stand von `vcc`) und `vendor/vintagecoder`.

Nicht enthalten:
- **ROMs und Hypervisor des MEGA65** gehören Dritten; VC65 liefert sie nicht mit.
- **EasyAsm** (Dan Sanderson) diente nur als Vergleich; es wurde **kein Code übernommen**.

Jede künftig eingebundene Fremdkomponente (Code, Daten, Schrift) wird hier mit Herkunft, Urheber, Lizenz und Fundstelle aufgeführt, bevor sie ins Repository kommt. Neue Abhängigkeiten brauchen eine mit der GPL-3.0 vereinbare Lizenz.
