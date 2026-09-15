# Betrieb: vom kalten Flash zur API, ohne Zutun

Protokoll vom 14. und 15.09.2026. Nach dem Handversuch
(`walkthrough-stage5-manual.md`) ging es darum, die Kette dauerhaft zu machen:
ein Image-Server im Firmennetz, ein Wartungssystem im Flash, das von dort das
neueste Image holt, und ein API-Image, in dem systemd den Dienst startet.

Ergebnis am 15.09. um 20:44, Power-Cycle, JTAG abgezogen, nichts weiter:

```
20:44:22  U-Boot: DHCP client bound to address 10.42.100.153
20:44:32  U-Boot: ## Loading kernel (any) from FIT Image at 02000000 ...
          Wartungssystem (systemd) -> ax7020-update.service -> Router -> kexec
          API-Image: GET http://10.42.100.156:8000/state -> {"state":"unknown",...}
          POST blinky.bit -> operating, LEDs blinken
```

---

## 1. Image-Server auf dem Router

nginx als Container auf AI-heimdall, nur an die LAN-Adresse gebunden,
Read-only, Root `/srv/ax7020-images`:

```bash
docker run -d --name ax7020-image-server --restart unless-stopped \
  -p 10.42.0.1:8080:80 \
  -v /srv/ax7020-images:/usr/share/nginx/html:ro \
  -v /etc/ax7020-image-server/default.conf:/etc/nginx/conf.d/default.conf:ro \
  --read-only --tmpfs /var/cache/nginx --tmpfs /var/run --tmpfs /tmp nginx:alpine
```

`default.conf` enthält nur `autoindex on` und `disable_symlinks off`. Jeder
Build bekommt ein Verzeichnis mit Zeitstempel, `ax7020-latest` ist ein
Symlink darauf. Das Board kennt nur diese eine URL:

```
http://10.42.0.1:8080/ax7020-latest/manifest
```

`tools/publish-image.sh AI-heimdall:/srv/ax7020-images` kopiert zImage, DTB
und initramfs aus dem Yocto-Deploy per scp, schreibt das Manifest mit den
SHA256 und setzt den Link um. `-i ax7020-initramfs` wählt statt des
API-Images das Wartungssystem.

## 2. Rezepte

Alles in `yocto/meta-ax7020`. Die Entscheidung mit den meisten Folgen zuerst:
`INIT_MANAGER = "systemd"` in `setup-build.sh`, für beide Images. Ein
Init-System für Wartung und Entwicklung, und der API-Dienst ist eine Unit.

**FastAPI ohne pdm-backend.** scarthgap hat keine Klasse für das
Build-Backend, das fastapi verlangt. Für reine Python-Wheels ist ein
Build-Schritt ohnehin sinnlos, ein Wheel ist ein Zip des
site-packages-Baums. `classes/pypi-wheel.bbclass` lädt das Wheel von PyPI,
prüft die SHA256 und entpackt es. Damit: fastapi 0.111.1, starlette 0.37.2,
uvicorn 0.30.6, click 8.1.7, python-multipart 0.0.9. pydantic, anyio und h11
kommen aus meta-python.

**uv** als vorgebautes statisches armv7-musl-Binary, Version und Hash
festgenagelt. Es liegt für Experimente im Image (`uv run --with …`), startet
aber nicht den Dienst: das würde bei jedem Boot Pakete aus dem Netz ziehen.

**ax7020-api**: `app.py` nach `/opt/ax7020-api`, `empty.bin` nach
`/lib/firmware`, `ax7020-api.service` mit `python3 -m uvicorn app:app` auf
Port 8000, aktiviert.

**ax7020-api-image**: core-image-minimal plus das Obige, dropbear,
Operator-Schlüssel. Ohne `ax7020-updater`, sonst würde das Image sich per
kexec endlos selbst nachladen. `INITRAMFS_MAXSIZE` auf 512 MB, das Rootfs
hat 138 MB unkomprimiert, 53 MB als cpio.gz.

**ax7020-updater** bekommt `ax7020-update.service` (oneshot, nach
network-online, 15 s Karenz) und als Standard die Router-URL.

## 3. Drei Bauten, drei Fehler

