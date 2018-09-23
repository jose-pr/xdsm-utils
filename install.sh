#!/bin/sh
set -e

targetRoot="$1"
targetDst="${2:-opt/xpenology-elves}"
target="$targetRoot/$targetDst"
src="$(dirname $0)"
echo "Installation Directory: $target"
echo "Source Directory: $src"
mkdir -p "$target"
cp -R "$src"/* "$target"
rm -f "$target/*.sh"
ls -R "$target"
chmod +x "$target/bin/xdsm-utils"
