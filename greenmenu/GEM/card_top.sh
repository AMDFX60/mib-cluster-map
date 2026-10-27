#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# The turn card back where the settings put it, in the unit's settings copy.
echo "Turn card at the top (standard)"
sh "$PKG/scripts/card_layout.sh" top
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_CARD_DONE"
    echo "Hold the power button for 10 seconds to reboot the unit."
elif [ $RC -eq 3 ]; then
    echo "CLUSTERMAP_CARD_UNCHANGED"
else
    echo "CLUSTERMAP_CARD_FAILED (code $RC). Read the messages above."
fi
exit 0
