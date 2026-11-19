#!/bin/sh
. "`dirname "$0"`/common.sh"
# The master switch off (GAL_DUALSCREEN_ENABLE=0) in the unit's settings copy:
# everything stays installed, Android Auto runs as stock and the cockpit keeps
# the car's own map. For a wireless adapter that stops working with the map,
# or to compare. The next install keeps it (scripts/menu_switch.sh).
echo "Cockpit map OFF"
sh "$PKG/scripts/menu_switch.sh" GAL_DUALSCREEN_ENABLE 0 reboot "Cockpit map: OFF. Android Auto runs as stock; nothing is removed"
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
