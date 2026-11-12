#!/bin/sh
. "`dirname "$0"`/common.sh"
# The 720p picture (CLUSTERMAP_720P) on, in the unit's settings copy.
echo "Test: 720p picture, 1:1"
sh "$PKG/scripts/full_frame.sh" 720p
RC=$?
echo
if [ $RC -eq 0 ]; then
    echo "CLUSTERMAP_FULL_FRAME_DONE"
elif [ $RC -eq 3 ]; then
    echo "CLUSTERMAP_FULL_FRAME_UNCHANGED"
else
    echo "CLUSTERMAP_FULL_FRAME_FAILED (code $RC). Read the messages above."
fi
exit 0
