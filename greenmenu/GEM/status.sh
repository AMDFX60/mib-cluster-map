#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
CONFIG=/mnt/system/etc/eso/production/smartphone_integrator.json
LSD=/mnt/app/eso/hmi/lsd/lsd.sh
echo "Phone map on the digital cluster: status"
echo "Package folder: $PKG"
echo "Firmware train: $TRAIN"
if train_supported; then echo "  supported: yes ($SUPPORT_NOTE)"; else echo "  supported: NO, needs $SUPPORTED_TRAIN ($SUPPORT_NOTE)"; fi
if grep -q 'libgal_hook.so' "$CONFIG" 2>/dev/null; then echo "Hook: installed"; else echo "Hook: not installed"; fi
if [ -f /mnt/app/eso/lib/gal_dualscreen/libgal_hook.so ]; then echo "  library: present"; else echo "  library: missing"; fi
if [ -f /mnt/app/navigation/stream-player ]; then echo "  player: present"; else echo "  player: missing"; fi
UNIT_CONF=/mnt/app/eso/lib/gal_dualscreen/gal_dualscreen.conf
if [ -r "$UNIT_CONF" ]; then
    w=`sed -n 's/^GAL_PLAYER_WINDOW=\([0-9]*x[0-9]*\)[ 	]*$/\1/p' "$UNIT_CONF" | tail -1`
    m=`sed -n 's/^GAL_SECONDARY_MARGINS=\([0-9]*x[0-9]*\)[ 	]*$/\1/p' "$UNIT_CONF" | tail -1`
    if [ "`sed -n 's/^CLUSTERMAP_FULL_FRAME=\([01]\)[ 	]*$/\1/p' "$UNIT_CONF" | tail -1`" = 1 ]; then
        echo "  window ${w:-unknown}, sharper map: ON (whole frame)"
    else
        echo "  window ${w:-unknown}, sharper map: off (margins ${m:-unknown})"
    fi
    i=`sed -n 's/^GAL_SECONDARY_INSETS=\([0-9,]*\)[ 	]*$/\1/p' "$UNIT_CONF" | head -1`
    d=`sed -n 's/^GAL_SECONDARY_DPI=\([0-9]*\)[ 	]*$/\1/p' "$UNIT_CONF" | head -1`
    if grep -q '^CLUSTERMAP_CARD_TOP_INSETS=' "$UNIT_CONF"; then
        echo "  turn card: at the bottom (test), insets ${i:-unknown}, DPI ${d:-unknown}"
    else
        echo "  turn card: at the top, insets ${i:-unknown}, DPI ${d:-unknown}"
    fi
fi
if grep -q 'libcarplay_cluster.so' "$CONFIG" 2>/dev/null; then
    echo "CarPlay map: installed, `sed -n 's/.*"ALTSCREEN111_WIDTH=\([0-9]*\)", "ALTSCREEN111_HEIGHT=\([0-9]*\)".*/\1x\2/p' "$CONFIG"`"
    if [ -r /tmp/mibr-carplay111.state ]; then echo "  CarPlay cluster stream: `cat /tmp/mibr-carplay111.state`"; else echo "  CarPlay cluster stream: none yet (connect an iPhone)"; fi
else
    a=`wc -c < /mnt/app/eso/lib/libairplay.so 2>/dev/null | sed 's/ //g'`
    if [ "$a" = 703688 ]; then echo "CarPlay map: not installed (this unit's CarPlay library is supported)"; else echo "CarPlay map: not installed (CarPlay library ${a:-missing} bytes; supported: 703688)"; fi
fi
if sh "$PKG/lsd_jar.sh" loaded NavActiveIgnore.jar; then echo "NavActiveIgnore: loaded (required)"
elif sh "$PKG/lsd_jar.sh" loaded CarPlayNavigationPatch.jar; then echo "NavActiveIgnore: loaded as CarPlay's CarPlayNavigationPatch.jar (same patch)"
else echo "NavActiveIgnore: not loaded (Install adds it on tested firmware)"; fi
if sh "$PKG/lsd_jar.sh" loaded VCAndroidAuto.jar; then echo "Turn-by-turn arrows (VCAndroidAuto.jar): loaded. Installing the map turns this off."; else echo "Turn-by-turn arrows (VCAndroidAuto.jar): not loaded"; fi
echo "Java patch lines:"
grep -n 'Xbootclasspath/p' "$LSD" 2>/dev/null | sed 's|.*/p:||; s|\$BASE_DIR/lsd/jars/||g; s|"$||; s|^|  |'
if [ -r /tmp/gal_dualscreen.log ]; then
    echo "Last hook events:"
    grep -E "event=(init |firmware.verify|secondary.register|focus.state|player.spawn|focus.loss)" /tmp/gal_dualscreen.log | tail -6 | sed 's/^gal_dualscreen //' | cut -c1-110
else
    echo "No hook log yet (connect a phone after rebooting)."
fi
exit 0
