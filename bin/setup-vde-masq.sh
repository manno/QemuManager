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

# Setup networking
ifconfig tap0 10.111.111.254 broadcast 10.111.111.255 netmask 255.255.255.0
echo "1" > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# start dnsmasq for dns/dhcp
# FIXME
