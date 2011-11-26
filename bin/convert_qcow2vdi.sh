#!/bin/sh

org=$1
if [ ! -f "$org" ]; then
    echo "file not found: $org"
    echo "usage: $0 test.qcow"
    exit 1
fi

time qemu-img convert -O raw "$org"  "$org".raw
time VBoxManage convertdd "$org".raw "$org".vdi
time VBoxManage modifyvdi `pwd`/"$org".vdi compact
time rm "$org".raw

