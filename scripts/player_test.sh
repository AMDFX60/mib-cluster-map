#!/bin/sh
# The green menu's test steps (1.4.1-beta3), in the unit's own copy of the
# settings. After each: reboot, drive, "Save logs to SD", which notes the step
# (test_step.txt). Each step sets the whole test state, so the order does
# not matter; the next install from the card writes the card's settings
# again, so a test never stays by mistake.
#
#   player_test.sh step1|step2|step3|step4|step5|off
#     step1  software decoder, the first 2 minutes of the stream recorded
#            (GAL_PLAYER_RECORD=120; "Save logs to SD" takes it along)
#     step2  the unit's own video decoder (GAL_PLAYER_DECODER=hw)
#     step3  the same, its picture rectangle as x/y/width/height
#     step4  the same, output device 0
#     step5  software decoder, the phone may have 3 cockpit pictures in
#            flight, not 4 (GAL_SECONDARY_MAX_UNACKED=3)
#     off    back to the settings as installed
#
# The step is a block of lines at the end of the file. The player takes a
# setting's last line, so the block wins over the installed line above it,
# and removing the block brings that line back. The hook takes the first
# line, so step 5 only works while the file has no active
# GAL_SECONDARY_MAX_UNACKED line of its own (the shipped one is a comment).
# Exit 0: switched, reboot. Anything else: failed, nothing changed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
CONF="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"

case "$1" in
    step1) NAME="Step 1: software decoder, stream recorded" ;;
    step2) NAME="Step 2: hardware decoder" ;;
    step3) NAME="Step 3: hardware decoder, rectangle xywh" ;;
    step4) NAME="Step 4: hardware decoder, output 0" ;;
    step5) NAME="Step 5: software decoder, delay window 3" ;;
    off) NAME= ;;
    *) echo "usage: $0 step1|step2|step3|step4|step5|off" >&2; exit 2 ;;
esac

if [ ! -r "$CONF" ]; then
    echo "The cluster map is not installed: install it first."
    exit 1
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15

# Every earlier test block goes (also those of 1.4.1-beta2's switches).
sed -e '/^# Test switch [A-Z]* (green menu)$/,/^# end of test switch [A-Z]*$/d' "$CONF" > "$CONF.new" 2>/dev/null
RC=$?
if [ $RC -eq 0 ] && [ -n "$NAME" ]; then
    {
        echo "# Test switch STEP (green menu)"
        echo "# $NAME"
        case "$1" in
            step1) echo "GAL_PLAYER_RECORD=120" ;;
            step2) echo "GAL_PLAYER_DECODER=hw" ;;
            step3) echo "GAL_PLAYER_DECODER=hw"; echo "GAL_PLAYER_NVSS_RECT=xywh" ;;
            step4) echo "GAL_PLAYER_DECODER=hw"; echo "GAL_PLAYER_NVSS_OUTPUT=0" ;;
            step5) echo "GAL_SECONDARY_MAX_UNACKED=3" ;;
        esac
        echo "# end of test switch STEP"
    } >> "$CONF.new" 2>/dev/null
    RC=$?
fi
if [ $RC -eq 0 ] && [ -s "$CONF.new" ] && mv "$CONF.new" "$CONF" 2>/dev/null; then
    chmod 644 "$CONF" 2>/dev/null
else
    rm -f "$CONF.new" 2>/dev/null
    echo "Could not write $CONF. Nothing changed."
    exit 1
fi
sync

if [ -n "$NAME" ]; then
    echo "$NAME"
else
    echo "Back to standard: the settings as installed, no test step."
fi
if [ "$1" = step5 ]; then
    FIRST=`sed -n 's/^[ 	]*GAL_SECONDARY_MAX_UNACKED[ 	]*=[ 	]*\([0-9]*\).*$/\1/p' "$CONF" | head -1`
    if [ "$FIRST" != 3 ]; then
        echo "Note: an earlier GAL_SECONDARY_MAX_UNACKED=$FIRST line in the settings wins;"
        echo "the delay window stays $FIRST until that line is removed on the card."
    fi
fi
exit 0
