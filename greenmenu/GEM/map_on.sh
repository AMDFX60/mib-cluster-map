#!/bin/sh
. "`dirname "$0"`/common.sh"
# The master switch back on (GAL_DUALSCREEN_ENABLE=1) in the unit's settings
# copy. The next install keeps it (scripts/menu_switch.sh).
echo "Cockpit map ON"
sh "$PKG/scripts/menu_switch.sh" GAL_DUALSCREEN_ENABLE 1 reboot "Cockpit map: ON"
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_SWITCH_DONE"
elif [ $RC -eq 3 ]; then
    echo "CLUSTERMAP_SWITCH_UNCHANGED"
else
    echo "CLUSTERMAP_SWITCH_FAILED (code $RC). Read the messages above."
fi
exit 0
