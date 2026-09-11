#!/bin/bash
# Parches sobre repos de TWRP/AOSP/OrangeFox que no alojamos.
# Sin ellos la build falla o el recovery no descifra.
set -e
DIR=${1:-$HOME/fox_12.1}
HERE=$(cd "$(dirname "$0")/.." && pwd)

apply() {
  local p="$DIR/$1" f="$HERE/patches/$2"
  if git -C "$p" apply --check "$f" 2>/dev/null; then
    git -C "$p" apply "$f" && echo "  OK   $1"
  elif git -C "$p" apply --reverse --check "$f" 2>/dev/null; then
    echo "  YA   $1 (ya estaba aplicado)"
  else
    echo "  FALLO $1 -- revisalo a mano"; return 1
  fi
}

apply system/vold        0001-vold-fbe-fixes.patch
apply system/tools/aidl  0002-aidl-uninitialized-pointer.patch
apply bootable/recovery  0003-twrp-theme-absolute-out.patch
apply vendor/recovery    0004-orangefox-isolate-tmp.patch
echo "Parches aplicados."
