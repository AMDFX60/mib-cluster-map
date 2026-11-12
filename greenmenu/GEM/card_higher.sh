#!/bin/sh
. "`dirname "$0"`/common.sh"
# The turn card still hidden, the car higher on the cluster map (test, the
# 1.2.2-beta3 position), in the unit's settings copy.
echo "Test: hidden turn card, car higher"
sh "$PKG/scripts/card_layout.sh" higher
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
