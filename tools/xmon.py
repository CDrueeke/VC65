#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Xemu mit UART-Monitor starten und Speicher lesen (ohne -prgexit, auch fuer aeltere Xemu-Staende, z. B. Windows 2024-09).
Der Monitor ('M <hex>') liefert 16 Byte je Zeile und kennt 28-Bit-Adressen: Hauptspeicher ab $0000000 (Bank n = n * $10000), Farb-RAM
$FF80000, VIC-IV-Register flach ab $FFD3000 (VIC-IV-Register $D0xx = $FFD30xx), auch bei ausgeblendeter Ein-/Ausgabe.
Aufruf:  tools/xmon.py programm.prg wartesekunden adresse:laenge [adresse:laenge ...]     (Adresse und Laenge hex)
Umgebung: XEMU (Pfad), XEMU_ROM (MEGA65.ROM), XMON_ARGS (weitere Xemu-Optionen), XMON_PORT (Standard 4510)."""
import os, re, socket, subprocess, sys, time

CRLF = chr(13) + chr(10)


def xemu_path():
    return os.environ.get("XEMU") or (r"C:\Program Files\xemu\xmega65.exe" if os.name == "nt" else "/Applications/xmega65.app/Contents/MacOS/xmega65")


def rom_path():
    if os.environ.get("XEMU_ROM"):
        return os.environ["XEMU_ROM"]
    if os.name == "nt":
        return os.path.expandvars(r"%APPDATA%\xemu-lgb\mega65\MEGA65.ROM")
    return os.path.expanduser("~/Library/Application Support/xemu-lgb/mega65/MEGA65.ROM")


def mon(sock, cmd, wait=0.6):
    sock.sendall((cmd + CRLF).encode())
    time.sleep(wait)
    sock.settimeout(0.5)
    out = b""
    try:
        while True:
            d = sock.recv(65536)
            if not d:
                break
            out += d
    except socket.timeout:
        pass
    return out.decode("latin1")


def read_mem(sock, addr, n, batch=16):
    """liest n Byte ab addr: M-Befehle in Haeppchen zu je `batch` Zeilen senden (der UART-Puffer von Xemu laeuft sonst ueber und verwirft
    Befehle), dann die Antworten abwarten (je Zeile 16 Byte); fehlende Zeilen werden zu 0"""
    got = {}
    rx = re.compile(r":([0-9A-Fa-f]{7,8}):((?:[0-9A-Fa-f]{2})+)")
    for first in range(0, n, 16 * batch):
        offs = list(range(first, min(n, first + 16 * batch), 16))
        for attempt in range(3):
            want = [o for o in offs if addr + o not in got]
            if not want:
                break
            sock.sendall("".join("M%07X" % (addr + o) + CRLF for o in want).encode())
            buf = ""
            sock.settimeout(1.5)
            t_end = time.time() + 20
            while time.time() < t_end:
                try:
                    d = sock.recv(65536)
                except socket.timeout:
                    break
                if not d:
                    break
                buf += d.decode("latin1")
                for m in rx.finditer(buf):
                    got[int(m.group(1), 16)] = bytes.fromhex(m.group(2))
                if all(addr + o in got for o in want):
                    break
    out = bytearray()
    for i in range(0, n, 16):
        out += got.get(addr + i, bytes(16))
    return bytes(out[:n])


class Xemu:
    """with Xemu(prg, wartesekunden, ['-initattic', datei, '-8', d81]) as x: x.mem(0x4d000, 4000)"""

    def __init__(self, prg, wait, extra=(), port=None):
        self.port = int(port or os.environ.get("XMON_PORT", "4510"))
        args = [xemu_path(), "-headless", "-sleepless", "-fastboot", "-besure", "-rom", rom_path(), "-prg", prg, "-prgmode", "65",
                "-uartmon", ":%d" % self.port] + os.environ.get("XMON_ARGS", "").split() + list(extra)
        env = dict(os.environ, SDL_RENDER_DRIVER="software")
        self.p = subprocess.Popen(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
        time.sleep(wait)
        self.s = socket.create_connection(("127.0.0.1", self.port), timeout=10)
        mon(self.s, "")

    def mem(self, addr, n):
        return read_mem(self.s, addr, n)

    def vic(self, reg, n=1):
        """VIC-IV-Register $D0xx (reg = 0..$7F) ueber die flache Adresse"""
        return self.mem(0xFFD3000 + reg, n)

    def close(self):
        try:
            self.s.close()
        finally:
            self.p.kill()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()


def main():
    prg, wait = sys.argv[1], float(sys.argv[2])
    with Xemu(prg, wait) as x:
        for spec in sys.argv[3:]:
            a, n = spec.split(":")
            d = x.mem(int(a, 16), int(n, 16))
            for i in range(0, len(d), 16):
                print("%07X: %s" % (int(a, 16) + i, " ".join("%02X" % v for v in d[i:i + 16])))


if __name__ == "__main__":
    main()
