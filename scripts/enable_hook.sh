#!/bin/sh

# A non-interactive shell -- ssh "host command", or anything not started
# from a login shell -- does not inherit the firmware's PATH, so dirname,
# wc, grep and the unit's own binaries are simply absent and this script
# fails in confusing ways partway through. Set it before any external
# command runs, including the dirname below.
PATH=/proc/boot:/bin:/usr/bin:/usr/sbin:/sbin:/mnt/app/armle/bin:/mnt/app/armle/sbin:/mnt/app/armle/usr/bin:/mnt/app/armle/usr/sbin:$PATH
export PATH

# Install the preload environment into the supervisor-owned GAL child.
# This script never launches a second GAL process.

set -eu

CARD_ROOT=`cd "\`dirname "$0"\`" && pwd`
SYSTEM_MOUNT=/mnt/system
TARGET_CONFIG=$SYSTEM_MOUNT/etc/eso/production/smartphone_integrator.json
PERSISTENT_BACKUP=$TARGET_CONFIG.gal-dualscreen.original
JSONLINT=/mnt/app/eso/bin/jsonlint
# Match the QNX login/startup loader path. In particular, libiplcommon.so,
# libosal.so, and libutil.so are supplied by /lib, not /mnt/app/eso/lib.
VALIDATOR_LD_LIBRARY_PATH=/proc/boot:/lib:/lib/dll:/usr/lib:/mnt/app/root/lib-target:/mnt/app/usr/lib:/mnt/app/armle/lib:/mnt/app/armle/lib/dll:/mnt/app/armle/usr/lib:/eso/lib:/mnt/app/eso/lib
BACKUP_DIR="$CARD_ROOT/backups"
ORIGINAL="$BACKUP_DIR/smartphone_integrator.json.original"
LOG_DIR="$CARD_ROOT/logs"
DPI=140
DEBUG=0
SECOND_SINK=1
INJECT_META=1
AAP_MINOR=
CLUSTER_INPUT=1
OUTPUT=withhold
DISPLAYABLE=
LOG_PATH_REQUESTED=
STREAM=1
SYSTEM_WRITABLE=0
SYSTEM_TEMP=
KEEP_TBT=0
KEEP_NAVIGNORE=0
# This fork has no CarPlay map. Packages before 1.1.3 installed harman-f's
# CarPlay hook on units whose CarPlay library they knew; an install now takes
# what they left out again (the supervisor config is rebuilt from the original
# anyway).
CARPLAY_LEFTOVERS="libcarplay_cluster.so libcarplay_cluster.so.new carplay_cluster.sh"
PROFILES=$CARD_ROOT/profiles.conf

# The preload target lives on the internal /mnt/app partition instead of the
# SD card. The SD card mounts read-only again on every fresh boot unless
# something remounts it before GAL starts; unlike the hook's own log path,
# there is no automatic fallback for a missing LD_PRELOAD target -- the
# dynamic linker just silently proceeds without it, so if the SD card is not
# yet mounted at the exact moment smartphone_integrator launches GAL, the
# hook never loads at all, with no error anywhere. See lib_app_mount.sh
# (shared with disable_hook.sh) for the path constants and why /eso/lib
# was chosen over /navigation.
if [ -f "$CARD_ROOT/scripts/lib_app_mount.sh" ]; then
    . "$CARD_ROOT/scripts/lib_app_mount.sh"
elif [ -f "$CARD_ROOT/lib_app_mount.sh" ]; then
    . "$CARD_ROOT/lib_app_mount.sh"
else
    echo "ERROR: lib_app_mount.sh not found in $CARD_ROOT" >&2
    exit 1
fi

if [ ! -r "$CARD_ROOT/scripts/lib_unit.sh" ] || [ ! -r "$PROFILES" ] || \
   [ ! -r "$CARD_ROOT/scripts/lib_cluster_frame.sh" ]; then
    echo "ERROR: scripts/lib_unit.sh, lib_cluster_frame.sh or profiles.conf not found in $CARD_ROOT" >&2
    exit 1
fi
. "$CARD_ROOT/scripts/lib_unit.sh"
. "$CARD_ROOT/scripts/lib_cluster_frame.sh"

finish()
{
    if [ "$SYSTEM_WRITABLE" -eq 1 ]; then
        if [ -n "$SYSTEM_TEMP" ]; then
            rm -f "$SYSTEM_TEMP" 2>/dev/null || true
            SYSTEM_TEMP=
        fi
        mount -ur "$SYSTEM_MOUNT" 2>/dev/null || true
        SYSTEM_WRITABLE=0
    fi
    app_mount_finish
}

trap finish 0 1 2 15

usage()
{
    echo "Usage: $0 [--dpi NUMBER] [--debug|--no-debug]   (debug logging is off unless --debug)"
    echo "          [--no-second-sink] [--no-inject-meta] [--aap-minor N]"
    echo "          [--cluster-input]"
    echo "          [--output MODE] [--displayable N] [--log PATH]"
    echo
    echo "  Most settings come from a config FILE, which has no entry limit:"
    echo "  ClusterMap/gal_dualscreen.conf on the SD card, copied to the unit"
    echo "  by this script. Options given here are injected into the"
    echo "  environment and override the file."
    echo
    echo "  --keep-turn-by-turn  leave adi961's VCAndroidAuto.jar loaded. By"
    echo "                    default the installer removes its start-up line,"
    echo "                    because the cluster map fails when a route starts"
    echo "                    while that jar is active."
    echo "  --no-navignore    do not add the NavActiveIgnore patch when it is missing"
    echo "  --no-second-sink  register no second video service"
    echo "  --no-inject-meta  write no display_id/display_type fields"
    echo
    echo "  Bisect switches for the SERVICE_DISCOVERY_MISSING result: the"
    echo "  phone stopped answering discovery when the hook did BOTH. Run"
    echo "  each alone to find which the phone objects to."
    echo
    echo "  --aap-minor N     advertise AAP 1.N instead of the stock 1.2."
    echo "                    DHU negotiates 1.7 and gets a working cluster."
    echo "                    Risky: claims protocol this receiver does not"
    echo "                    implement. Verify Android Auto still works."
    echo
    echo "  --cluster-input   also advertise an InputSourceService for the"
    echo "                    cluster (display id 1). Proven necessary in a"
    echo "                    DHU subtractive test: removing it from a"
    echo "                    working two-display session stops the phone"
    echo "                    responding. Pair this with --aap-minor 7."
    echo
    echo "  --output MODE     what to do with the secondary sink's video:"
    echo "                      gal       forward to GAL. Reconfigures the one"
    echo "                                shared renderer and blanks the main"
    echo "                                screen. Stock path."
    echo "                      withhold  do not forward, do not decode. Frames"
    echo "                                still arrive and are counted; main"
    echo "                                screen untouched."
    echo "                      own       decode the frames ourselves into a"
    echo "                                private NvSS instance on the cluster"
    echo "                                displayable. Main screen untouched."
    echo "                      own-ack   NOT currently available for the"
    echo "                                secondary sink -- falls back to own."
    echo "                                (as own, but GAL is still told playback"
    echo "                                started, with the handler's renderer"
    echo "                                job stubbed out via a private vtable."
    echo "                    Default gal. Use own."
    echo "  --log PATH        write the hook log here. Omitted by default so"
    echo "                    the environment array stays short; the hook then"
    echo "                    uses its built-in path and falls back to"
    echo "                    /tmp/gal_dualscreen.log, which the status scripts"
    echo "                    search for anyway."
    echo "  --displayable N   cluster displayable to decode onto. Default 3;"
    echo "                    33 is the stock Kombi map window, already 800x480"
    echo "                    and already routed to the cluster by context 70."
    echo "  --no-secondary-render  alias for --output withhold. Do not forward"
    echo "                    playbackStart to GAL. GAL owns one renderer, so"
    echo "                    forwarding it blanks the main screen; withholding"
    echo "                    keeps the main screen and still counts frames."
    echo
    echo "  The cluster map window's size is read from the display manager at"
    echo "  install time. Where it is not 800x480, the phone is asked to leave"
    echo "  margins so its map has that shape, and the player fills the window."
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dpi)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            DPI=$2
            shift 2
            ;;
        --aap-minor)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            AAP_MINOR=$2
            case "$AAP_MINOR" in ''|*[!0-9]*) echo "--aap-minor needs a number" >&2; exit 2 ;; esac
            shift 2
            ;;
        --cluster-input) CLUSTER_INPUT=1; shift ;;
        --no-cluster-input) CLUSTER_INPUT=0; shift ;;
        --output)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            OUTPUT="$2"
            case "$OUTPUT" in
                own-ack)
                    # Accepted rather than rejected, because the hook falls
                    # back safely and the mode becomes real once the
                    # secondary gets a proper CVideoSinkCallbackHandler.
                    # But it must not look like it is doing something.
                    echo "NOTE: own-ack is not available for the secondary sink." >&2
                    echo "      This hook writes a CVideoSinkImpl into sink+0x38, so" >&2
                    echo "      playbackStart there dispatches to that class's slot 6" >&2
                    echo "      (ackFrames), not the callback handler's playbackStart" >&2
                    echo "      that own-ack stubs. The hook will refuse the patch and" >&2
                    echo "      run as 'own'. Use --output own." >&2
                    ;;
                own)
                    # The mode's SHAPE is right -- withhold from GAL,
                    # decode ourselves, ack ourselves -- but its decoder
                    # is NvSS, and the car proved on 2026-08-22 that a
                    # second NvSS stream cannot render: it dies at
                    # NvMediaVideoMixerBindOutput because GAL owns the
                    # only physical output. Accepted rather than rejected,
                    # because it becomes correct the moment the decoder is
                    # rebuilt on NvMedia + a KD stream, and the frame
                    # extraction and acking underneath it are already
                    # right. But nobody should spend a boot on it unaware.
                    echo "NOTE: --output own cannot display anything yet." >&2
                    echo "      Its decoder is NvSS, and a second NvSS stream cannot" >&2
                    echo "      render on this unit -- it fails at" >&2
                    echo "      NvMediaVideoMixerBindOutput because GAL owns the only" >&2
                    echo "      physical output. See the NvSS experiment in README.md." >&2
                    echo "      Expect own.open to succeed, a few own.decode lines, then" >&2
                    echo "      nothing on the cluster. The useful on-car test right now" >&2
                    echo "      is ./nvmedia_probe, which needs no install and no reboot." >&2
                    ;;
                gal|withhold) ;;
                *) echo "--output must be gal, withhold, own or own-ack" >&2; exit 2 ;;
            esac
            shift 2 ;;
        --log)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            HOOK_LOG_PATH="$2"; LOG_PATH_REQUESTED=1
            shift 2 ;;
        --displayable)
            [ $# -ge 2 ] || { usage >&2; exit 2; }
            DISPLAYABLE="$2"
            case "$DISPLAYABLE" in ''|*[!0-9]*) echo "--displayable needs a number" >&2; exit 2 ;; esac
            shift 2 ;;
        --stream) STREAM=1; shift ;;
        --no-stream) STREAM=0; shift ;;
        # Documented as "alias for --output withhold", and now implemented as
        # exactly that. It used to emit GAL_DUALSCREEN_SECONDARY_RENDER=0, a key
        # the hook stopped reading when the NvSS/own-render paths were removed --
        # so the flag spent one of the ~10 environment slots to say nothing.
        --no-secondary-render) OUTPUT=withhold; shift ;;
        --no-second-sink) SECOND_SINK=0; shift ;;
        --no-inject-meta) INJECT_META=0; shift ;;
        --debug) DEBUG=1; shift ;;
        --no-debug) DEBUG=0; shift ;;
        --keep-turn-by-turn) KEEP_TBT=1; shift ;;
        --no-navignore) KEEP_NAVIGNORE=1; shift ;;
        --no-carplay) shift ;;  # no CarPlay map any more; older menus pass it
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$DPI" in
    ''|*[!0-9]*) echo "DPI must be a positive integer" >&2; exit 2 ;;
