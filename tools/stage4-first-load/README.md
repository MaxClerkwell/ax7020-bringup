# Stage 4, erster Ladeversuch: Werkzeuge

Begleitcode zu `docs/walkthrough-stage4-first-load.md`.

| Datei | Läuft auf | Zweck |
|---|---|---|
| `nclisten.py` | Host | UDP-Listener auf 6666, schreibt Netconsole-Zeilen mit Zeitstempel in eine Datei |
| `netconsole-setup.sh` | Board | legt ein dynamisches Netconsole-Ziel über configfs an |
| `load-bitstream.sh` | Host | Hostkey aufräumen, Listener starten oder wiederverwenden, Netconsole einrichten, `.bin` hochladen, entkoppelt laden, Ergebnis zeigen |
| `jtag-regs.sh` | Host | devcfg-, SLCR- und GEM-Register über den AHB-AP lesen, ohne CPU-Halt |
| `jtag-logbuf.sh` | Host | Kernel-Ringpuffer aus dem DDR dumpen |
| `jtag-pc.sh` | Host | PC und CPSR beider Kerne, mit Symbol aus `System.map` |
| `jtag-lvlshftr-off.sh` | Host | Gegenprobe: Level-Shifter PL→PS abschalten |

Der Listener schreibt nach `$NETCONSOLE_LOG` (Standard: `./netconsole.log`) und
bleibt nach dem Skript laufen; ein zweiter Aufruf nutzt ihn weiter. Ein
erfolgreicher Lauf endet mit `AX7020: rc=0 state=operating` und einem Ping.

Typischer Ablauf:

```bash
tools/stage4-first-load/load-bitstream.sh 10.42.100.134 bitstream/blinky/blinky.bin
# Board stumm? Dann:
tools/stage4-first-load/jtag-regs.sh
tools/stage4-first-load/jtag-logbuf.sh
tools/stage4-first-load/jtag-pc.sh
```
