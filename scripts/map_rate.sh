#!/bin/sh
# The green menu's cockpit frame-rate switch. NavActiveIgnore.jar, which the
# installer adds on the Skoda, also sets how often the unit sends the cockpit
# its map picture: 20 frames a second, where the stock firmware sends 10
# (ChangeDataRateSequence calls setDataFrameRate(20) at full data rate). The
# package's NavActiveIgnore30.jar is the same jar with only that number at
# 30 (tools/make_rate_jar.py). The switch copies one or the other over the
# unit's jar; the Java interface reads it at the next reboot. lsd.sh is not
# touched. An install keeps the choice.
#
#   map_rate.sh 30|20
# Exit 0: switched, reboot. 3: nothing to change. Anything else: failed.
HERE=`dirname "$0"`
. "$HERE/lib_app_mount.sh"
PKG_ROOT="$HERE/.."
JAR="$APP_MOUNT/eso/hmi/lsd/jars/NavActiveIgnore.jar"
JAR20="$PKG_ROOT/thirdparty/NavActiveIgnore.jar"
JAR30="$PKG_ROOT/thirdparty/NavActiveIgnore30.jar"

case "$1" in
    30) SRC=$JAR30 ;;
    20) SRC=$JAR20 ;;
    *) echo "usage: $0 30|20" >&2; exit 2 ;;
esac
if [ ! -r "$JAR20" ] || [ ! -r "$JAR30" ]; then
    echo "This package has no NavActiveIgnore.jar and NavActiveIgnore30.jar. Nothing changed."
    exit 1
fi
if ! sh "$PKG_ROOT/lsd_jar.sh" loaded NavActiveIgnore.jar || [ ! -r "$JAR" ]; then
    if sh "$PKG_ROOT/lsd_jar.sh" loaded CarPlayNavigationPatch.jar; then
        echo "This unit loads CarPlayNavigationPatch.jar instead of NavActiveIgnore.jar;"
        echo "the switch only changes this package's NavActiveIgnore.jar. Nothing changed."
    else
        echo "NavActiveIgnore.jar is not loaded: install the cluster map first. Nothing changed."
    fi
    exit 3
fi
# The unit has no cmp or checksum tool; the two jars differ in size.
NOW=`wc -c < "$JAR" | sed 's/ //g'`
case "$NOW" in
    "`wc -c < "$JAR20" | sed 's/ //g'`") CUR=20 ;;
    "`wc -c < "$JAR30" | sed 's/ //g'`") CUR=30 ;;
    *) echo "The unit's NavActiveIgnore.jar ($NOW bytes) is not one of this package's"
       echo "two. Install the cluster map from this card first. Nothing changed."
       exit 3 ;;
esac
if [ "$CUR" = "$1" ]; then
    echo "The cockpit map is already set to $1 frames a second. Nothing changed."
    exit 3
fi

mount -uw "$APP_MOUNT" 2>/dev/null || { echo "Cannot remount $APP_MOUNT read-write. Nothing changed."; exit 1; }
APP_WRITABLE=1
trap app_mount_finish 0 1 2 15
if cp "$SRC" "$JAR.new" 2>/dev/null &&
   [ "`wc -c < "$SRC"`" = "`wc -c < "$JAR.new"`" ] &&
   mv "$JAR.new" "$JAR" 2>/dev/null; then
    chmod 644 "$JAR" 2>/dev/null
else
    rm -f "$JAR.new" 2>/dev/null
    echo "Could not write $JAR. Nothing changed."
    exit 1
fi
sync
echo "Cockpit map: $1 frames a second from the next reboot (was $CUR)."
if [ "$1" = 30 ]; then
    echo "If the cockpit map, or the car's own map, stutters, freezes or stays"
    echo "black, switch back to 20."
fi
exit 0
