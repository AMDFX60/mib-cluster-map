#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# The cockpit map at 20 frames a second (standard): the package's NavActiveIgnore.jar.
echo "Cockpit map 20 fps mode (standard)"
sh "$PKG/scripts/map_rate.sh" 20
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_RATE_DONE"
    echo "Hold the power button for 10 seconds to reboot the unit."
elif [ $RC -eq 3 ]; then
    echo "CLUSTERMAP_RATE_UNCHANGED"
else
    echo "CLUSTERMAP_RATE_FAILED (code $RC). Read the messages above."
fi
exit 0
