#!/bin/bash
# Build OrangeFox.
#
# Note: 'source build/envsetup.sh' must run in the shell itself, not inside a
# pipeline, or its variables do not persist.
set -e
DIR=${1:-$HOME/fox_12.1}
cd "$DIR"

export ALLOW_MISSING_DEPENDENCIES=true
export FOX_BUILD_DEVICE=merlinx
export LC_ALL=C

# vendorsetup.sh only runs when envsetup.sh is sourced. Re-running lunch alone
# does not refresh the OF_*/FOX_* variables.
source build/envsetup.sh
lunch twrp_merlinx-eng

# The ramdisk staging directory is not always reinstalled on incremental
# builds, so freshly linked libraries can be left out of the image. Clearing it
# is cheap and avoids a whole class of confusing results.
rm -rf "$OUT/recovery" "$OUT/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp"

mka -j"$(nproc --all)" recoveryimage
