# Stage 4, erster Ladeversuch: ein offener Bitstream trifft den FPGA-Manager

Protokoll vom 2026-09-10. Die verwendeten Skripte liegen in
`tools/stage4-first-load/`. Ausgangslage: das Wartungssystem aus
`docs/walkthrough-stage3.md` läuft aus dem QSPI, das Board hängt im Firmennetz
unter `10.42.100.134`, JTAG (FT232H) ist angeschlossen. Ziel: den mit Yosys,
nextpnr-xilinx und prjxray gebauten Blinky (`bitstream/blinky/`) über den
Kernel-FPGA-Manager in die PL laden.

Ergebnis vorweg: der Bitstream ist korrekt und kommt vollständig in die PL an.
Danach hängt das Board, weil das Design keinen PS7-Block enthält und die PL
die direkten FIQ-Leitungen zu beiden Cortex-A9-Kernen treibt.

---

## 1. Board erreichbar?

```bash
curl -s http://10.42.0.1:8000/get_all_network_clients | jq '.clients[] | select(.hostname=="ax7020")'
ping -c 2 10.42.100.134
ssh root@10.42.100.134 'uptime; cat /sys/class/fpga_manager/fpga0/state'
```

`state` war `unknown`: seit dem Boot wurde noch nie ein Bitstream geladen.

**Stolperstein:** Nach jedem Neustart meldet SSH `REMOTE HOST IDENTIFICATION
HAS CHANGED`. Das Rootfs liegt im RAM, dropbear erzeugt bei jedem Boot einen
neuen Hostkey. Vor dem Verbinden:

```bash
ssh-keygen -R 10.42.100.134
```

## 2. Bitstream vorbereiten

`blinky.bit` ist das Ergebnis der offenen Flow (`bitstream/blinky/Makefile`).
Der Zynq-FPGA-Manager will kein `.bit`, sondern das Format, das bootgen
erzeugt: Header weg, jedes 32-Bit-Wort byte-gedreht. Das macht
`bitstream/bit2bin.py`:

```bash
cd bitstream/blinky && make blinky.bin
xxd -l 16 blinky.bin      # erwartet: ffff ffff ffff ffff 6655 99aa ...
md5sum blinky.bin
```

## 3. Kernel-Log sichtbar machen: dynamisches Netconsole

Der erste Versuch (ohne diesen Schritt) endete mit einem stummen Board und
keiner einzigen Meldung. Deshalb vor dem Laden den Kernel-Log per UDP auf den
Rechner lenken. Das Wartungssystem hat configfs und `CONFIG_NETCONSOLE`.

Listener auf dem Host (Port 6666):

```python
# nclisten.py
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(("0.0.0.0", 6666))
with open(sys.argv[1], "ab", buffering=0) as f:
    while True:
        d, a = s.recvfrom(65535)
        f.write(f"[{time.strftime('%H:%M:%S')} {a[0]}] ".encode() + d)
        if not d.endswith(b"\n"): f.write(b"\n")
```

```bash
setsid nohup python3 nclisten.py netconsole.log &
ip -br link show eno1        # MAC des Hosts, wird unten gebraucht
```

Auf dem Board (Reihenfolge ist Pflicht: erst alle Felder, dann `enabled`):

```sh
cd /sys/kernel/config/netconsole && mkdir host && cd host
echo eth0              > dev_name
echo 6666              > local_port
echo 6666              > remote_port
echo 10.42.100.134     > local_ip
echo 10.42.100.20      > remote_ip
echo f8:75:a4:40:9d:c3 > remote_mac
echo 1                 > enabled
echo "AX7020: netconsole test" > /dev/kmsg
```

Die Testzeile muss im `netconsole.log` auf dem Host auftauchen.

## 4. Upload und Laden

Die Datei per `cat` übertragen, `scp` fehlt im Minimal-Image. Das Laden
entkoppelt starten, damit die SSH-Sitzung nicht mit dem Board stirbt:

