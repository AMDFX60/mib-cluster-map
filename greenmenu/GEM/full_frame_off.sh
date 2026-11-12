#!/bin/sh
. "`dirname "$0"`/common.sh"
# Sharper map (CLUSTERMAP_FULL_FRAME) off, in the unit's settings copy.
echo "Sharper map OFF"
sh "$PKG/scripts/full_frame.sh" off
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