esac
[ "$DPI" -gt 0 ] || { echo "DPI must be greater than zero" >&2; exit 2; }
[ -r "$CARD_ROOT/libgal_hook.so" ] || {
    echo "Missing $CARD_ROOT/libgal_hook.so" >&2
    exit 1
}
[ -r "$TARGET_CONFIG" ] || {
    echo "Missing persistent supervisor config: $TARGET_CONFIG" >&2
    exit 1
}
[ -x "$JSONLINT" ] || {
    echo "Required firmware validator is missing: $JSONLINT" >&2
    exit 1
}
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$TARGET_CONFIG" || {
    echo "jsonlint could not validate the existing persistent supervisor config" >&2
    echo "No file has been modified" >&2
    exit 1
}

mkdir -p "$BACKUP_DIR" "$LOG_DIR" || {
    echo "Cannot create $BACKUP_DIR / $LOG_DIR under $CARD_ROOT" >&2
    exit 1
}
# mkdir -p SUCCEEDS on an already-existing directory even when the
# filesystem is mounted read-only, so it cannot detect the SD card's
# default state after a power cycle. Relying on it meant the install got
# as far as staging the preload, then failed on the first real write with
# "cannot create ...: Read-only file system" and reported the misleading
# "Could not locate children.gal.envs" -- pointing at the config's
# structure rather than at the mount. Probe with an actual write, which
# is the thing that has to work, and fail here with the real reason.
WRITE_PROBE="$LOG_DIR/.write_probe.$$"
if ! : > "$WRITE_PROBE" 2>/dev/null; then
    echo "Cannot write $CARD_ROOT -- it is mounted read-only." >&2
    echo "The SD card returns to read-only on every boot; run this first:" >&2
    echo "    mount -uw $CARD_ROOT" >&2
    exit 1
fi
rm -f "$WRITE_PROBE"

# Stage the preload target on the internal partition before touching the
# persistent supervisor config at all: if this fails, nothing has been
# modified yet, matching the fail-closed pattern used throughout this
# script. Always copy fresh rather than trusting an existing copy, so an
# updated libgal_hook.so on the SD card is never silently ignored.
#
# On a repeat install, PRELOAD_SO_REAL is not a fresh file -- it is the
# exact path the live LD_PRELOAD alias already resolves to, in active use
# by whatever GAL session is currently running. Stage to a temp name in
# the same directory, verify it, and only then atomically rename it onto
# the live path -- the same stage-then-atomic-rename shape used for
# TARGET_CONFIG below -- so an interrupted or partial copy (disk full,
# power loss mid-write) can never leave that live, already-relied-upon
# file half-written. A direct cp onto the live path could.
mount -uw "$APP_MOUNT" 2>/dev/null || {
    echo "Cannot remount $APP_MOUNT read-write" >&2
    exit 1
}
APP_WRITABLE=1
mkdir -p "$PRELOAD_WRITE_DIR" || {
    echo "Cannot create $PRELOAD_WRITE_DIR" >&2
    exit 1
}
# Belt-and-braces alongside the file-level chmod below: mkdir -p honors
# umask for the directory's own mode bits, and this directory needs to
# stay traversable regardless of the invoking shell's umask.
chmod 755 "$PRELOAD_WRITE_DIR" 2>/dev/null || true
PRELOAD_SO_TEMP="$PRELOAD_WRITE_DIR/libgal_hook.so.new.$$"
cp "$CARD_ROOT/libgal_hook.so" "$PRELOAD_SO_TEMP" || {
    rm -f "$PRELOAD_SO_TEMP"
    echo "Could not stage libgal_hook.so to $PRELOAD_SO_TEMP" >&2
    exit 1
}
chmod 755 "$PRELOAD_SO_TEMP" 2>/dev/null || true
# Byte-for-byte where available: a same-size but corrupted copy would pass
# a size-only check. This unit's firmware image ships neither cmp nor
# diff at all -- confirmed against the full extracted firmware tree, not
# just a PATH gap on this shell -- so probe for cmp and fall back to the
# size-only comparison this project used before cmp was assumed available,
# rather than hard-failing every install on a tool this target never had.
if command -v cmp >/dev/null 2>&1; then
    cmp -s "$CARD_ROOT/libgal_hook.so" "$PRELOAD_SO_TEMP" || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Staged libgal_hook.so does not match $CARD_ROOT/libgal_hook.so" >&2
        exit 1
    }
else
    SRC_SIZE=`wc -c < "$CARD_ROOT/libgal_hook.so"` || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Could not read size of $CARD_ROOT/libgal_hook.so" >&2
        exit 1
    }
    DST_SIZE=`wc -c < "$PRELOAD_SO_TEMP"` || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Could not read size of staged $PRELOAD_SO_TEMP" >&2
        exit 1
    }
    [ "$SRC_SIZE" -eq "$DST_SIZE" ] || {
        rm -f "$PRELOAD_SO_TEMP"
        echo "Staged libgal_hook.so size ($DST_SIZE) does not match $CARD_ROOT/libgal_hook.so ($SRC_SIZE)" >&2
        exit 1
    }
    echo "Note: cmp is not available on this unit; verified staged copy by size only."
fi
mv "$PRELOAD_SO_TEMP" "$PRELOAD_SO_REAL" || {
    rm -f "$PRELOAD_SO_TEMP"
    echo "Could not atomically install $PRELOAD_SO_REAL" >&2
    exit 1
}
# Confirm the short /eso alias actually resolves to what was just written,
# not just that the write under /mnt/app/eso succeeded -- catches a wrong
# assumption about the /eso alias before it ever reaches the persistent
# config, rather than silently deploying a dead LD_PRELOAD path.
[ -r "$PRELOAD_SO_ALIAS" ] || {
    echo "$PRELOAD_SO_ALIAS is not readable through the short alias path" >&2
    echo "Wrote to $PRELOAD_WRITE_DIR but /eso does not resolve to it as expected" >&2
    exit 1
}
# Install libdmdt_flush.so interposer to PRELOAD_WRITE_DIR and /mnt/app/eso/lib
if [ -r "$CARD_ROOT/lib/libdmdt_flush.so" ]; then
    cp "$CARD_ROOT/lib/libdmdt_flush.so" "$PRELOAD_WRITE_DIR/libdmdt_flush.so" 2>/dev/null || true
    chmod 755 "$PRELOAD_WRITE_DIR/libdmdt_flush.so" 2>/dev/null || true
    cp "$CARD_ROOT/lib/libdmdt_flush.so" "$APP_MOUNT/eso/lib/libdmdt_flush.so" 2>/dev/null || true
    chmod 755 "$APP_MOUNT/eso/lib/libdmdt_flush.so" 2>/dev/null || true
    echo "Installed dmdt flush interposer to: $PRELOAD_WRITE_DIR/libdmdt_flush.so"