```bash
ssh root@10.42.100.134 'mkdir -p /lib/firmware; cat > /lib/firmware/blinky.bin; md5sum /lib/firmware/blinky.bin' < blinky.bin

ssh root@10.42.100.134 'echo "AX7020: loading blinky.bin" > /dev/kmsg;
  setsid nohup sh -c "echo blinky.bin > /sys/class/fpga_manager/fpga0/firmware;
  echo AX7020: rc=\$? state=\$(cat /sys/class/fpga_manager/fpga0/state) > /dev/kmsg" >/dev/null 2>&1 </dev/null &'
```

Beobachtet:

```
[11:16:15] AX7020: loading blinky.bin via fpga_manager now
[11:16:15] fpga_manager fpga0: writing blinky.bin to Xilinx Zynq FPGA Manager
```

Danach nichts mehr. Kein Ping, kein SSH, keine Panic-Meldung.

## 5. Diagnose über JTAG, ohne die CPU anzuhalten

Der Zynq-DAP hat einen AHB-AP (AP 0), über den sich physische Adressen lesen
lassen, während der Kernel weiterläuft. Registerlesen:

```bash
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg -c '
  init
  zynq.dap apreg 0 0x00 0x23000052
  foreach {n a} {DEVCFG_INT_STS 0xF800700C DEVCFG_STATUS 0xF8007014
                 FPGA_RST_CTRL 0xF8000240 LVL_SHFTR_EN 0xF8000900} {
    zynq.dap apreg 0 0x04 $a; echo "$n [zynq.dap apreg 0 0x0C]" }
  shutdown'
```

| Register | Wert | Bedeutung |
|---|---|---|
| `DEVCFG_INT_STS` | `0x50023004` | Bit 2 = `PCFG_DONE`: die PL ist fertig konfiguriert |
| `LVL_SHFTR_EN` | `0xf` | Treiber hat die Level-Shifter PL→PS eingeschaltet |
| `FPGA_RST_CTRL` | `0xf` | PL-Reset noch gesetzt, der Treiber kam nicht weiter |

In `drivers/fpga/zynq-fpga.c`, `zynq_fpga_ops_write_complete()`, folgen die
beiden letzten Schritte direkt aufeinander: erst Level-Shifter an, dann Reset
lösen. Der Kernel ist also genau dazwischen gestorben.

Kernel-Log aus dem DDR ziehen (Ringpuffer `__log_buf`, physisch = Adresse aus
`System.map` minus `0xC0000000`, Größe `1 << CONFIG_LOG_BUF_SHIFT`):

```bash
B=yocto/build/tmp/work/ax7020-poky-linux-gnueabi/linux-xlnx/6.6.40+git/linux-ax7020-standard-build
grep ' __log_buf$' $B/System.map          # c0a3e624 -> phys 0x00a3e624
grep LOG_BUF_SHIFT $B/.config             # 14 -> 16 KiB
openocd -f openocd/ft232h.cfg -f target/zynq_7000.cfg \
  -c 'target create zynq.axi mem_ap -dap zynq.dap -ap-num 0' \
  -c 'init; targets zynq.axi; dump_image logbuf.bin 0x00a3e624 0x4000; shutdown'
strings -n 8 logbuf.bin | tail
```

Der Log endet bei "writing blinky.bin". Kein Oops, kein Panic.

Programmzähler beider Kerne (dafür muss man kurz anhalten):

```bash
openocd ... -c 'init; targets zynq.cpu0; halt; reg pc; reg cpsr; resume;
                targets zynq.cpu1; halt; reg pc; reg cpsr; resume; shutdown'
```

```
cpu0: pc 0xc06270cc  cpsr 0x800e01d3   -> ct_nmi_enter / ct_nmi_exit
cpu1: pc 0xffff1300  cpsr 0x800301d1   -> vector_fiq + 0x1c, FIQ-Modus
```

Auflösen mit `System.map`; die Vektor-Stubs liegen bei `0xffff1000`
(`__stubs_start`), also `0xffff1300 - 0x1000 + __stubs_start`.

## 6. Interpretation

