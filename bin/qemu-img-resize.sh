#!/bin/sh
# Description: resize qemu qcow image
# don't forget to commit first

FILE="$1"
TMP=$(basename "$FILE" .qcow).raw
NEW=$(basename "$FILE" .qcow).NEW.qcow
oldsize=$(qemu-img info "$FILE" | grep "virtual size" | awk '{print $3}' | sed 's/\.0G$/GB/')
# 5GB = 5000 * 1M
size="10000"

#qemu-img commit "$FILE"

echo "=== convert to raw"
qemu-img convert "$FILE" -O raw "$TMP"
echo "=== resize raw $oldsize to $size * 1MB"
dd if=/dev/zero of="$TMP" seek="$size" obs=1M count=0
echo "=== convert to compressed qcow"
qemu-img convert -c "$TMP" -O qcow "$NEW"
# ./qemu-all.sh cd isoimages/gparted-livecd-0.3.4-8.iso -hda "$NEW"

echo "=== cleanup"
rm $TMP
echo "you can now test '$NEW' and finally remove '$FILE'"
echo "don't forget to resize the filesystems!"

