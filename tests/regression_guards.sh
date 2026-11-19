#!/bin/sh
# Static guards for faults that reached a car once (here or upstream). Each
# check names the report it came from. Run from anywhere:
#   sh tests/regression_guards.sh
# build_local.sh runs it before it packs a card. Adapted from upstream
# MacsInSpace/mib-cluster-map tests/regression_guards.sh (guards 1, 3 and 5;
# its guard 6 is tools/unit_shell_lint.py rule E1 here).
ROOT=`dirname "$0"`/..
cd "$ROOT" || exit 2
FAIL=0
bad() { echo "GUARD FAILED: $*"; FAIL=1; }

# 1. Upstream #101: the installer wrote GAL_DUALSCREEN_ENABLE=1 into gal's
#    start-up whatever the settings said, and the start-up value beats the
#    settings file, so GAL_DUALSCREEN_ENABLE=0 did nothing. The injected
#    value must come from the settings, and the hook must let the file's
#    line win (the green menu's "Cockpit map OFF/ON" changes only the file).
grep -n '^INJECTION=' scripts/enable_hook.sh | grep -q 'GAL_DUALSCREEN_ENABLE=\$HOOK_ENABLE' ||
    bad "enable_hook.sh: INJECTION must carry GAL_DUALSCREEN_ENABLE=\$HOOK_ENABLE (#101)"
grep -n 'GAL_DUALSCREEN_ENABLE=1\\"' scripts/enable_hook.sh | grep -v '^[0-9]*:[ 	]*#' | grep -q . &&
    bad "enable_hook.sh: a fixed GAL_DUALSCREEN_ENABLE=1 is written into gal's start-up (#101)"
grep -q 'strcmp(key, "GAL_DUALSCREEN_ENABLE") == 0' src/gal_hook.c ||
    bad "src/gal_hook.c: the settings file no longer decides GAL_DUALSCREEN_ENABLE (#101)"

# 2. Upstream v1.2.0: the installer runs under set -eu on the unit. A test
#    harness without it let a release through that stopped on an unset
#    variable.
for f in scripts/enable_hook.sh scripts/disable_hook.sh; do
    grep -q '^set -eu' "$f" || bad "$f does not start with set -eu any more"
done

# 3. Every script the menu names has to exist, and so does whatever those
#    scripts call from the package's scripts folder (a menu entry whose
#    script was never packed says "script not found" in the car).
for f in `sed -n 's|.*"/fs/sda0/ClusterMap/GEM/\([^"]*\)".*|\1|p' greenmenu/cluster-map.esd`; do
    [ -f "greenmenu/GEM/$f" ] || bad "cluster-map.esd names GEM/$f, which does not exist"
done
for f in `sed -n 's|.*"\$PKG/scripts/\([a-z_]*\.sh\)".*|\1|p' greenmenu/GEM/*.sh | sort -u`; do
    grep -q "scripts/$f" build_local.sh || bad "a menu script calls scripts/$f, which build_local.sh does not pack"
done

if [ $FAIL = 0 ]; then echo "regression guards ok"; fi
exit $FAIL
