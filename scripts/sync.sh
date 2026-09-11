#!/bin/bash
# Sync an OrangeFox 12.1 tree for merlinx.
set -e
DIR=${1:-$HOME/fox_12.1}
mkdir -p "$DIR" && cd "$DIR"

repo init -u https://gitlab.com/OrangeFox/sync.git -b fox_12.1 --depth=1

mkdir -p .repo/local_manifests
curl -fsSL -o .repo/local_manifests/merlinx.xml \
  https://raw.githubusercontent.com/mt6768-place/mt6768-place-guide/recovery/local_manifests/merlinx.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc --all)"
echo "Done. Next: scripts/apply-patches.sh $DIR"
