#!/bin/sh
. "`dirname "$0"`/common.sh"
# The turn card setting "top_left", in the unit's settings copy; the next
# install keeps it (scripts/card_layout.sh).
echo "Turn card top left"
sh "$PKG/scripts/card_layout.sh" top_left
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