Linux auf ARM behandelt FIQ als NMI (`ct_nmi_enter`). Beide Kerne bearbeiten
ununterbrochen FIQs. Der Zynq-7000 hat direkte Leitungen von der PL zu den
Kernen, `IRQF2P[19:16]` = nFIQ und nIRQ für Core 0 und 1, die am GIC
vorbeigehen. Ein Vivado-Design enthält immer den PS7-Block, der diese
Eingänge definiert. Der nextpnr-Blinky enthält keinen PS7, die Leitungen sind
undefiniert. Solange die Level-Shifter aus sind, sieht der PS davon nichts.
Sobald der Treiber sie nach `PCFG_DONE` einschaltet, feuert die PL Dauer-FIQ.

Gegenprobe: Level-Shifter per JTAG wieder abschalten (SLCR ist im Kernel
entsperrt, `LOCKSTA` = 0):

```
zynq.dap apreg 0 0x04 0xF8000900; zynq.dap apreg 0 0x0C 0x0
```

Danach lief cpu0 in `die()`, cpu1 in `vector_dabt`. Der Kernel war schon zu
weit kaputt, aber er bewegte sich erst, als die PL abgetrennt war.

## 7. Konsequenz

Die offene Flow liefert einen gültigen Bitstream. Das Design muss den PS7
instanziieren und die Interrupt-Eingänge auf 0 legen. nextpnr-xilinx kennt die
Primitive (`PS7_PS7`) und bindet unbenutzte Eingänge auf Konstanten, siehe
`build/nextpnr-xilinx/xilinx/arch_place.cc`.

Nach jedem Hänger: Power-Cycle, dann `ssh-keygen -R` und von vorn.

## Merksätze

* **Ohne Log-Kanal nie einen Bitstream laden.** Netconsole über configfs
  kostet acht Zeilen und ist der Unterschied zwischen "stumm tot" und
  "letzte Meldung bekannt".
* **AHB-AP statt CPU-Halt.** `zynq.dap apreg 0 ...` und ein `mem_ap`-Target
  lesen Register und RAM, ohne den Kernel anzufassen. `mdw` nach `halt`
  braucht `phys`, sonst Data Abort, und die Session hinterlässt einen
  angehaltenen Kern mit `DSCR_DTR_RX_FULL`.
* **DDR hinter dem L2 kann veraltet sein.** Der Log-Puffer war brauchbar,
  `jiffies` nicht.
* **PCFG_DONE heißt nicht "fertig".** Danach kommen Level-Shifter und Reset,
  und erst dort zeigt sich, ob das Design mit dem PS zusammenpasst.

---

## 8. Zweiter Versuch mit PS7: es läuft

Eine Zeile im Verilog, wie im nextpnr-Beispiel `xilinx/examples/artyz7-20`:

```verilog
(* keep *) PS7 ps7_i();
```

nextpnr meldet beim Platzieren "Tieing unused PS7 inputs to constants". Neu
gebaut (`make blinky.bin`, md5 `7a840ea55dca311466b1a3bacb8887cb`), Board per
JTAG neu gestartet (SLCR-Unlock, dann `PSS_RST_CTRL` = 1 über den AHB-AP; der
Debug-Zugang blieb entgegen Gotcha 6 erhalten), geladen wie in Abschnitt 4:

```
AX7020: loading blinky.bin (PS7) via fpga_manager
fpga_manager fpga0: writing blinky.bin to Xilinx Zynq FPGA Manager
AX7020: rc=0 state=operating
```

| Register | Wert |
|---|---|
| `DEVCFG_INT_STS` | `PCFG_DONE` gesetzt |
| `LVL_SHFTR_EN` | `0xf` |
| `FPGA_RST_CTRL` | `0x0`, Reset gelöst |
| `/sys/class/fpga_manager/fpga0/state` | `operating` |

Das Board blieb dabei per SSH erreichbar. Damit ist die Kette
Yosys → nextpnr-xilinx → prjxray → `bit2bin.py` → SSH → FPGA-Manager
einmal komplett und ohne proprietäres Werkzeug durchlaufen. Stage 4 ist damit
erreicht.