fi

# The profiles the hook matches gal against, and the script the player runs
# when the cockpit's map window is not the size in the settings.
cp "$PROFILES" "$PRELOAD_WRITE_DIR/profiles.conf" && chmod 644 "$PRELOAD_WRITE_DIR/profiles.conf" || {
    echo "Could not copy profiles.conf to $PRELOAD_WRITE_DIR" >&2
    exit 1
}
cp "$CARD_ROOT/scripts/window_fix.sh" "$PRELOAD_WRITE_DIR/window_fix.sh" 2>/dev/null || true
chmod 755 "$PRELOAD_WRITE_DIR/window_fix.sh" 2>/dev/null || true
cp "$CARD_ROOT/scripts/lib_cluster_frame.sh" "$PRELOAD_WRITE_DIR/lib_cluster_frame.sh" 2>/dev/null || true
chmod 644 "$PRELOAD_WRITE_DIR/lib_cluster_frame.sh" 2>/dev/null || true

TRAIN=unknown
for f in /net/rcc/dev/shmem/version.txt /dev/shmem/version.txt; do
    if [ -r "$f" ]; then
        TRAIN=`grep "Current train" "$f" | sed 's/Current train = //' | sed -e 's|["'"'"']||g' | sed 's/\r//'`
        break
    fi
done

# The settings owners have tested, by make (profiles.conf): read here, before
# the settings copy, which needs the make's "auto" values; used again below.
unit_make "$PROFILES" "$TRAIN" || :

# Internal copy of the settings file: the hook reads the SD card first and
# falls back to this one, so the tuned values still apply without the card.
# Every setting below is read from this copy, which is written without the
# carriage returns a Windows editor adds: with them none of the installer's
# own readers matched a line, while the hook (which strips them) still did,
# so a CRLF file was half-applied without a word.
#
# The owner's own lines from the last install are put back where this card
# still has the shipped default (scripts/lib_keep_settings.sh), with one
# exception: on the SAME package as the last install, a setting whose line
# on the card has changed since that install is the owner's edit and is used
# as it is, also when the edit was putting it back to the shipped value
# (#19: FRAME_SCALE commented out on the card, yet 135 came back each time).
CONF_COPY="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
OWNER_SAVED="$PRELOAD_WRITE_DIR/gal_dualscreen.owner.conf"
CARD_LAST="$PRELOAD_WRITE_DIR/gal_dualscreen.card.conf"
CONF_DEFAULT="$CARD_ROOT/scripts/gal_dualscreen.default.conf"
PKG_SAVED="$PRELOAD_WRITE_DIR/package_version.txt"
PKG_NOW=`head -1 "$CARD_ROOT/scripts/package_version.txt" 2>/dev/null || :`
PKG_LAST=`head -1 "$PKG_SAVED" 2>/dev/null || :`
CARD_SAVED_NEW=
if [ -r "$CARD_ROOT/gal_dualscreen.conf" ]; then
    if awk '{ sub(/\r$/, ""); print }' "$CARD_ROOT/gal_dualscreen.conf" > "$CONF_COPY.card" 2>/dev/null &&
       [ -s "$CONF_COPY.card" ]; then
        :
    else
        cp "$CARD_ROOT/gal_dualscreen.conf" "$CONF_COPY.card" 2>/dev/null || true
    fi
    KEEP_SETTINGS=`sed -n 's/^CLUSTERMAP_KEEP_SETTINGS=\([01]\)[ 	]*$/\1/p' "$CONF_COPY.card" 2>/dev/null | tail -1`
    KEEP_FROM=
    if [ "$KEEP_SETTINGS" != 0 ] && [ -r "$CONF_DEFAULT" ] && [ -r "$CARD_ROOT/scripts/lib_keep_settings.sh" ] &&
       [ -r "$OWNER_SAVED" ]; then
        . "$CARD_ROOT/scripts/lib_keep_settings.sh"
        if [ -n "$PKG_NOW" ] && [ "$PKG_NOW" = "$PKG_LAST" ] && [ -r "$CARD_LAST" ]; then
            keep_unedited "$OWNER_SAVED" "$CONF_COPY.card" "$CARD_LAST" > /tmp/clustermap_owner_prev.conf 2>/dev/null &&
                KEEP_FROM=saved
        else
            cp "$OWNER_SAVED" /tmp/clustermap_owner_prev.conf 2>/dev/null && KEEP_FROM=saved
        fi
    elif [ "$KEEP_SETTINGS" != 0 ] && [ ! -r "$OWNER_SAVED" ] && [ -r "$CONF_COPY" ]; then
        # Installed by a release that saved no owner lines (v1.1.1, beta18 or
        # older). Its copy cannot tell the owner's lines from the ones that
        # installer wrote or shipped, so nothing is carried over.
        echo "Settings: the previous install was from an older release; its settings are not carried over. This card's gal_dualscreen.conf is used."
    fi
    # The card's file as it is now, for the comparison at the next install.
    # Moved into place only when this install has finished.
    cp "$CONF_COPY.card" "$CARD_LAST.new" 2>/dev/null && CARD_SAVED_NEW=1
    mv "$CONF_COPY.card" "$CONF_COPY" 2>/dev/null || cp "$CARD_ROOT/gal_dualscreen.conf" "$CONF_COPY" 2>/dev/null || true
    chmod 644 "$CONF_COPY" 2>/dev/null || true
    echo "Installed settings copy: $CONF_COPY"
    if [ -n "$KEEP_FROM" ]; then
        KEPT=`keep_apply "$CONF_COPY" /tmp/clustermap_owner_prev.conf "$CONF_DEFAULT"` || {
            KEPT=; echo "WARNING: could not carry over your previous settings; using the card's as they are." >&2; }
        if [ -n "$KEPT" ]; then
            echo "Kept from your previous install (change them on the card to override, or CLUSTERMAP_KEEP_SETTINGS=0 for a clean install):"
            echo "$KEPT" | sed 's/^/  /'
        fi
    elif [ "$KEEP_SETTINGS" = 0 ]; then
        echo "CLUSTERMAP_KEEP_SETTINGS=0: installed the card's settings only."
    fi
    rm -f /tmp/clustermap_owner_prev.conf 2>/dev/null
    # The owner's lines for the next install, before this installer adds its own.
    if [ -r "$CONF_DEFAULT" ] && [ -r "$CARD_ROOT/scripts/lib_keep_settings.sh" ]; then
        . "$CARD_ROOT/scripts/lib_keep_settings.sh"
        keep_owner_lines "$CONF_COPY" "$CONF_DEFAULT" > "$OWNER_SAVED.new" 2>/dev/null &&
            mv "$OWNER_SAVED.new" "$OWNER_SAVED" 2>/dev/null || rm -f "$OWNER_SAVED.new" 2>/dev/null
    fi
else
    echo "NOTE: no gal_dualscreen.conf beside this script; the hook will run on built-in defaults."
