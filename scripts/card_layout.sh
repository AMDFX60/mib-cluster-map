#!/bin/sh
# The green menu's turn-card setting: where Google Maps shows its green turn
# card on the cluster map, chosen with the insets (the space Maps keeps the
# car in). Measured on a Skoda 1010x376 cockpit at DPI 110 (139 at 720p), so
# only offered for that window.
#   hidden     no card: the space is too short for it (160x60, 25-45 percent
#              of the height); the car just below the middle, the arrival
#              time in a line at the bottom. The standard. Car-tested.
#   top_right  the same space 25 lines lower: Maps then shows the card in the
#              top right corner with the arrival time under it, and the car
#              lower down (car-tested, 1.2.2-beta4).
#   top_left   a try: the space as for top_right but moved right, so the free
#              room is on the left. Maps decides where its card goes; if it
#              stays on the right, the car is just further right.
# The choice is written to the unit's own copy of the settings and takes
# effect at the next reboot. The next install keeps it (CLUSTERMAP_TURN_CARD_
# MENU), unless CLUSTERMAP_TURN_CARD on the card says otherwise than hidden.
#
#   card_layout.sh hidden|top_right|top_left
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
MARK="# Turn card (chosen in the green menu; the next install keeps it)"

# top,bottom,left,right in the margin band (800x298). At 720p the hook scales
# these to the window (x1.2625); with theme 0 each still fits the 15 bytes
# UiConfig has (the top must stay at 100 or less for that).
# The same table is in enable_hook.sh (turn_card_insets).
case "$1" in
    hidden)    NEW=75,163,320,320;  WHAT="hidden" ;;
    top_right) NEW=100,138,320,320; WHAT="top right" ;;
    top_left)  NEW=100,138,480,160; WHAT="top left (a try)" ;;
    *) echo "usage: $0 hidden|top_right|top_left" >&2; exit 2 ;;
esac

# uiconfig_fits INSETS THEME SCALE_E4
# Whether the hook can send these insets (video_sink_hook.c): at most 15
# bytes, 4 plus 2 for each inset up to 127 and 3 above, none for a 0, plus 2
# for theme 1 or 2; after the hook's scaling.
uiconfig_fits()
{
    n=4
    case "$2" in 1|2) n=6 ;; esac
    for v in `echo "$1" | sed 's/,/ /g'`; do
        [ "$3" = 10000 ] || v=`expr \( $v \* $3 + 5000 \) / 10000 || :`
        if [ "$v" -gt 127 ]; then n=`expr $n + 3`
        elif [ "$v" -gt 0 ]; then n=`expr $n + 2`; fi
    done
    [ "$n" -le 15 ]
}

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi
WINDOW=`sed -n 's/^[ 	]*GAL_PLAYER_WINDOW[ 	]*=[ 	]*\([0-9]*x[0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
if [ "$WINDOW" != 1010x376 ]; then
    echo "The cluster map window is ${WINDOW:-unknown}. The turn card positions are"
    echo "measured for a 1010x376 window (Skoda) only. Nothing changed."
    exit 3
fi
NOW=`sed -n 's/^CLUSTERMAP_TURN_CARD=\([a-z_]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
INS=`sed -n 's/^[ 	]*GAL_SECONDARY_INSETS[ 	]*=[ 	]*\([0-9]*,[0-9]*,[0-9]*,[0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
if [ "$NOW" = "$1" ] && [ "$INS" = "$NEW" ]; then
    echo "The turn card is already $WHAT. Nothing changed."
    exit 3
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
# Every line of these keys goes first, so each is in the file once; the
# CLUSTERMAP_CARD_* lines are the test switch of 1.1.2 to 1.2.2-beta4.
if sed -e '/^[ 	]*GAL_SECONDARY_INSETS[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_TURN_CARD[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_TURN_CARD_MENU[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_CARD_STANDARD_INSETS[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_CARD_TOP_INSETS[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_CARD_POSITION[ 	]*=/d' \
       -e '/^# Turn card position (switched by the green menu)$/d' \
       -e '/^# Turn card (chosen in the green menu; the next install keeps it)$/d' \
       "$CONF" > "$CONF.new" 2>/dev/null &&
   { echo
     echo "$MARK"
     echo "GAL_SECONDARY_INSETS=$NEW"
     echo "CLUSTERMAP_TURN_CARD=$1"
     echo "CLUSTERMAP_TURN_CARD_MENU=$1"; } >> "$CONF.new" 2>/dev/null &&
   mv "$CONF.new" "$CONF" 2>/dev/null; then
    chmod 644 "$CONF" 2>/dev/null
else
    rm -f "$CONF.new" 2>/dev/null
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync
echo "Turn card: $WHAT. Insets $NEW."
THEME=`sed -n 's/^GAL_SECONDARY_UI_THEME=\([0-9]\)[ 	]*$/\1/p' "$CONF" | head -1`
SCALE=`sed -n 's/^GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4=\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
if [ -z "$SCALE" ] || [ "$SCALE" -eq 0 ] || [ "$SCALE" -gt 80000 ]; then SCALE=10000; fi
# At 720p the hook scales by window / band instead (1.2625 on 1010x376).
if [ "`sed -n 's/^CLUSTERMAP_720P=\([01]\)[ 	]*$/\1/p' "$CONF" | tail -1`" = 1 ]; then SCALE=12625; fi
if ! uiconfig_fits "$NEW" "${THEME:-0}" "$SCALE"; then
    echo "Note: with GAL_SECONDARY_UI_THEME=${THEME:-0} these insets do not fit the"
    echo "setting; the hook will cut the smallest above 127 to 127. Theme 0 fits them."
fi
DPI=`sed -n 's/^[ 	]*GAL_SECONDARY_DPI[ 	]*=[ 	]*\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
if [ -n "$DPI" ] && [ "$DPI" != 110 ]; then
    echo "Note: the positions are measured at DPI 110; this unit has DPI $DPI,"
    echo "so the card is another size and may sit differently."
fi
echo "The next install keeps this choice."
exit 0
