#!/bin/sh
# The green menu's map-size switch: GAL_SECONDARY_DPI in the unit's own copy
# of the settings, 10 smaller or larger at a time, or back to the value the
# install wrote. Lower draws the map, its text and the turn card smaller, so
# more map shows. With full frame the hook scales it by the pixel aspect
# (110 becomes 177 on 1010x376). Changes only that line, keeping the
# installed value to go back to; takes effect at the next reboot. An install
# from the card writes the card's DPI again.
#
#   map_size.sh smaller|larger|reset
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
MARK="# Map size (switched by the green menu)"
STEP=10
# The range owners have used, with some room either side (docs/Install.md).
MIN=80
MAX=170

case "$1" in
    smaller|larger|reset) ;;
    *) echo "usage: $0 smaller|larger|reset" >&2; exit 2 ;;
esac

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi
# The hook reads a key's first line; without one it uses its own 140.
NOW=`sed -n 's/^[ 	]*GAL_SECONDARY_DPI[ 	]*=[ 	]*\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
[ -n "$NOW" ] || NOW=140
SAVED=`sed -n 's/^CLUSTERMAP_DPI_INSTALLED=\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
case "$1" in
    smaller)
        NEW=`expr $NOW - $STEP || :`
        if [ "$NEW" -lt $MIN ]; then
            echo "DPI is $NOW; this switch goes down to $MIN. Nothing changed."
            exit 3
        fi ;;
    larger)
        NEW=`expr $NOW + $STEP`
        if [ "$NEW" -gt $MAX ]; then
            echo "DPI is $NOW; this switch goes up to $MAX. Nothing changed."
            exit 3
        fi ;;
    reset)
        if [ -z "$SAVED" ]; then
            echo "DPI is already the installed $NOW. Nothing changed."
            exit 3
        fi
        NEW=$SAVED ;;
esac
# Back at the installed value, nothing is left to go back to.
KEEP=${SAVED:-$NOW}
[ "$NEW" != "$KEEP" ] || KEEP=

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
# Every line of these keys goes first, so each is in the file once.
if sed -e '/^[ 	]*GAL_SECONDARY_DPI[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_DPI_INSTALLED[ 	]*=/d' \
       -e '/^# Map size (switched by the green menu)$/d' \
       "$CONF" > "$CONF.new" 2>/dev/null &&
   { echo
     echo "$MARK"
     echo "GAL_SECONDARY_DPI=$NEW"
     if [ -n "$KEEP" ]; then echo "CLUSTERMAP_DPI_INSTALLED=$KEEP"; fi; } >> "$CONF.new" 2>/dev/null &&
   mv "$CONF.new" "$CONF" 2>/dev/null; then
    chmod 644 "$CONF" 2>/dev/null
else
    rm -f "$CONF.new" 2>/dev/null
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync
if [ -n "$KEEP" ]; then
    echo "Map size: DPI $NEW (test), was $NOW, installed $KEEP."
else
    echo "Map size: DPI $NEW, as installed."
fi
PAR=`sed -n 's/^GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4=\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
if [ -n "$PAR" ] && [ "$PAR" -gt 0 ] && [ "$PAR" -le 80000 ] && [ "$PAR" != 10000 ]; then
    echo "With the sharper map the hook sends `expr \( $NEW \* $PAR + 5000 \) / 10000`."
fi
if grep -q -e '^CLUSTERMAP_CARD_STANDARD_INSETS=' -e '^CLUSTERMAP_CARD_TOP_INSETS=' "$CONF" && [ "$NEW" != 110 ]; then
    echo "Note: the turn card test positions are measured at DPI 110."
fi
exit 0