fi
# CLUSTERMAP_KEEP_ARROWS=1: keep the turn-arrows jar with the map, adding it
# when missing. On SEAT the two work together; on VW the map goes blank when
# a route starts.
WITH_ARROWS=0
if [ "`sed -n 's/^CLUSTERMAP_KEEP_ARROWS=\([01]\)[ 	]*$/\1/p' "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`" = 1 ]; then
    WITH_ARROWS=1; KEEP_TBT=1
fi

# The settings owners have tested, by make (unit_make above): the cockpit
# map window, then DPI and insets. Used for "auto" in gal_dualscreen.conf
# (#41) and, for the window, when the display manager does not list it (#15,
# #19: a SEAT and a Skoda drew stripes in an 800x480 window). Values:
# docs/Install.md.

# The cluster map window. The cluster's encoder expects the window it shows
# to be this size; an 800x480 window on a cluster whose map window is, say,
# 1010x376 arrives as stripes (SEAT P4708, issue #4). So the player opens its
# window at the stock Kombi map window's size: Android Auto's 800x480 frame
# is drawn into it at its own shape. dmdt gd prints one line per window: ID, type, "W x H", buffers,
# name; 33 is the stock Kombi map.
MAP_SIZE=`( cd /eso && LD_PRELOAD="$PRELOAD_WRITE_DIR/libdmdt_flush.so" \
    LD_LIBRARY_PATH=/eso/lib:/lib:/usr/lib IPL_CONFIG_DIR=/etc/eso/production \
    ./bin/apps/dmdt gd ) 2>/dev/null | awk '
    $1 == 33 {
        for (i = 2; i < NF; i++) if ($i == "x") { print $(i - 1) "x" $(i + 1); exit }
    }'`
# A GAL_PLAYER_WINDOW line in the card's settings is used only when the
# display manager does not list the window (#19: a SEAT that never reported
# its 1010x376, with its own map on the cockpit at every install).
MAP_SET=`sed -n 's/^GAL_PLAYER_WINDOW=\([0-9]*x[0-9]*\)[ 	]*$/\1/p' \
    "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`
MAP_FROM="display manager"
MAP_GUESSED=
if [ -z "$MAP_SIZE" ] && [ -n "$MAP_SET" ]; then
    MAP_SIZE=$MAP_SET
    MAP_FROM="GAL_PLAYER_WINDOW in gal_dualscreen.conf"
fi
if [ -z "$MAP_SIZE" ] && [ -n "$CAR_WINDOW" ]; then
    MAP_SIZE=$CAR_WINDOW
    MAP_FROM="usual size on $CAR_MAKE; the display manager did not list it"
    MAP_GUESSED=1
fi
MAP_W=`echo "$MAP_SIZE" | sed -n 's/^\([0-9][0-9]*\)x[0-9][0-9]*$/\1/p'`
MAP_H=`echo "$MAP_SIZE" | sed -n 's/^[0-9][0-9]*x\([0-9][0-9]*\)$/\1/p'`
if [ -n "$MAP_W" ] && [ -n "$MAP_H" ] && [ "$MAP_W" -ge 320 ] && [ "$MAP_W" -le 1920 ] && \
   [ "$MAP_H" -ge 160 ] && [ "$MAP_H" -le 1080 ]; then
    echo "Cluster map window: ${MAP_W}x${MAP_H} (from the $MAP_FROM)"
    if [ -n "$MAP_GUESSED" ]; then
        # #52: a VW cockpit with a 1010x376 window took the 800x480 guess.
        echo "  This size is a guess, and not every $CAR_MAKE cockpit has it. If the map"
        echo "  does not appear, put the cockpit in map view with the car's own"
        echo "  navigation and install again, or set GAL_PLAYER_WINDOW in"
        echo "  gal_dualscreen.conf (dmdt_gd.txt in Save logs lists window 33)."
    fi
else
    MAP_W=800; MAP_H=480
    echo "Cluster map window: not reported by the display manager; using 800x480."
    echo "  The stock map window is only listed once the cockpit has shown its"
    echo "  own map. If your cockpit map is not 800x480, the picture can arrive"
    echo "  as stripes or the wrong shape. To get the right size: put the"
    echo "  cockpit in map view with the car's own navigation, then run this"
    echo "  install again. If it still is not listed, set the size yourself in"
    echo "  gal_dualscreen.conf, e.g. GAL_PLAYER_WINDOW=1010x376 on SEAT and Skoda."
fi
# Android Auto's frame is always 800x480: the phone is asked to leave
# margins so the rest (the band) has the window's shape, none for an 800x480
# window, or with CLUSTERMAP_FULL_FRAME=1 a pixel aspect ratio, so it draws
# on the whole frame (scripts/lib_cluster_frame.sh). The green menu's
# sharper-map switch changes the same lines later without a new install.
FULL_FRAME=`sed -n 's/^CLUSTERMAP_FULL_FRAME=\([01]\)[ 	]*$/\1/p' \
    "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`
[ "$FULL_FRAME" = 1 ] || FULL_FRAME=0
# The owner's choice is saved as it is even where this window cannot use it:
# when the player finds the real window later, window_fix.sh applies it.
FULL_FRAME_ASKED=$FULL_FRAME
if [ "$FULL_FRAME" = 1 ] && ! frame_full_ok $MAP_W $MAP_H; then
    echo "CLUSTERMAP_FULL_FRAME: the ${MAP_W}x${MAP_H} window is not wider than the frame's 5:3, so it gets no full frame; kept on in case the cockpit's window turns out wider."
    FULL_FRAME=0
fi
# Skoda fork, CLUSTERMAP_720P=1: a 1280x720 frame whose margins leave exactly
# the window, shown 1:1 by the player. Wins over full frame; kept as asked
# like full frame when this window cannot use it.
HD_FRAME=`sed -n 's/^CLUSTERMAP_720P=\([01]\)[ 	]*$/\1/p' \
    "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`
[ "$HD_FRAME" = 1 ] || HD_FRAME=0
HD_FRAME_ASKED=$HD_FRAME
if [ "$HD_FRAME" = 1 ] && ! frame_hd_ok $MAP_W $MAP_H; then
    echo "CLUSTERMAP_720P: the ${MAP_W}x${MAP_H} window does not fit a 1280x720 frame with margins of at most half; using the 800x480 frame."
    HD_FRAME=0
fi
if [ "$HD_FRAME" = 1 ]; then FULL_FRAME=0; fi
if ! frame_write_conf "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" $MAP_W $MAP_H $FULL_FRAME_ASKED $HD_FRAME_ASKED; then
    if [ "$FULL_FRAME" = 1 ] || [ "$HD_FRAME" = 1 ]; then
        echo "WARNING: could not edit the settings copy; CLUSTERMAP_FULL_FRAME and CLUSTERMAP_720P ignored, using margins."
    fi
    FULL_FRAME=0
    HD_FRAME=0
    frame_geometry $MAP_W $MAP_H 0 0
fi
if [ "$HD_FRAME" = 1 ]; then
    echo "Android Auto: 1280x720 frame with ${MARGIN_W}x${MARGIN_H} margins, the ${MAP_W}x${MAP_H} window's own pixels shown 1:1 (CLUSTERMAP_720P, a test; not car-tested yet)."
elif [ "$FULL_FRAME" = 1 ]; then
    echo "Android Auto: whole 800x480 frame, pixel aspect ${PIXEL_ASPECT_E4}/10000, stretched to the window (CLUSTERMAP_FULL_FRAME, the Skoda fork's default; car-tested on a Superb P4526)."
elif [ "$MARGIN_W" -gt 0 ] || [ "$MARGIN_H" -gt 0 ]; then
    echo "Android Auto: 800x480 with ${MARGIN_W}x${MARGIN_H} margins, scaled to fill the window."
fi

# "auto" DPI and insets: the values owners settled on for this make and
# window. A number in the card's file is kept as it is. Rewritten in place
# because the hook keeps the first value it reads for a key.
if [ "${MAP_W}x${MAP_H}" = "$CAR_WINDOW" ]; then
    AUTO_FROM="tested on $CAR_MAKE, ${MAP_W}x${MAP_H}"
else
    CAR_DPI=125; CAR_INSETS=40,40,127,127
    AUTO_FROM="no tested values for this car and window; shipped defaults"
fi
CONF_DPI=`sed -n 's/^GAL_SECONDARY_DPI=\([^ 	]*\)[ 	]*$/\1/p' "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | head -1`
CONF_INSETS=`sed -n 's/^GAL_SECONDARY_INSETS=\([^ 	]*\)[ 	]*$/\1/p' "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | head -1`
if [ "$CONF_DPI" = auto ] || [ "$CONF_INSETS" = auto ]; then
    if sed -e "s/^GAL_SECONDARY_DPI=auto[ 	]*$/GAL_SECONDARY_DPI=$CAR_DPI/" \
           -e "s/^GAL_SECONDARY_INSETS=auto[ 	]*$/GAL_SECONDARY_INSETS=$CAR_INSETS/" \
           "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" > "$PRELOAD_WRITE_DIR/gal_dualscreen.conf.new" &&
       mv "$PRELOAD_WRITE_DIR/gal_dualscreen.conf.new" "$PRELOAD_WRITE_DIR/gal_dualscreen.conf"; then
        :
    else
        rm -f "$PRELOAD_WRITE_DIR/gal_dualscreen.conf.new"
        echo "WARNING: could not fill in the auto settings; the hook uses its built-in values." >&2
    fi
fi
# Audi A4 B9 (AUG22) shows its cockpit map in context 72, not 70 (#14). The
# shipped 70 is changed in the installed copy; any other number is kept.
if [ "$CAR_CONTEXT" != 70 ] &&
   grep -q '^GAL_VC_CONTEXT=70[ 	]*$' "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null; then
    if sed "s/^GAL_VC_CONTEXT=70[ 	]*$/GAL_VC_CONTEXT=$CAR_CONTEXT/" "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" \
           > "$PRELOAD_WRITE_DIR/gal_dualscreen.conf.new" &&
       mv "$PRELOAD_WRITE_DIR/gal_dualscreen.conf.new" "$PRELOAD_WRITE_DIR/gal_dualscreen.conf"; then
        echo "Cockpit context: $CAR_CONTEXT ($CAR_MAKE)"
    else
        rm -f "$PRELOAD_WRITE_DIR/gal_dualscreen.conf.new"
        echo "WARNING: could not set GAL_VC_CONTEXT=$CAR_CONTEXT; set it in gal_dualscreen.conf." >&2
    fi
fi
[ "$CONF_DPI" = auto ] && echo "Map DPI: $CAR_DPI ($AUTO_FROM)" || echo "Map DPI: ${CONF_DPI:-built-in} (from gal_dualscreen.conf)"
[ "$CONF_INSETS" = auto ] && echo "Map insets: $CAR_INSETS ($AUTO_FROM)" || echo "Map insets: ${CONF_INSETS:-built-in} (from gal_dualscreen.conf)"
# The DPI the hook will actually use, for the summary. --dpi goes into the
# environment, which the hook reads before the conf file, so it wins.
case "$CONF_DPI" in
    auto) EFFECTIVE_DPI=$CAR_DPI ;;
    '')   EFFECTIVE_DPI=built-in ;;
    *)    EFFECTIVE_DPI=$CONF_DPI ;;
