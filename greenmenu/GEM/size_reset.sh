#!/bin/sh
. /fs/sda0/ClusterMap/GEM/common.sh 2>/dev/null || . `dirname "$0"`/common.sh
# The cluster map's DPI back to the installed value, in the unit's settings copy.
echo "Map size as installed"
sh "$PKG/scripts/map_size.sh" reset
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
