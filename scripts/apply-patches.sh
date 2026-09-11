#!/bin/bash
# Aplica los parches de los repos de AOSP que no alojamos (son cambios de una
# o pocas lineas; no tiene sentido forkear AOSP entero para eso).
set -e
DIR=${1:-$HOME/pixelos-merlinx}
HERE=$(cd "$(dirname "$0")/.." && pwd)

apply() { # apply <ruta-relativa> <parche>
  local p="$DIR/$1" f="$HERE/patches/$2"
  if git -C "$p" apply --check "$f" 2>/dev/null; then
    git -C "$p" apply "$f" && echo "  OK   $1"
  elif git -C "$p" apply --reverse --check "$f" 2>/dev/null; then
    echo "  YA   $1 (ya estaba aplicado)"
  else
    echo "  FALLO $1 -- revisalo a mano"; return 1
  fi
}

apply external/libmnl            0001-libmnl-drop-vendor-variant.patch
apply frameworks/av              0002-AudioTrack-restore-pre-a17-abi.patch
apply frameworks/opt/telephony   0003-telephony-allow-mtk-subclassing.patch
echo "Parches aplicados."
