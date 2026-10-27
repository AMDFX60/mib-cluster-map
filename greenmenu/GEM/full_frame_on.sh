#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# Sharper map (CLUSTERMAP_FULL_FRAME) on, in the unit's settings copy.
echo "Sharper map ON"
sh "$PKG/scripts/full_frame.sh" on
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_FULL_FRAME_DONE"
    echo "Hold the power button for 10 seconds to reboot the unit."
elif [ $RC -eq 3 ]; then
    echo "CLUSTERMAP_FULL_FRAME_UNCHANGED"
else
    echo "CLUSTERMAP_FULL_FRAME_FAILED (code $RC). Read the messages above."
fi
exit 0