**INITRAMFS_MAXSIZE.** Yoctos Standardgrenze von 128 MB ist für Boards mit
viel weniger als 1 GiB gedacht. Grenze hoch, fertig.

**Roots Home.** Unter systemd liegt es in `/root`, unter sysvinit in
`/home/root`. Das Schlüssel-Rezept installierte nach `/home/root`, das
API-Image sagte `Permission denied (publickey)`. Aufgefallen vor dem Flashen
des Wartungssystems, das denselben Fehler gehabt hätte. Fix: `${ROOT_HOME}`.

**Das FIT passt nicht mehr.** Das systemd-Wartungssystem ist 21,4 MB, das
einkompilierte `bootcmd` las 16 MiB. U-Boot meldete

```
Bad FIT kernel image format! (err=-22)
```

und blieb am Prompt stehen, wo es am Firmen-Switch unerreichbar ist. Fix:
`sf read 0x2000000 0x340000 0x1800000`, 24 MiB, die Partition erlaubt 28,75.

## 4. Flashen ohne Jumper, mit Stolpersteinen

`tools/flash-fit.sh <ip> <image> [mtd]` lädt hoch, schreibt über
`/dev/mtdblockN`, liest zurück, vergleicht drei MD5. Zwei Details des
BusyBox im systemd-Image: `dd` kennt kein `conv=fsync`, `head` kein `-c`.
Die Rücklese läuft deshalb über `dd bs=4 count=`.

Das neue U-Boot kam per JTAG heiß in den DDR: laufendes U-Boot anhalten,
in SCTLR MMU und Caches abschalten, `load_image u-boot.bin 0x4000000`, PC
setzen, weiter. Es bootete das FIT, das Wartungssystem holte das API-Image,
und aus dem laufenden Linux wurde dann `u-boot.img` nach mtd1 geschrieben.

## 5. Der Power-Cycle, der keiner war

Nach dem Flashen parkte der BootROM bei `0xffffff28`, das lineare
QSPI-Fenster lieferte per JTAG nur Nullen, und ein Power-Cycle änderte
nichts, obwohl `REBOOT_STATUS` einen POR meldete. Der FT232H hält TMS auf
3,3 V und speist über die Schutzdioden der JTAG-Pins die Schiene des Boards.
Der Flash-Chip wurde nie stromlos. Mit abgezogenem USB-Adapter bootete das
Board sofort. Das ist dieselbe Physik wie am ersten Tag, als die JTAG-Kette
"ohne Strom" sichtbar war.

## 6. Adressen

Die Board-IP wechselte an einem Nachmittag von .134 über .144, .149, .153
auf .156. U-Boot und der Kernel ziehen je einen eigenen Lease. Die einzige
verlässliche Quelle ist die Inventar-API auf dem Router:

```bash
IP=$(curl -s http://10.42.0.1:8000/get_all_network_clients \
     | jq -r '.clients[] | select(.hostname=="ax7020" and .active_lease) | .ip')
curl http://$IP:8000/state
curl -F file=@/data/maxclerkwell/Repositories/alinx/bitstream/blinky/blinky.bit http://$IP:8000/bitstream
```

## 7. Was noch fehlt

* Authentifizierung für die API.
* Bitstream als vierte Manifest-Zeile, damit die PL nach dem Boot nicht leer
  ist.
* Ein Build-Stempel im Image, `/etc/ax7020-release`, damit man sieht, was
  läuft und woher es kam. Drei gleich aussehende Stände desselben Systems
  haben heute mehr Verwirrung gestiftet als jeder Bug.
* Blog-Artikel zu Stage 2, 4 und 5.

## Merksätze

* **Ein Init-System-Wechsel ist ein Distro-Wechsel.** Homes, Units,
  BusyBox-Optionen, Image-Größe: alles verschiebt sich ein wenig, und jedes
  Stück fällt einzeln auf.
* **Größen wachsen, Konstanten nicht.** Ein fest einkompilierter Lesebereich
  ist eine Zeitbombe, die beim nächsten dickeren Image hochgeht.
* **"Stromlos" ist eine Behauptung.** Der Adapter am JTAG-Port widerspricht.
* **Die IP ist kein Name.** Wer sie sich merkt, redet bald mit dem Nichts.
