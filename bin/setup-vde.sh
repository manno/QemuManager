#!/bin/sh
TAP=tap0

if pidof vde_switch; then
    exit 0
fi

# Start switching daemon, create interface
killall vde_switch
vde_switch --sock /tmp/vde.ctl --group adm --mod 770 --tap $TAP --daemon
sleep 1
chown root:adm /tmp/vde.ctl

# Setup interface
ifconfig $TAP up
if ! ip link show dev br0 |grep -q UP; then
    # FIXME?
    echo "Failed to bring up $TAP"
    exit 1
fi

# Setup the bridge
if ! ip link show dev br0 |grep -q UP; then
    ifup br0
fi

# Add interface to bridge
if ! brctl show br0 | grep -q $TAP; then 
    brctl addif br0 $TAP
fi

# Sanity Check
if ! brctl show br0 | grep -q $TAP; then 
    echo "Failed to add $TAP to br0"
    exit 1
fi
