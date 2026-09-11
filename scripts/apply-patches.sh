#!/bin/bash
# Patches against TWRP/AOSP/OrangeFox repositories we do not mirror.
# Without them the build either fails or produces a recovery that boots but
# cannot decrypt.
set -e
DIR=${1:-$HOME/fox_12.1}
HERE=$(cd "$(dirname "$0")/.." && pwd)

apply() {
  local p="$DIR/$1" f="$HERE/patches/$2"
  if git -C "$p" apply --check "$f" 2>/dev/null; then
    git -C "$p" apply "$f" && echo "  OK       $1"
  elif git -C "$p" apply --reverse --check "$f" 2>/dev/null; then
    echo "  ALREADY  $1"
  else
    echo "  FAILED   $1 -- apply it by hand"; return 1
  fi
}

apply system/vold        0001-vold-fbe-fixes.patch
apply system/tools/aidl  0002-aidl-uninitialized-pointer.patch
apply bootable/recovery  0003-twrp-theme-absolute-out.patch
apply vendor/recovery    0004-orangefox-isolate-tmp.patch
echo "Patches applied."
