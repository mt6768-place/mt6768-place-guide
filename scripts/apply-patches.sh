#!/bin/bash
# Apply the changes that live in AOSP repositories we do not mirror.
# They are one to a few lines each; forking AOSP for that would add nothing.
set -e
DIR=${1:-$HOME/pixelos-merlinx}
HERE=$(cd "$(dirname "$0")/.." && pwd)

apply() { # apply <relative path> <patch>
  local p="$DIR/$1" f="$HERE/patches/$2"
  if git -C "$p" apply --check "$f" 2>/dev/null; then
    git -C "$p" apply "$f" && echo "  OK       $1"
  elif git -C "$p" apply --reverse --check "$f" 2>/dev/null; then
    echo "  ALREADY  $1"
  else
    echo "  FAILED   $1 -- apply it by hand"; return 1
  fi
}

apply external/libmnl            0001-libmnl-drop-vendor-variant.patch
apply frameworks/av              0002-AudioTrack-restore-pre-a17-abi.patch
apply frameworks/opt/telephony   0003-telephony-allow-mtk-subclassing.patch
echo "Patches applied."
