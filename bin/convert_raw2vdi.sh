#!/bin/sh

org=$1
if [ ! -f "$org" ]; then
    echo "file not found: $org"
    echo "usage: $0 test.raw"
    exit 1
fi

time VBoxManage convertdd "$org" "$org".vdi
time VBoxManage modifyvdi `pwd`/"$org".vdi compact

