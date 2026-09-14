# Stage 2 nachgeholt: Images aus dem Netz, gestartet mit kexec

Protokoll vom 2026-09-10, direkt nach dem ersten Bitstream
(`walkthrough-stage4-first-load.md`). Werkzeuge: `tools/publish-image.sh`,
`tools/stage4-first-load/` für Netconsole und JTAG.

Ausgangslage: das Wartungssystem im Flash hat seit dem 31.08. einen Updater
(`ax7020-update`), der ein FIT per curl holt und mit kexec startet. Gebaut,
nie ausgeführt. `IMAGE_URL` war leer.

---

## 1. Ein Image-Server in einer Zeile

```bash
mkdir -p build/images && cp tftp/fitImage build/images/fitImage-maintenance-2026-08-31.bin
cd build/images && ln -s fitImage-maintenance-2026-08-31.bin latest
sha256sum fitImage-maintenance-2026-08-31.bin | cut -d' ' -f1 > latest.sha256
python3 -m http.server 8080 --bind 10.42.100.20
```

Als erstes Testobjekt das Wartungsimage selbst: wenn kexec funktioniert, kommt
dasselbe System mit Uptime null zurück.

## 2. Erster Lauf: Board tot

Auf dem Board `IMAGE_URL` und `EXPECT_SHA256` gesetzt, Updater entkoppelt
gestartet, Ausgabe nach `/dev/kmsg`. Der HTTP-Log zeigt den Abruf:

```
10.42.100.134 - - [10/Sep/2026 12:33:36] "GET /latest HTTP/1.1" 200 -
```

Danach: kein Ping, kein SSH. Und die Netconsole-Ausgabe war weg, weil der
Listener aus einem früheren Lauf noch den Port hielt und in eine gelöschte
Datei schrieb. Lehre für das Ladeskript: Listener wiederverwenden, Logpfad
absolut.

## 3. Diagnose über JTAG

```
A9_CPU_RST_CTRL 0x00000022
```

cpu1 im Reset mit gestopptem Takt: das ist der CPU-Hotplug, den
`machine_shutdown()` vor `kexec -e` macht. kexec ist also wirklich
gesprungen. Der Log-Puffer im DDR enthielt nur noch Zufallsdaten, das Ziel
des Sprungs hatte den Kernel überschrieben.

Die Antwort steht in den kexec-tools-Quellen im Yocto-Baum
(`kexec/arch/arm/kexec-zImage-arm.c`):

```c
int zImage_arm_probe(const char *UNUSED(buf), off_t UNUSED(len))
{
	/* Only zImage loading is supported. Do not check if
	 * the buffer is valid kernel image */
	return 0;
}
```

Es gibt auf 32-Bit-ARM keinen FIT-Loader, und die zImage-Prüfung nimmt jede
Datei. Der Updater hatte auf `d00dfeed` geprüft, also genau darauf, dass es
ein FIT ist. kexec hat das FIT als Kernel geladen und ist hineingesprungen.

## 4. Softreset reicht nicht

Zwei Resets über `PSS_RST_CTRL` per JTAG brachten das Board nicht hoch, der
BootROM parkte bei `0xffffff28` wie am 30.08. mit leerem Flash. Der
Flash-Chip hängt nicht am PS-Reset; Linux hatte ihn im 4-Byte-Adressmodus
gelassen, der BootROM liest mit 3 Byte. Power-Cycle.

## 5. Der Updater, zweite Fassung

Drei Dateien statt einem FIT, beschrieben von einem Manifest:

```
kernel zImage-20260910-105035            <sha256>
dtb    zynq-ax7020-20260910-105035.dtb   <sha256>
initrd initramfs-20260910-105035.cpio.gz <sha256>
```

`tools/publish-image.sh <webroot>` schreibt das aus dem Yocto-Deploy und
setzt `latest.manifest`. Der Updater holt Manifest und Dateien, prüft jede
SHA256, prüft die zImage-Magic an Offset 0x24 und die DTB-Magic, und ruft

```sh
kexec -l zImage --dtb=dtb --initrd=initrd --command-line="$CMDLINE"
```

`DRY_RUN=1` hört danach auf. Genau so getestet, Skript ins RAM des Boards
kopiert:

```
ax7020-update: kernel: 3974168 bytes, checksum ok
ax7020-update: dtb: 11651 bytes, checksum ok
ax7020-update: initrd: 9404953 bytes, checksum ok
ax7020-update: loading with kexec
ax7020-update: dry run, not executing
```

## 6. Der Sprung

Mit einer Kommandozeile, die dem neuen Kernel eine Netconsole samt Host-MAC
mitgibt (ohne MAC bleibt sie stumm, siehe Stage 3):

```
CMDLINE="console=ttyPS0,115200 ip=dhcp netconsole=6666@10.42.100.134/eth0,6666@10.42.100.20/f8:75:a4:40:9d:c3"
```

```
[13:03:22] ax7020-update: handing over - this system stops here
[13:03:28] Linux version 6.6.40-xilinx ...
[13:03:28] OF: fdt: Machine model: Alinx AX7020 board
[13:03:28] Kernel command line: console=ttyPS0,115200 ip=dhcp netconsole=...
[13:03:28] netconsole: network logging started
[13:03:28] IP-Config: Got DHCP answer from 10.42.0.1, my address is 10.42.100.134
[13:03:28] Run /init as init process
```

SSH um 13:03:45, `/proc/uptime` 21 s, `/proc/cmdline` die übergebene Zeile.
Sechs Sekunden vom alten zum neuen Kernel, ohne U-Boot, ohne Flash.

Nebenbefund: der UDP-Listener auf 6666 sieht auch U-Boots
Netconsole-Broadcasts beim Power-Cycle, also den kompletten Boot von SPL bis
`bootm`.

## 7. Dauerhaft machen

Das Rezept `ax7020-updater` bekommt ein Init-Skript (`rc5`, Priorität 99):
15 Sekunden nach dem Boot, entkoppelt, Ausgabe nach `/dev/kmsg`, nur wenn
`IMAGE_URL` gesetzt ist. Damit sucht das Board bei jedem Start nach
`latest.manifest`. Ein Fehler lässt das Wartungssystem stehen, per SSH
erreichbar.

Neues Wartungs-FIT bauen und ohne Jumper über `/dev/mtdblock3` schreiben,
wie in Stage 3, Kapitel 10.

## Merksätze

* **Eine Prüfung, die das Falsche bestätigt, ist schlimmer als keine.** Der
  Magic-Check auf `d00dfeed` garantierte genau das Format, das kexec nicht
  kann.
* **Den Loader lesen, nicht die Manpage.** `zImage_arm_probe()` ist vier
  Zeilen und erklärt alles.
* **Nach einem Crash den Chip mitdenken.** Der PS-Reset resettet den PS. Der
  Flash merkt sich seinen Adressmodus.
* **Netconsole mit MAC in die Kommandozeile.** Dann ist der neue Kernel von
  der ersten Zeile an sichtbar.
