# Printing through an Asuswrt-Merlin router

These steps let the Mac print wirelessly to a LaserJet 1018 or 1020 that
is plugged into the USB port of an ASUS router running Asuswrt-Merlin.
They were tested on an RT-AC68U and an RT-AC86U (386.14_2) with a
LaserJet 1018.

Two things happen:

- **Router.** `lj1018.sh` uploads the printer's firmware every time the
  printer appears on the USB port, both at router boot and after the
  printer is switched off and on. It uploads only once per power-on;
  a 1018 that already runs its firmware does not accept a second copy,
  and the upload then blocks the USB port. It waits until the printer
  has been on the USB port for 15 seconds before uploading: the printer
  appears on USB before it is ready, and an early upload blocks too.
- **Mac.** The driver (`rastertozjs`) produces the print data and sends
  it to the router's print server, which passes it to the printer
  unchanged.

## Router setup

1. In the router's web interface, go to **Administration → System** and
   set **Enable JFFS custom scripts and configs** to *Yes*.
2. Copy the firmware and the script to the router from the Mac. Adjust
   the user name and address.
   ```sh
   ssh admin@192.168.1.1 'cat > /jffs/sihp1018.dl' < sihp1018.dl
   ssh admin@192.168.1.1 'cat > /jffs/scripts/lj1018.sh' < contrib/asuswrt-merlin/lj1018.sh
   ```
3. On the router, make the script start at boot:
   ```sh
   chmod +x /jffs/scripts/lj1018.sh
   echo '/jffs/scripts/lj1018.sh /jffs/sihp1018.dl &' >> /jffs/scripts/services-start
   chmod +x /jffs/scripts/services-start
   ```
   If you already have another script that sends the firmware at boot,
   remove it: the printer must not receive the firmware twice.
4. Reboot the router, or switch the printer off and on and run
   `/jffs/scripts/lj1018.sh /jffs/sihp1018.dl &`. Then check:
   ```sh
   grep lj1018 /tmp/syslog.log      # "firmware uploaded"
   ls -l /tmp/.lj1018_fw            # flag file present
   ```
   The upload comes about 15–20 seconds after the printer is switched
   on. If your printer needs longer, pass the wait in seconds as a
   second argument: `/jffs/scripts/lj1018.sh /jffs/sihp1018.dl 25 &`.

## Mac setup

Install the driver (see the main README). Then point the printer at the
router's raw print server and turn the driver's own firmware upload off:

```sh
sudo lpadmin -p HP1018 -E -v 'socket://192.168.1.1:9100/?waiteof=false' \
  -P /Library/Printers/PPDs/Contents/Resources/HP-LaserJet-1018-hpzjs.ppd \
  -o zjsFirmware=Never
```

`waiteof=false` matters: the ASUS print server never closes the
connection, so without it every job stays at "Waiting for printer to
finish". Keep the `/` before `?`: recent macOS versions reject
`...:9100?waiteof=false` with `Bad device-uri`.

Check the result with `lpstat -v HP1018`. Adding the printer from
System Settings instead sets up an LPD queue
(`lpd://192.168.1.1/LPRServer`) and the driver's default firmware
setting; use the `lpadmin` command above.

### If the router's own print server does not work

Install Entware (`amtm` → Entware, needs a USB drive), then:

```sh
opkg install p910nd
```

`lj1018.sh` then also starts `p910nd` on port **9101**, which forwards
raw data both ways. Use `socket://192.168.1.1:9101/?waiteof=false` as the
printer address.

## Troubleshooting

- **The job stays at "Connected to printer", or is sent, and nothing
  prints.** The USB port is usually blocked by a firmware upload the
  printer did not accept. Check the log on the router:
  ```sh
  grep lj1018 /tmp/syslog.log
  ```
  "firmware upload blocked ... and was stopped" means the script gave
  up after 60 seconds. Switch the printer off and on; if it happens
  again, raise the wait (second argument, see *Router setup*). Older
  versions of `lj1018.sh` never give up: look for a `cat` that never
  exits with `ps | grep "cat " | grep -v grep`, run `killall cat`, and
  switch the printer off and on.
- **The queue address changed.** Run `lpstat -v HP1018` on the Mac. If
  it does not show `socket://192.168.1.1:9100/?waiteof=false`, run the
  `lpadmin` command from *Mac setup* again. This can happen after
  changing routers or re-adding the printer in System Settings.
- **`sh: can't create /dev/usb/lp0: Device or resource busy`.** Another
  process has the USB port open, usually a stuck `cat` as above. To
  find it:
  ```sh
  for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -q usb/lp && echo "$(basename $p): $(tr '\0' ' ' < $p/cmdline)"; done
  ```
- **Testing without CUPS.** Make a print file on the Mac and send it
  straight to the printer over SSH:
  ```sh
  PPD=/Library/Printers/PPDs/Contents/Resources/HP-LaserJet-1018-hpzjs.ppd
  cupsfilter -p $PPD -m application/vnd.cups-raster test.pdf > /tmp/page.ras 2>/dev/null
  PPD=$PPD /Library/Printers/hpzjs/filter/rastertozjs 1 $USER test 1 zjsFirmware=Never /tmp/page.ras > job.zjs
  ssh -x admin@192.168.1.1 'cat > /dev/usb/lp0' < job.zjs
  ```
  (`cupsfilter -m printer/foo` does not run the driver here and
  produces PostScript, which the printer ignores.)
