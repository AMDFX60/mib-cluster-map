#!/bin/sh
# The green menu's turn-card switch: test positions for the card on the
# cluster map, or back where the settings put it. Google Maps places its
# card at the top of the space the insets leave, centred, and the car
# somewhere in that space too, so each position is a set of insets: the card
# goes with the space, and the car may go with it. Measured on a Skoda
# 1010x376 cockpit at DPI 110 (a card about 400x105 in the 800x298 band),
# so only offered for that window. Changes only GAL_SECONDARY_INSETS in the
# unit's own copy of the settings, keeping the previous value to go back to;
# takes effect at the next reboot. An install from the card writes the
# card's insets again.
#
#   card_layout.sh bottom|left|right|hide|top
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
MARK="# Turn card position (switched by the green menu)"

# top,bottom,left,right in the margin band (800x298). With full frame the hook
# scales these by the pixel aspect, and with theme 0 each still fits the 15
# bytes UiConfig has.
# bottom: a 400x105 band, centred, 10 above the lower edge, between the two
#   lower segments.
# left, right: the standard space (40 from the top, 127 above the bottom) as
#   narrow as the card and against the left or right inset of 127, as far as
#   the standard insets go: the card about 73 off the centre.
# hide: a 160x60 box where the car sits with the standard insets, too small
#   for the card. Maps drops its arrival-time card when the space is too
#   short; whether it drops the turn card as well is the test.
case "$1" in
    bottom) NEW=183,10,200,200; WHAT="at the bottom" ;;
    left)   NEW=40,127,127,273; WHAT="top left" ;;
    right)  NEW=40,127,273,127; WHAT="top right" ;;
    hide)   NEW=75,163,320,320; WHAT="in a small space, to hide it" ;;
    top)    NEW=; WHAT="at the top" ;;
    *) echo "usage: $0 bottom|left|right|hide|top" >&2; exit 2 ;;
esac

# uiconfig_fits INSETS THEME PIXEL_ASPECT_E4
# Whether the hook can send these insets (video_sink_hook.c): at most 15
# bytes, 4 plus 2 for each inset up to 127 and 3 above, none for a 0, plus 2
# for theme 1 or 2; in full frame after scaling by the pixel aspect.
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
if [ "$1" != top ] && [ "$WINDOW" != 1010x376 ]; then
    echo "The cluster map window is ${WINDOW:-unknown}. The test positions are"
    echo "measured for a 1010x376 window (Skoda) only. Nothing changed."
    exit 3
fi
# The hook reads a key's first line.
NOW=`sed -n 's/^[ 	]*GAL_SECONDARY_INSETS[ 	]*=[ 	]*\([0-9]*,[0-9]*,[0-9]*,[0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
SAVED=`sed -n 's/^CLUSTERMAP_CARD_TOP_INSETS=\([0-9]*,[0-9]*,[0-9]*,[0-9]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
# The position in use; a saved value without one is beta10's bottom switch.
POS=top
if [ -n "$SAVED" ]; then
    POS=`sed -n 's/^CLUSTERMAP_CARD_POSITION=\([a-z]*\)[ 	]*$/\1/p' "$CONF" | tail -1`
    [ -n "$POS" ] || POS=bottom
fi
if [ "$1" = "$POS" ]; then
    echo "The turn card is already $WHAT. Nothing changed."
    exit 3
fi
if [ "$1" = top ]; then
    NEW=$SAVED
    KEEP=
else
    KEEP=${SAVED:-${NOW:-40,40,127,127}}
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
# Every line of these keys goes first, so each is in the file once.
if sed -e '/^[ 	]*GAL_SECONDARY_INSETS[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_CARD_TOP_INSETS[ 	]*=/d' \
       -e '/^[ 	]*CLUSTERMAP_CARD_POSITION[ 	]*=/d' \
       -e '/^# Turn card position (switched by the green menu)$/d' \
       "$CONF" > "$CONF.new" 2>/dev/null &&
   { echo
     echo "$MARK"
     echo "GAL_SECONDARY_INSETS=$NEW"
     if [ -n "$KEEP" ]; then
         echo "CLUSTERMAP_CARD_TOP_INSETS=$KEEP"
         echo "CLUSTERMAP_CARD_POSITION=$1"
     fi; } >> "$CONF.new" 2>/dev/null &&
   mv "$CONF.new" "$CONF" 2>/dev/null; then
    chmod 644 "$CONF" 2>/dev/null
else
    rm -f "$CONF.new" 2>/dev/null
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync
if [ "$1" = top ]; then
    echo "Turn card: back at the top. Insets $NEW."
else
    echo "Turn card: $WHAT (test). Insets $NEW, standard $KEEP."
    THEME=`sed -n 's/^GAL_SECONDARY_UI_THEME=\([0-9]\)[ 	]*$/\1/p' "$CONF" | head -1`
    PAR=`sed -n 's/^GAL_SECONDARY_PIXEL_ASPECT_RATIO_E4=\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
    if [ -z "$PAR" ] || [ "$PAR" -eq 0 ] || [ "$PAR" -gt 80000 ]; then PAR=10000; fi
    if ! uiconfig_fits "$NEW" "${THEME:-0}" "$PAR"; then
        echo "Note: with GAL_SECONDARY_UI_THEME=${THEME:-0} these insets do not fit the"
        echo "setting; the hook will cut each to 127. Theme 0 fits them."
    fi
    DPI=`sed -n 's/^[ 	]*GAL_SECONDARY_DPI[ 	]*=[ 	]*\([0-9][0-9]*\)[ 	]*$/\1/p' "$CONF" | head -1`
    if [ -n "$DPI" ] && [ "$DPI" != 110 ]; then
        echo "Note: the positions are measured at DPI 110; this unit has DPI $DPI,"
        echo "so the card is another size and may fit the space less well."
    fi
    echo "If the car or the road ahead ends up hidden, switch it back to the top."
fi
exit 0
