#!/bin/bash
# Compila OrangeFox. Ojo: 'source build/envsetup.sh' tiene que ejecutarse en
# el shell, no dentro de una tuberia, o sus variables no persisten.
set -e
DIR=${1:-$HOME/fox_12.1}
cd "$DIR"

export ALLOW_MISSING_DEPENDENCIES=true
export FOX_BUILD_DEVICE=merlinx
export LC_ALL=C

source build/envsetup.sh
lunch twrp_merlinx-eng

# vendorsetup.sh solo se ejecuta al hacer source de envsetup.sh; si solo
# relanzas lunch, las variables OF_*/FOX_* no se refrescan.

# El staging del ramdisk no siempre se reinstala en builds incrementales:
# librerias recien enlazadas se quedan fuera de la imagen. Borrarlo es barato.
rm -rf "$OUT/recovery" "$OUT/obj/PACKAGING/recovery_intermediates/ramdisk_files-timestamp"

mka -j"$(nproc --all)" recoveryimage
