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
    if grep -q -e '^CLUSTERMAP_CARD_STANDARD_INSETS=' -e '^CLUSTERMAP_CARD_TOP_INSETS=' "$UNIT_CONF"; then
        p=`sed -n 's/^CLUSTERMAP_CARD_POSITION=\([a-z]*\)[ 	]*$/\1/p' "$UNIT_CONF" | tail -1`
        case "${p:-bottom}" in
            top|bottom) p="at the $p" ;;
            *)          p="moved" ;;
        esac
        echo "  turn card: $p (test), insets ${i:-unknown}"
    else
        echo "  turn card: as installed, insets ${i:-unknown}"
    fi
    s=`sed -n 's/^CLUSTERMAP_DPI_INSTALLED=\([0-9]*\)[ 	]*$/\1/p' "$UNIT_CONF" | tail -1`
    if [ -n "$s" ]; then
        echo "  map size: DPI ${d:-unknown} (test, installed $s)"
    else
        echo "  map size: DPI ${d:-unknown}"
    fi
fi
if grep -q 'libcarplay_cluster.so' "$CONFIG" 2>/dev/null; then
    echo "CarPlay map: left by an older package. Install again to remove it."
fi
if sh "$PKG/lsd_jar.sh" loaded NavActiveIgnore.jar; then echo "NavActiveIgnore: loaded (required)"
elif sh "$PKG/lsd_jar.sh" loaded CarPlayNavigationPatch.jar; then echo "NavActiveIgnore: loaded as CarPlay's CarPlayNavigationPatch.jar (same patch)"
else echo "NavActiveIgnore: not loaded (Install adds it on tested firmware)"; fi
j=/mnt/app/eso/hmi/lsd/jars/NavActiveIgnore.jar
if [ -r "$j" ] && sh "$PKG/lsd_jar.sh" loaded NavActiveIgnore.jar; then
    r=`wc -c < "$j" | sed 's/ //g'`
    case "$r" in
        "`wc -c < "$PKG/thirdparty/NavActiveIgnore.jar" 2>/dev/null | sed 's/ //g'`") echo "  cockpit map: 20 frames a second" ;;
        "`wc -c < "$PKG/thirdparty/NavActiveIgnore30.jar" 2>/dev/null | sed 's/ //g'`") echo "  cockpit map: 30 frames a second (test)" ;;
        *) echo "  cockpit map rate: not this package's jar ($r bytes)" ;;
    esac
fi
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
