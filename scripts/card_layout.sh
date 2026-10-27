#!/bin/sh
# The green menu's turn-card switch: the card at the bottom of the cluster
# map, or back where the settings put it. Google Maps places its card at the
# top of the space the insets leave, so "bottom" leaves only a band as high
# as the card at the bottom, between the two lower segments; Maps decides
# where the car then goes. Measured on a Skoda 1010x376 cockpit at DPI 110,
# so only offered for that window. Changes only GAL_SECONDARY_INSETS in the
# unit's own copy of the settings, keeping the previous value to go back to;
# takes effect at the next reboot. An install from the card writes the
# card's insets again.
#
#   card_layout.sh bottom|top
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
# top,bottom,left,right in the margin band (800x298): a 400x105 band, centred,
# 10 above the lower edge. With full frame the hook scales these by the pixel
# aspect, and with theme 0 they still fit the 15 bytes UiConfig has.
BOTTOM_INSETS=183,10,200,200
MARK="# Turn card position (switched by the green menu)"

case "$1" in
    bottom|top) ;;
    *) echo "usage: $0 bottom|top" >&2; exit 2 ;;
esac

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi
WINDOW=`sed -n 's/^[ 	]*GAL_PLAYER_WINDOW[ 	]*=[ 	]*\([0-9]*x[0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
if [ "$1" = bottom ] && [ "$WINDOW" != 1010x376 ]; then
    echo "The cluster map window is ${WINDOW:-unknown}. The bottom position is"
    echo "measured for a 1010x376 window (Skoda) only. Nothing changed."
    exit 3
fi
# The hook reads a key's first line.
NOW=`sed -n 's/^[ 	]*GAL_SECONDARY_INSETS[ 	]*=[ 	]*\([0-9]*,[0-9]*,[0-9]*,[0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
SAVED=`sed -n 's/^CLUSTERMAP_CARD_TOP_INSETS=\([0-9]*,[0-9]*,[0-9]*,[0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
if [ "$1" = bottom ]; then
    if [ -n "$SAVED" ]; then
        echo "The turn card is already at the bottom. Nothing changed."
        exit 3
    fi
    NEW=$BOTTOM_INSETS
    KEEP=${NOW:-40,40,127,127}
else
    if [ -z "$SAVED" ]; then
        echo "The turn card is already where the settings put it. Nothing changed."
        exit 3
    fi
    NEW=$SAVED
    KEEP=
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
# Every line of these keys goes first, so each is in the file once.
if sed -e '/^[ 	]*GAL_SECONDARY_INSETS[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_CARD_TOP_INSETS[ 	]*=/d' \
       -e '/^# Turn card position (switched by the green menu)$/d' \
       "$CONF" > "$CONF.new" 2>/dev/null &&
   { echo
     echo "$MARK"
     echo "GAL_SECONDARY_INSETS=$NEW"
     if [ -n "$KEEP" ]; then echo "CLUSTERMAP_CARD_TOP_INSETS=$KEEP"; fi; } >> "$CONF.new" 2>/dev/null &&
   mv "$CONF.new" "$CONF" 2>/dev/null; then
    chmod 644 "$CONF" 2>/dev/null
else
    rm -f "$CONF.new" 2>/dev/null
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync
if [ "$1" = bottom ]; then
    echo "Turn card: at the bottom (test). Insets $NEW, were $KEEP."
    THEME=`sed -n 's/^GAL_SECONDARY_UI_THEME=\([0-9]\)[ 	]*$/\1/p' "$CONF" | head -1`
    if [ "$THEME" = 1 ] || [ "$THEME" = 2 ]; then
        echo "Note: GAL_SECONDARY_UI_THEME=$THEME leaves too little room for these"
        echo "insets; the hook will cut them to 127. Theme 0 fits them."
    fi
    echo "If the car or the road ahead ends up hidden, switch it back to the top."
else
    echo "Turn card: back at the top. Insets $NEW."
fi
exit 0
