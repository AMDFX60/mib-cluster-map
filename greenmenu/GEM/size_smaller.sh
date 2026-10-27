#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# The cluster map 10 DPI smaller (test), in the unit's settings copy.
echo "Test: map smaller (DPI -10)"
sh "$PKG/scripts/map_size.sh" smaller
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_SIZE_DONE"
    echo "Hold the power button for 10 seconds to reboot the unit."
elif [ $RC -eq 3 ]; then
    echo "CLUSTERMAP_SIZE_UNCHANGED"
else
    echo "CLUSTERMAP_SIZE_FAILED (code $RC). Read the messages above."
fi
exit 0