esac
[ "$DPI" -ne 140 ] && EFFECTIVE_DPI=$DPI

# Install stream-player to /mnt/app/navigation
# Through a new file and a rename: copying over the old player fails while it
# runs, and would leave the old one in place.
if [ -x "$CARD_ROOT/stream-player" ]; then
    PLAYER_DST="$APP_MOUNT/navigation/stream-player"
    if cp "$CARD_ROOT/stream-player" "$PLAYER_DST.new" 2>/dev/null && \
       [ "`wc -c < $CARD_ROOT/stream-player`" = "`wc -c < $PLAYER_DST.new`" ] && \
       chmod 755 "$PLAYER_DST.new" && mv "$PLAYER_DST.new" "$PLAYER_DST"; then
        echo "Installed stream-player to: $PLAYER_DST"
    else
        rm -f "$PLAYER_DST.new"
        echo "WARNING: could not install stream-player to $PLAYER_DST; the previous player, if any, stays." >&2
    fi
fi

# What the CarPlay map of an older package left on the unit.
for f in $CARPLAY_LEFTOVERS; do
    if [ -f "$PRELOAD_WRITE_DIR/$f" ]; then
        rm -f "$PRELOAD_WRITE_DIR/$f" && echo "Removed the old CarPlay map's $f"
    fi
done
rm -f "$APP_MOUNT/root/mibr-carplay111-safearea.conf" "$APP_MOUNT/root/mibr-carplay111-nav-query.enabled" \
      "$APP_MOUNT/root/mibr-carplay111-nav".* 2>/dev/null || true

mount -ur "$APP_MOUNT" 2>/dev/null || true
APP_WRITABLE=0
echo "Installed preload target: $PRELOAD_SO_ALIAS"

TARGET_IS_HOOKED=0
if grep -q 'libgal_hook.so' "$TARGET_CONFIG" 2>/dev/null; then
    TARGET_IS_HOOKED=1
fi

# The untouched supervisor config. The unit's own copy (beside the target) is
# the truth; the card's copy is refreshed from the unit at every install,
# because a card can have been in another car, or the unit's firmware can
# have been updated since the card's copy was made. Rebuilding a repeat
# install from a stale card copy would write another unit's config here.
# Never label an already-injected file as the original.
PERSISTENT_OK=0
if [ -r "$PERSISTENT_BACKUP" ] && ! grep -q 'libgal_hook.so' "$PERSISTENT_BACKUP" 2>/dev/null &&
   ! grep -q 'libcarplay_cluster.so' "$PERSISTENT_BACKUP" 2>/dev/null; then
    PERSISTENT_OK=1
fi
if [ "$TARGET_IS_HOOKED" -eq 0 ] && ! grep -q 'libcarplay_cluster.so' "$TARGET_CONFIG" 2>/dev/null; then
    cp "$TARGET_CONFIG" "$ORIGINAL" || exit 1
    echo "Saved untouched supervisor config: $ORIGINAL"
elif [ "$PERSISTENT_OK" -eq 1 ]; then
    cp "$PERSISTENT_BACKUP" "$ORIGINAL" || exit 1
    echo "Saved untouched supervisor config (from the unit's own copy): $ORIGINAL"
elif [ -r "$ORIGINAL" ]; then
    echo "NOTE: the unit has no untouched copy of its supervisor config; using the card's: $ORIGINAL"
else
    echo "Active config is already injected and no untouched backup is available" >&2
    echo "Refusing to overwrite or mislabel the original firmware config" >&2
    exit 1
fi

if grep -q 'libgal_hook.so' "$ORIGINAL" 2>/dev/null; then
    echo "SD recovery copy is not untouched: $ORIGINAL" >&2
    exit 1
fi
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$ORIGINAL" || {
    echo "SD recovery copy failed jsonlint: $ORIGINAL" >&2
    exit 1
}

# A repeated install is rebuilt from the first untouched backup. This avoids
# accumulating duplicate LD_PRELOAD/environment entries.
# ORIGINAL was just refreshed from the unit (above), so it is this unit's.
SOURCE="$ORIGINAL"

TEMP="$CARD_ROOT/logs/smartphone_integrator.json.new.$$"

