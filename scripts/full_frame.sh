#!/bin/sh
# The green menu's picture switch: how Android Auto's frame fills the cluster
# map window, in the unit's own copy of the settings, so it can be tried in
# the car without editing the card and installing again.
#   720p  a 1280x720 frame whose margins leave exactly the window, shown 1:1
#         (CLUSTERMAP_720P=1, this fork's standard)
#   off   the 800x480 frame with margins, as upstream (the menu's comparison)
#   on    upstream's sharper map: the whole 800x480 frame with wide pixels
#         (no longer in this fork's menu)
# on and off end 720p. Changes only the window lines of that
# copy (lib_cluster_frame.sh); takes effect at the next reboot: gal reads the
# settings once at its start and hands the same frame values to every player
# it starts until then. An install from the card writes the card's setting
# again.
# From AMDFX60's fork (GPL-3.0).
#
#   full_frame.sh on|off|720p
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
. "$HERE/lib_cluster_frame.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"

case "$1" in
    on)   WANT=1; WANT_HD=0 ;;
    off)  WANT=0; WANT_HD=0 ;;
    720p) WANT=; WANT_HD=1 ;;
    *)    echo "usage: $0 on|off|720p" >&2; exit 2 ;;
esac

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi
WINDOW=`sed -n 's/^[ 	]*GAL_PLAYER_WINDOW[ 	]*=[ 	]*\([0-9][0-9]*x[0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
MAP_W=`echo "$WINDOW" | sed -n 's/^\([0-9]*\)x[0-9]*$/\1/p'`
MAP_H=`echo "$WINDOW" | sed -n 's/^[0-9]*x\([0-9]*\)$/\1/p'`
if [ -z "$MAP_W" ] || [ -z "$MAP_H" ] || [ "$MAP_W" -lt 320 ] || [ "$MAP_W" -gt 1920 ] ||
   [ "$MAP_H" -lt 160 ] || [ "$MAP_H" -gt 1080 ]; then
    echo "The settings copy names no cluster map window. Install again from the"
    echo "card (with the cockpit in map view), then use this switch."
    exit 1
fi
# Written only by an installer that has the full-frame hook and player; an
# older install would take the settings and draw a squeezed map.
if ! grep -q "^$FRAME_CONF_MARK\$" "$CONF" 2>/dev/null; then
    echo "The cluster map on the unit was installed by an older release, which"
    echo "cannot draw the sharper map. Choose \"Install cluster map\" from this"
    echo "card first, then use this switch. Nothing changed."
    exit 1
fi
# The 720p frame needs this package's hook and player, which write the
# CLUSTERMAP_720P line; an older install would ask the phone for 800x480
# with 720p margins.
if [ "$WANT_HD" = 1 ] && ! grep -q '^CLUSTERMAP_720P=' "$CONF" 2>/dev/null; then
    echo "The cluster map on the unit was installed by an older release, which"
    echo "cannot draw the 720p picture. Choose \"Install cluster map\" from this"
    echo "card first, then use this switch. Nothing changed."
    exit 1
fi
if [ "$WANT_HD" = 1 ] && ! frame_hd_ok $MAP_W $MAP_H; then
    echo "The cluster map window is ${MAP_W}x${MAP_H}, which a 1280x720 frame cannot"
    echo "hold with the margins the hook allows. Nothing changed."
    exit 3
fi
if [ "$WANT" = 1 ] && ! frame_full_ok $MAP_W $MAP_H; then
    echo "The cluster map window is ${MAP_W}x${MAP_H}, not wider than Android Auto's"
    echo "5:3 frame: the map already uses every line, so there is nothing to switch."
    exit 3
fi

NOW=`sed -n 's/^CLUSTERMAP_FULL_FRAME=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`
[ "$NOW" = 1 ] || NOW=0
NOW_HD=`sed -n 's/^CLUSTERMAP_720P=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`
[ "$NOW_HD" = 1 ] || NOW_HD=0
# 720p keeps the full-frame line as it is, for the way back.
[ -n "$WANT" ] || WANT=$NOW
if [ "$NOW_HD" = "$WANT_HD" ] && [ "$NOW" = "$WANT" ]; then
    if [ "$WANT_HD" = 1 ]; then
        echo "The 720p picture is already on. Nothing changed."
    elif [ "$1" = off ]; then
        echo "The 800x480 picture is already on. Nothing changed."
    else
        echo "Upstream's sharper map is already on. Nothing changed."
    fi
    exit 3
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
if ! frame_write_conf "$CONF" $MAP_W $MAP_H $WANT $WANT_HD; then
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync
if [ "$WANT_HD" = 1 ]; then
    echo "720p picture: ON (this fork's standard)."
    echo "Android Auto is asked for a 1280x720 frame with ${MARGIN_W}x${MARGIN_H} margins,"
    echo "so the phone draws the ${MAP_W}x${MAP_H} window's own pixels and the player"
    echo "shows them 1:1, without scaling. The hook scales DPI and insets to match."
    echo "If the cockpit shows no map after the reboot, choose the 800x480 picture."
elif [ "$WANT" = 1 ]; then
    echo "Sharper map: ON."
    echo "Android Auto now draws on the whole 800x480 frame, pixel aspect"
    echo "${PIXEL_ASPECT_E4}/10000, stretched to the ${MAP_W}x${MAP_H} window. The hook"
    echo "scales DPI and insets by the same ratio, so the map should keep its"
    echo "scale and the turn card its place. Compare with OFF after a reboot."
else
    echo "800x480 picture (to compare with 720p): ${MARGIN_W}x${MARGIN_H} margins,"
    echo "scaled to the ${MAP_W}x${MAP_H} window. The 720p entry goes back."
fi
echo "Hold the power button for 10 seconds to reboot the unit."
exit 0
