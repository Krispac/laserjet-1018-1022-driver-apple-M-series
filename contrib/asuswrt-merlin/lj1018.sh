#!/bin/sh
# -------------------------------------------------------------------
# lj1018.sh - HP LaserJet 1018/1020 on an Asuswrt-Merlin router
#
# Uploads the printer firmware once every time the printer appears on
# the router's USB port (router boot or printer power-on), so the Mac
# can print over the network with zjsFirmware=Never.
# Optionally starts p910nd (Entware) as a raw print server on port 9101.
#
# Version: 2026.11.19.2
# Copyright (c) 2026 Nicola Ferralis - SPDX-License-Identifier: MIT
#
# Usage:  /jffs/scripts/lj1018.sh [firmware-file] [settle-seconds] &
#         (start it from /jffs/scripts/services-start)
# -------------------------------------------------------------------

FW=${1:-/jffs/sihp1018.dl}     # sihp1018.dl, sihp1020.dl or hp1020.acl-style .dl
SETTLE=${2:-15}                # seconds the printer must be present before upload
DEV=/dev/usb/lp0
FLAG=/tmp/.lj1018_fw           # /tmp is cleared at every router boot
POLL=5                         # seconds between checks
TIMEOUT=60                     # give up on an upload that blocks this long

if [ ! -f "$FW" ]; then
    logger -t lj1018 "firmware file $FW not found"
    exit 1
fi

# Optional raw print server on port 9101 (only if Entware's p910nd is
# installed; Entware may be mounted a while after boot, so wait for it).
( i=0
  while [ $i -lt 60 ] && [ ! -x /opt/sbin/p910nd ]; do i=$((i+1)); sleep 10; done
  [ -x /opt/sbin/p910nd ] && /opt/sbin/p910nd -b -f $DEV 1 ) &

# Send the firmware; kill the upload if the printer stops accepting data,
# so the USB port is not left blocked.
upload() {
    cat "$FW" > $DEV &
    pid=$!
    t=0
    while kill -0 $pid 2>/dev/null; do
        if [ $t -ge $TIMEOUT ]; then
            kill $pid 2>/dev/null
            logger -t lj1018 "firmware upload blocked for ${TIMEOUT}s and was stopped; switch the printer off and on"
            return 99
        fi
        sleep 1; t=$((t+1))
    done
    wait $pid
}

present=0                      # seconds the printer has been present

while true; do
    if [ -c $DEV ]; then
        if [ ! -f $FLAG ]; then
            # Wait until the printer has been present for SETTLE seconds:
            # right after power-on it appears on USB before it is ready.
            if [ $present -ge $SETTLE ]; then
                upload; rc=$?
                if [ $rc -eq 0 ]; then
                    logger -t lj1018 "firmware uploaded ($FW)"
                    touch $FLAG
                elif [ $rc -eq 99 ]; then
                    # Blocked: retrying would only block the port again.
                    # A power cycle clears the flag.
                    touch $FLAG
                else
                    logger -t lj1018 "cannot write to $DEV (busy?); retrying"
                fi
                present=0
            else
                present=$((present+POLL))
            fi
        fi
    else
        present=0
        rm -f $FLAG                    # printer switched off or unplugged
    fi
    sleep $POLL
done