# Point the hook at the SD-card log path. The SD card is writable right
# now (this script required it), and stays writable across a GAL restart
# that does not go through a fresh boot. It mounts read-only again on the
# next boot unless something remounts it before GAL starts -- which is
# before any interactive login shell could run a .profile-based
# "mount -uw" workaround. libgal_hook.so's own hook_vlog() already
# handles that case: if opening this path fails, it falls back to
# /tmp/gal_dualscreen.log automatically. hook_status.sh and
# runtime_debug.sh both check the SD path first and fall back to /tmp the
# same way, so no separate configuration is needed here for that case.
[ -n "$LOG_PATH_REQUESTED" ] || HOOK_LOG_PATH="$LOG_DIR/gal_dualscreen.log"
# Only emit the variable when asked, so the default install is
# byte-identical to before this option existed.
#
# Emit ONLY variables that differ from their built-in defaults.
#
# smartphone_integrator silently drops entries past a limit in this
# array: with 11 entries the whole injection vanished -- GAL started with
# no LD_PRELOAD and no GAL_DUALSCREEN_* at all, keeping only the last two
# (the stock LD_LIBRARY_PATH and IPL_CONFIG_DIR_GAL), while the config on
# disk still looked correct. Nothing reports this; the hook simply never
# loads. Nine entries were fine, so keep this list as short as possible
# and never assume a new variable is free.
OPT_ENV=
# GAL_STREAM_ENABLE and GAL_DUALSCREEN_CLUSTER_INPUT both default ON inside
# the hook (environment_flag_default_on), so the OFF value is the one that has
# to be emitted -- the reverse of what these two lines used to do. Emitting the
# ON value spent a slot saying what the hook already assumed, and, far worse,
# --no-stream and --no-cluster-input emitted NOTHING and so did nothing at all:
# the hook fell back to its default and turned the feature on anyway, while the
# summary below dutifully reported it as 0.
[ "$STREAM" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_STREAM_ENABLE=0\", "
[ -n "$AAP_MINOR" ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_AAP_MINOR=$AAP_MINOR\", "
[ "$CLUSTER_INPUT" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_CLUSTER_INPUT=0\", "
[ "$SECOND_SINK" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_SECOND_SINK=0\", "
[ "$INJECT_META" -eq 0 ] && OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_INJECT_META=0\", "
# --output is the only knob on this axis now; --no-secondary-render folds
# into it at parse time above.
[ -n "$OUTPUT" ] && [ "$OUTPUT" != gal ] && \
    OPT_ENV="$OPT_ENV\"GAL_DUALSCREEN_OUTPUT=$OUTPUT\", "
# 3 is the hook's built-in default displayable; only send a different one.
[ -n "$DISPLAYABLE" ] && [ "$DISPLAYABLE" -ne 3 ] && \
    OPT_ENV="$OPT_ENV\"GAL_VC_DISPLAYABLE_ID=$DISPLAYABLE\", "
# 140 is the hook's built-in default, so emitting it wastes one of the few
# env slots available. Only send it when it differs -- and the two MUST
# agree: if this said 160 while the hook defaulted to 140, running without
# --dpi would emit nothing and silently apply 140 while every message here
# claimed 160. tools/verify_constants.sh checks they match.
DPI_ENV=
[ "$DPI" -ne 140 ] && DPI_ENV="\"GAL_SECONDARY_DPI=$DPI\", "
# GAL_HOOK_LOG costs one of the ~10 usable slots, and without it the hook
# uses its own compiled-in path and still falls back to /tmp when the card
# is read-only -- which it is on every boot. The status scripts search the
# built-in path too, so omitting it changes where the log lands but not
# whether the tooling finds it. Emitted only when --log asked for a path.
LOG_ENV=
[ -n "$LOG_PATH_REQUESTED" ] && LOG_ENV="\"GAL_HOOK_LOG=$HOOK_LOG_PATH\", "
INJECTION="\"LD_PRELOAD=$PRELOAD_SO_ALIAS\", \"GAL_DUALSCREEN_ENABLE=1\", \"GAL_DUALSCREEN_DEBUG=$DEBUG\", $OPT_ENV$LOG_ENV$DPI_ENV"

# Refuse to write an array that smartphone_integrator would silently
# truncate. At 11 entries the ENTIRE injection was dropped once -- GAL ran
# with no LD_PRELOAD at all while this file still looked correct on disk,
# and the only symptom was a hook that never loaded. Failing loudly here is
# worth more than one extra option.
INJECTED_COUNT=`echo "$INJECTION" | awk -F'", ' '{print NF-1}'`
EXISTING_COUNT=`awk '
BEGIN { in_children=0; in_gal=0; in_envs=0; line="" }
{
    if ($0 ~ /"children"[ 	]*:/) in_children=1
    if (in_children && !in_gal && $0 ~ /^[ 	]*"gal"[ 	]*:/) in_gal=1
    # The array is on one line on the Golf, one entry per line on VWG11:
    # gather it up to the closing bracket either way.
    if (in_gal && !in_envs && $0 ~ /^[ 	]*"envs"[ 	]*:\[/) {
        in_envs=1; line=$0; sub(/^[^\[]*\[/, "", line)
    } else if (in_envs) line=line $0
    if (in_envs && line ~ /\]/) {
        sub(/\].*$/, "", line)
        n=split(line, parts, /"[ 	]*,[ 	]*"/)
        if (line ~ /^[ 	]*$/) n=0
        print n; exit
    }
}' "$SOURCE"`
[ -n "$EXISTING_COUNT" ] || EXISTING_COUNT=0
ENTRY_COUNT=`expr $INJECTED_COUNT + $EXISTING_COUNT`
echo "Environment entries: $INJECTED_COUNT injected + $EXISTING_COUNT already in the stock config"
if [ "$ENTRY_COUNT" -gt 10 ]; then
    echo "Refusing to install: $ENTRY_COUNT environment entries." >&2
    echo "smartphone_integrator silently drops the whole array past ~10," >&2
    echo "so the hook would never load and nothing would report it." >&2
    echo "Drop an option -- the default for --dpi costs nothing." >&2
    exit 3
fi
echo "Environment entries: $ENTRY_COUNT (limit 10)"

awk -v injection="$INJECTION" '
BEGIN { in_children=0; in_gal=0; patched=0 }
{
    if ($0 ~ /"children"[ 	]*:/) in_children=1
    if (in_children && !in_gal && $0 ~ /^[ 	]*"gal"[ 	]*:/) in_gal=1
    if (in_gal && !patched && $0 ~ /^[ 	]*"envs"[ 	]*:\[/) {
        sub(/\[/, "[" injection)
        patched=1
    }
    print
}
END { if (!patched) exit 3 }
' "$SOURCE" > "$TEMP" || {
    rm -f "$TEMP"
    echo "Could not locate children.gal.envs in $SOURCE" >&2
    exit 1
}

grep -q "LD_PRELOAD=$PRELOAD_SO_ALIAS" "$TEMP" || {
    rm -f "$TEMP"
    echo "Generated supervisor config failed verification" >&2
    exit 1
}

LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$TEMP" || {
    rm -f "$TEMP"
    echo "Generated supervisor config failed jsonlint validation" >&2
    exit 1
}

mount -uw "$SYSTEM_MOUNT" 2>/dev/null || {
    rm -f "$TEMP"
    echo "Cannot remount $SYSTEM_MOUNT read-write" >&2
    exit 1
}
SYSTEM_WRITABLE=1
cp "$TARGET_CONFIG" "$BACKUP_DIR/smartphone_integrator.json.before_enable.$$"
# ORIGINAL is the unit's untouched config as of this install (see above):
# written again each time, so a firmware update or another unit's stale copy
# never survives here. Uninstall restores from this file.
if [ "$PERSISTENT_OK" -eq 0 ] || [ "$TARGET_IS_HOOKED" -eq 0 ]; then
    cp "$ORIGINAL" "$PERSISTENT_BACKUP" || {
        echo "Could not create persistent recovery copy: $PERSISTENT_BACKUP" >&2
        exit 1
    }
fi
if grep -q 'libgal_hook.so' "$PERSISTENT_BACKUP" 2>/dev/null; then
    echo "Persistent recovery copy unexpectedly contains the hook: $PERSISTENT_BACKUP" >&2
    exit 1
fi
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$PERSISTENT_BACKUP" || {
    echo "Persistent recovery copy failed jsonlint: $PERSISTENT_BACKUP" >&2
    exit 1
}
SYSTEM_TEMP="$TARGET_CONFIG.gal-dualscreen-new"
cp "$TEMP" "$SYSTEM_TEMP" || {
    rm -f "$TEMP"
    echo "Could not stage $SYSTEM_TEMP" >&2
    exit 1
}
chmod 644 "$SYSTEM_TEMP" 2>/dev/null || true
grep -q "LD_PRELOAD=$PRELOAD_SO_ALIAS" "$SYSTEM_TEMP" || {
    rm -f "$TEMP"
    echo "Staged supervisor config failed verification" >&2
    exit 1
}
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$SYSTEM_TEMP" || {
    rm -f "$TEMP"
    echo "Staged supervisor config failed jsonlint validation" >&2
    exit 1
}
mv "$SYSTEM_TEMP" "$TARGET_CONFIG" || {
    rm -f "$TEMP"
    echo "Could not atomically install $TARGET_CONFIG" >&2
    exit 1
}
SYSTEM_TEMP=
LD_LIBRARY_PATH="$VALIDATOR_LD_LIBRARY_PATH" "$JSONLINT" --file "$TARGET_CONFIG" || {
    echo "Installed config failed validation; restoring persistent original" >&2
    if cp "$PERSISTENT_BACKUP" "$TARGET_CONFIG"; then
        echo "Restored $TARGET_CONFIG from $PERSISTENT_BACKUP" >&2
    else
        echo "CRITICAL: restore from $PERSISTENT_BACKUP also failed" >&2
        echo "CRITICAL: $TARGET_CONFIG is left in a state that failed jsonlint" >&2
        echo "CRITICAL: fix this file manually before rebooting the unit" >&2
    fi
    rm -f "$TEMP"
    exit 1
}
rm -f "$TEMP"
# The firewall rule an older package's CarPlay map added.
carplay_pf_close
sync
mount -ur "$SYSTEM_MOUNT" 2>/dev/null || true
SYSTEM_WRITABLE=0
trap - 0 1 2 15

echo "Hook environment installed for the supervisor-owned GAL."
echo "  persistent config: $TARGET_CONFIG"
echo "  persistent recovery: $PERSISTENT_BACKUP"
echo "  preload target: $PRELOAD_SO_ALIAS"
echo "    on the internal /mnt/app partition, not the SD card -- avoids the"
echo "    SD-card mount-timing race at GAL's boot-time launch."
echo "  output mode: $OUTPUT (video forwarded to stream-player)"
if [ "$HD_FRAME" = 1 ]; then
    echo "  cluster: Android Auto 1280x720 @ 30 fps (margins ${MARGIN_W}x${MARGIN_H}, shown 1:1), DPI $EFFECTIVE_DPI before the hook's 720p scaling, ${MAP_W}x${MAP_H} window"
elif [ "$FULL_FRAME" = 1 ]; then
    echo "  cluster: Android Auto 800x480 @ 30 fps (full frame, pixel aspect ${PIXEL_ASPECT_E4}/10000), DPI $EFFECTIVE_DPI, ${MAP_W}x${MAP_H} window"
else
    echo "  cluster: Android Auto 800x480 @ 30 fps (margins ${MARGIN_W}x${MARGIN_H}), DPI $EFFECTIVE_DPI, ${MAP_W}x${MAP_H} window"
fi
echo "  debug logs: $DEBUG"
echo "  second sink: $SECOND_SINK   inject metadata: $INJECT_META"
# The hook reads GAL_DUALSCREEN_AAP_MINOR from its own copy of the settings at
# run time, so --aap-minor is not the only source. Without the flag this line
# used to say "2 (stock)" while the hook was in fact using the file's value --
# which sent two testers (#19, #37) chasing a protocol version they were not
# running. Report what will actually be used.
AAP_MINOR_CONF=`sed -n 's/^GAL_DUALSCREEN_AAP_MINOR=\([0-9]*\)[ 	]*$/\1/p' \
    "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`
if [ -n "$AAP_MINOR" ]; then
    echo "  AAP minor version: $AAP_MINOR (--aap-minor)"
elif [ -n "$AAP_MINOR_CONF" ]; then
    echo "  AAP minor version: $AAP_MINOR_CONF (from gal_dualscreen.conf)"
else
    echo "  AAP minor version: 2 (stock)"
fi
echo "  stream forwarding: $STREAM"
echo "  cluster input service: $CLUSTER_INPUT"
echo "  hook log: $HOOK_LOG_PATH"
echo "    falls back to /tmp/gal_dualscreen.log (RAM-backed, does not survive"
echo "    a reboot) if the SD card is read-only when GAL starts -- true on"
echo "    every boot unless the SD card is remounted -uw before GAL starts."

# ---- Java interface: the two patches that decide whether the map stays up ----
# NavActiveIgnore must be loaded, and the turn-by-turn jar must not be. Both are
# single lines in the Java start-up script, edited through lsd_jar.sh, which
# checks every change before it replaces the file.
LSD_SH=/mnt/app/eso/hmi/lsd/lsd.sh
NAVIGNORE_MARKER=/mnt/app/eso/hmi/lsd/.aacluster_navignore_added
# Firmware where the bundled NavActiveIgnore.jar has been seen working. It is a
# Java patch: on a firmware it does not fit, the centre screen may not start,
# so it is never added automatically anywhere else.
# Where it is added without being asked is "navignore" in profiles.conf: trains
# where owners ran this same jar, or the toolbox's copy of it, and sent logs
# showing it loaded (#15). Those logs came from the green menu, which only runs
# once the centre screen has started, so the patch fits.
# CLUSTERMAP_ADD_NAVIGNORE=1 in gal_dualscreen.conf: add it on any other
# firmware too, when the owner asks. It is the same jar the toolbox applies,
# but done here it gets lsd.sh.before_* backups and is removed again by
# uninstall. Off by default: on a firmware it does not fit, the centre screen
# may not start (see docs/Install.md, Safety and recovery).
NAVIGNORE_ASKED=`sed -n 's/^CLUSTERMAP_ADD_NAVIGNORE=\([01]\)[ 	]*$/\1/p' \
    "$PRELOAD_WRITE_DIR/gal_dualscreen.conf" 2>/dev/null | tail -1`
# Never where profiles.conf says "nonavignore": with it, Android Auto stopped
# working on an S2125 (#39, FAILED_NO_GAL_DEVICE). Owners updated to
# MHI2_ER_VWG11_K3342 run it fine (#39, #28; the #28 freeze was an edited
# gal.json). The Audi K3346 kept its map through a route without it (#14).
NAVIGNORE_NEVER=0
if train_has "$PROFILES" "$TRAIN" nonavignore; then NAVIGNORE_NEVER=1; fi
# Which build: the toolbox's patches VW classes (de.vw.mib.asl.*), most of
# which the A6/A7 C7.5 interface does not have; there the Audi build M.I.B.
# installs (harman-f; thirdparty/navactiveignore-audi) goes in instead,
# under the same name on the unit.
NAVIGNORE_SRC="$CARD_ROOT/thirdparty/NavActiveIgnore.jar"
NAVIGNORE_BUILD="toolbox (VW)"
case "$TRAIN" in
    # Every Audi interface is de.audi.*: the A3 8V (AU37x) and A4/Q5 (AUG22)
    # get the Audi build too. Car-tested on the A7 only; elsewhere it is added
    # only when the owner asks (CLUSTERMAP_ADD_NAVIGNORE=1), never on a
    # "nonavignore" train.
    *_AU*) NAVIGNORE_SRC="$CARD_ROOT/thirdparty/NavActiveIgnore_Audi.jar"; NAVIGNORE_BUILD="Audi" ;;
esac
echo
if [ ! -r "$LSD_SH" ] || [ ! -r "$CARD_ROOT/lsd_jar.sh" ]; then
    echo "WARNING: cannot check the Java interface ($LSD_SH or lsd_jar.sh missing)." >&2
else
    NAV_HAVE=`wc -c < /mnt/app/eso/hmi/lsd/jars/NavActiveIgnore.jar 2>/dev/null | sed 's/ //g'`
    NAV_WANT=`wc -c < "$NAVIGNORE_SRC" 2>/dev/null | sed 's/ //g'`
    if sh "$CARD_ROOT/lsd_jar.sh" loaded NavActiveIgnore.jar && [ "$NAVIGNORE_NEVER" -eq 1 ] &&
       [ "$NAVIGNORE_BUILD" = Audi ] && [ -n "$NAV_WANT" ] && [ "$NAV_HAVE" = "$NAV_WANT" ]; then
        # An Audi owner's own M.I.B. install of the Audi build (a Q5 FY on
        # K3346 has it): the warning below is about the VW build.
        echo "Java check: NavActiveIgnore (Audi build) is loaded; left as it is."
    elif sh "$CARD_ROOT/lsd_jar.sh" loaded NavActiveIgnore.jar && [ "$NAVIGNORE_NEVER" -eq 1 ]; then
        echo "WARNING: NavActiveIgnore is loaded. On firmware $TRAIN it has stopped" >&2
        echo "         Android Auto (#39). If it does, remove it with the toolbox or" >&2
        echo "         this package's uninstall, or update to MHI2_ER_VWG11_K3342." >&2
    elif sh "$CARD_ROOT/lsd_jar.sh" loaded NavActiveIgnore.jar; then
        echo "Java check: NavActiveIgnore is loaded (required)."
        # A6/A7: the VW build there patches classes this interface lacks.
        case "$TRAIN" in
            *_AU*)
                if [ -n "$NAV_WANT" ] && [ "$NAV_HAVE" != "$NAV_WANT" ]; then
                    echo "WARNING: the loaded NavActiveIgnore.jar (${NAV_HAVE:-unreadable} bytes) is not the Audi" >&2
                    echo "         build this unit needs ($NAV_WANT bytes, as M.I.B. installs it)." >&2
                fi ;;
        esac
    elif sh "$CARD_ROOT/lsd_jar.sh" loaded CarPlayNavigationPatch.jar; then
        # CarPlay Maps VC ships the same nine classes under another name.
        echo "Java check: CarPlayNavigationPatch is loaded (the same patch as NavActiveIgnore)."
    elif [ "$NAVIGNORE_NEVER" -eq 1 ]; then
        echo "Java check: NavActiveIgnore is not loaded, and is never added on $TRAIN"
        if [ "$NAVIGNORE_ASKED" = 1 ]; then
            echo "            (CLUSTERMAP_ADD_NAVIGNORE=1 ignored: it broke Android Auto on this firmware, #39)."
            echo "            Owners updated to MHI2_ER_VWG11_K3342 have it working (#39, #28)."
        fi
    elif [ "$KEEP_NAVIGNORE" -eq 1 ]; then
        echo "Java check: NavActiveIgnore is NOT loaded and was left alone (--no-navignore)."
        echo "            The cluster will drop its map when the phone navigates."
    else
        NAV_OK=0
        NAV_WHY="firmware $TRAIN"
        if train_has "$PROFILES" "$TRAIN" navignore; then NAV_OK=1; fi
        if [ "$NAV_OK" -eq 0 ] && [ "$NAVIGNORE_ASKED" = 1 ]; then
            NAV_OK=1; NAV_WHY="asked for by CLUSTERMAP_ADD_NAVIGNORE=1 on $TRAIN"
        fi
        if [ "$NAV_OK" -eq 1 ]; then
            echo "Java check: NavActiveIgnore is not loaded; adding the $NAVIGNORE_BUILD build ($NAV_WHY)."
            if [ ! -r "$NAVIGNORE_SRC" ]; then
                echo "WARNING: the $NAVIGNORE_BUILD NavActiveIgnore build is not in this package; not added." >&2
            elif sh "$CARD_ROOT/lsd_jar.sh" add NavActiveIgnore.jar "$NAVIGNORE_SRC"; then
                mount -uw /mnt/app 2>/dev/null && { : > "$NAVIGNORE_MARKER"; mount -ur /mnt/app 2>/dev/null || true; }
            else
                echo "WARNING: could not add NavActiveIgnore; lsd.sh is unchanged." >&2
                echo "         Apply it from the toolbox: Customization > Navigation." >&2
            fi
        else
            echo "WARNING: NavActiveIgnore is NOT loaded, and it is not added automatically" >&2
            echo "         on firmware $TRAIN. Without it the cluster drops the map as" >&2
            echo "         soon as the phone starts a route. To have this installer add" >&2
            echo "         it, put CLUSTERMAP_ADD_NAVIGNORE=1 in gal_dualscreen.conf and" >&2
            echo "         install again; or apply it from the toolbox: Customization >" >&2
            echo "         Navigation > Ignore navigation-active status. It edits the script" >&2
            echo "         that starts the centre screen: check SSH works first, and keep a" >&2
            echo "         copy: cp $LSD_SH $LSD_SH.myback" >&2
        fi
    fi
    TBT_OK=0
    if train_has "$PROFILES" "$TRAIN" arrows; then TBT_OK=1; fi
    if [ "$WITH_ARROWS" -eq 1 ] && ! sh "$CARD_ROOT/lsd_jar.sh" loaded VCAndroidAuto.jar; then
        if [ "$TBT_OK" -eq 1 ]; then
            echo "Java check: adding VCAndroidAuto.jar beside the map (CLUSTERMAP_KEEP_ARROWS=1)."
            if sh "$CARD_ROOT/lsd_jar.sh" add VCAndroidAuto.jar "$CARD_ROOT/thirdparty/VCAndroidAuto.jar"; then
                mount -uw /mnt/app 2>/dev/null && { : > /mnt/app/eso/hmi/lsd/.aacluster_tbt_added; mount -ur /mnt/app 2>/dev/null || true; }
            else
                echo "WARNING: could not add VCAndroidAuto.jar; lsd.sh is unchanged." >&2
            fi
        else
            echo "WARNING: CLUSTERMAP_KEEP_ARROWS=1 ignored: the arrows jar is not known to" >&2
            echo "         work on firmware $TRAIN." >&2
        fi
    fi
    if sh "$CARD_ROOT/lsd_jar.sh" loaded VCAndroidAuto.jar; then
        if [ "$KEEP_TBT" -eq 1 ]; then
            echo "Java check: VCAndroidAuto.jar is loaded and was kept with the map."
            case "$TRAIN" in
                *_VWG*) echo "            On VW, expect the cluster map to go blank when a route starts." ;;
            esac
        elif sh "$CARD_ROOT/turn_by_turn.sh" remove; then
            :
        else
            echo "WARNING: could not remove the VCAndroidAuto.jar line; lsd.sh is unchanged." >&2
            echo "         The hook is installed, but the map may fail when a route starts." >&2
        fi
    else
        echo "Java check: VCAndroidAuto.jar is not loaded (good)."
    fi
    # One extra build of the arrows jar beside the map, never together with
    # VCAndroidAuto.jar (they carry the same classes):
    #   CLUSTERMAP_TURN_INFO=1  VCAndroidAutoTurns.jar: turn data and track
    #     info, the cockpit's view (arrows or map) left to the stock logic so
    #     the map should stay up with the cockpit's arrow beside it.
    #   CLUSTERMAP_MUSIC_INFO=1 VCAndroidAutoMusic.jar: track info only, no
    #     turn data.
    # TURN_INFO wins when both are set. Each jar the installer adds gets a
    # marker, and only marked jars are ever removed.
    CONF_FILE="$PRELOAD_WRITE_DIR/gal_dualscreen.conf"
    TURNS_ASKED=`sed -n 's/^CLUSTERMAP_TURN_INFO=\([01]\)[ 	]*$/\1/p' "$CONF_FILE" 2>/dev/null | tail -1`
    MUSIC_ASKED=`sed -n 's/^CLUSTERMAP_MUSIC_INFO=\([01]\)[ 	]*$/\1/p' "$CONF_FILE" 2>/dev/null | tail -1`
    FULL_JAR=0
    if sh "$CARD_ROOT/lsd_jar.sh" loaded VCAndroidAuto.jar; then FULL_JAR=1; fi
    WANT_JAR=
    WANT_KEY=
    WANT_WHAT=
    if [ "$TURNS_ASKED" = 1 ]; then
        WANT_JAR=VCAndroidAutoTurns.jar
        WANT_KEY=CLUSTERMAP_TURN_INFO
        WANT_WHAT="turn info and track info, cockpit view left to the cockpit"
    elif [ "$MUSIC_ASKED" = 1 ]; then
        WANT_JAR=VCAndroidAutoMusic.jar
        WANT_KEY=CLUSTERMAP_MUSIC_INFO
        WANT_WHAT="track info on the cockpit, no turn data"
    fi
    if [ "$FULL_JAR" -eq 1 ] && [ -n "$WANT_JAR" ]; then
        echo "WARNING: $WANT_KEY=1 ignored: VCAndroidAuto.jar is loaded" >&2
        echo "         (CLUSTERMAP_KEEP_ARROWS=1) and carries the same classes." >&2
        WANT_JAR=
    fi
    FOREIGN_JAR=
    for EXTRA_JAR in VCAndroidAutoMusic.jar VCAndroidAutoTurns.jar; do
        case "$EXTRA_JAR" in
            VCAndroidAutoMusic.jar) EXTRA_MARKER=/mnt/app/eso/hmi/lsd/.aacluster_music_added ;;
            *) EXTRA_MARKER=/mnt/app/eso/hmi/lsd/.aacluster_turns_added ;;
        esac
        if [ "$EXTRA_JAR" = "$WANT_JAR" ]; then
            continue
        fi
        if ! sh "$CARD_ROOT/lsd_jar.sh" loaded $EXTRA_JAR; then
            continue
        fi
        if [ -f "$EXTRA_MARKER" ]; then
            echo "Java check: removing $EXTRA_JAR (not asked for in gal_dualscreen.conf)."
            if sh "$CARD_ROOT/lsd_jar.sh" remove $EXTRA_JAR; then
                mount -uw /mnt/app 2>/dev/null && { rm -f "$EXTRA_MARKER"; mount -ur /mnt/app 2>/dev/null || true; }
            else
                echo "WARNING: could not remove $EXTRA_JAR; lsd.sh is unchanged." >&2
            fi
        else
            FOREIGN_JAR=$EXTRA_JAR
            echo "WARNING: $EXTRA_JAR is loaded and this installer did not add it." >&2
            echo "         Never load two of VCAndroidAuto.jar, VCAndroidAutoMusic.jar and" >&2
            echo "         VCAndroidAutoTurns.jar together: they carry the same classes." >&2
        fi
    done
    if [ -n "$WANT_JAR" ]; then
        case "$WANT_JAR" in
            VCAndroidAutoMusic.jar) WANT_MARKER=/mnt/app/eso/hmi/lsd/.aacluster_music_added ;;
            *) WANT_MARKER=/mnt/app/eso/hmi/lsd/.aacluster_turns_added ;;
        esac
        if [ "$TBT_OK" -ne 1 ]; then
            echo "WARNING: $WANT_KEY=1 ignored: the arrows jar is not known to" >&2
            echo "         work on firmware $TRAIN." >&2
        elif sh "$CARD_ROOT/lsd_jar.sh" loaded $WANT_JAR; then
            echo "Java check: $WANT_JAR is loaded ($WANT_WHAT)."
        elif [ -n "$FOREIGN_JAR" ]; then
            echo "WARNING: $WANT_KEY=1 ignored: remove $FOREIGN_JAR first." >&2
        else
            echo "Java check: adding $WANT_JAR ($WANT_KEY=1: $WANT_WHAT)."
            if sh "$CARD_ROOT/lsd_jar.sh" add $WANT_JAR "$CARD_ROOT/thirdparty/$WANT_JAR"; then
                mount -uw /mnt/app 2>/dev/null && { : > "$WANT_MARKER"; mount -ur /mnt/app 2>/dev/null || true; }
            else
                echo "WARNING: could not add $WANT_JAR; lsd.sh is unchanged." >&2
            fi
        fi
    fi
    # CLUSTERMAP_TURN_TEXT=auto|always|never: when the turns jar sends the
    # road name ("towards ...") to the cockpit. auto: only while the cockpit
    # is not showing the map, which already has Google's own card. The jar
    # reads it when the centre screen starts.
    TURN_TEXT_FILE=/mnt/app/root/vcaa_turn_text
    if [ "$WANT_JAR" = VCAndroidAutoTurns.jar ]; then
        TURN_TEXT=`sed -n 's/^CLUSTERMAP_TURN_TEXT=\([a-z]*\)[ 	]*$/\1/p' "$CONF_FILE" 2>/dev/null | tail -1`
        case "$TURN_TEXT" in
            auto|always|never) ;;
            "") TURN_TEXT=auto ;;
            *) echo "WARNING: CLUSTERMAP_TURN_TEXT=$TURN_TEXT is not auto, always or never; using auto." >&2
               TURN_TEXT=auto ;;
        esac
        if mount -uw /mnt/app 2>/dev/null; then
            echo "$TURN_TEXT" > "$TURN_TEXT_FILE" || echo "WARNING: could not write $TURN_TEXT_FILE" >&2
            mount -ur /mnt/app 2>/dev/null || true
        fi
        echo "Turn info: road name on the cockpit: $TURN_TEXT"
    elif [ -f "$TURN_TEXT_FILE" ]; then
        mount -uw /mnt/app 2>/dev/null && { rm -f "$TURN_TEXT_FILE"; mount -ur /mnt/app 2>/dev/null || true; }
    fi
fi

# The install is complete: remember which package and which card file it
# was, for the settings comparison at the next install. Not earlier, so a
# run that failed part-way is not taken for a finished install of this card.
if mount -uw "$APP_MOUNT" 2>/dev/null; then
    if [ -n "$CARD_SAVED_NEW" ] && [ -r "$CARD_LAST.new" ]; then
        mv "$CARD_LAST.new" "$CARD_LAST" 2>/dev/null || rm -f "$CARD_LAST.new" 2>/dev/null
    fi
    if [ -n "$PKG_NOW" ]; then
        echo "$PKG_NOW" > "$PKG_SAVED" 2>/dev/null || :
    fi
    mount -ur "$APP_MOUNT" 2>/dev/null || true
fi

echo
echo "Reboot the unit to apply it. Do not start a second GAL manually."
