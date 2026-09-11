#!/bin/bash
# Sincroniza el arbol de PixelOS 17 con los trees de mt6768-place.
set -e
DIR=${1:-$HOME/pixelos-merlinx}
mkdir -p "$DIR" && cd "$DIR"

repo init -u https://github.com/PixelOS-AOSP/manifest.git -b seventeen --git-lfs --depth=1

mkdir -p .repo/local_manifests
curl -fsSL -o .repo/local_manifests/merlinx.xml \
  https://raw.githubusercontent.com/mt6768-place/mt6768-place-guide/main/local_manifests/merlinx.xml

repo sync -c --force-sync --no-clone-bundle --no-tags -j"$(nproc --all)"
echo "Listo. Ahora aplica los parches: scripts/apply-patches.sh $DIR"
