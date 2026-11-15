#!/bin/sh
. "`dirname "$0"`/common.sh"
# Green menu test step (1.4.1-beta3): scripts/player_test.sh off.
echo "Step 6: back to standard"
sh "$PKG/scripts/player_test.sh" off
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_STEP_DONE"
    echo "Now reboot (hold the power button for 10 seconds): the cluster map runs as installed."
else
    echo "CLUSTERMAP_STEP_FAILED (code $RC). Read the messages above."
fi
exit 0
