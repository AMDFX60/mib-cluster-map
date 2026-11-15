#!/bin/sh
. "`dirname "$0"`/common.sh"
# Green menu test step (1.4.1-beta3): scripts/player_test.sh step3.
echo "Step 3: hardware decoder, rectangle xywh"
sh "$PKG/scripts/player_test.sh" step3
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_STEP_DONE"
    echo "Now reboot (hold the power button for 10 seconds), drive, then Save logs to SD."
else
    echo "CLUSTERMAP_STEP_FAILED (code $RC). Read the messages above."
fi
exit 0
