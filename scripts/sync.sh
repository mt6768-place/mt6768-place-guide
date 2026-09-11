#!/bin/bash
# Sync a PixelOS 17 tree using the mt6768-place device trees.
set -e
DIR=${1:-$HOME/pixelos-merlinx}
mkdir -p "$DIR" && cd "$DIR"

repo init -u https://github.com/PixelOS-AOSP/manifest.git -b seventeen --git-lfs --depth=1

mkdir -p .repo/local_manifests
curl -fsSL -o .repo/local_manifests/merlinx.xml \
  https://raw.githubusercontent.com/mt6768-place/mt6768-place-guide/main/local_manifests/merlinx.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc --all)"
echo "Done. Next: scripts/apply-patches.sh $DIR"
