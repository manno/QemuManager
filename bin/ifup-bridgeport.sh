#!/bin/bash
BRIDGE=br0
DEV=$1
sudo -p "Password for $0:" /bin/sh -c "/sbin/brctl addif ${BRIDGE} ${DEV}; /sbin/ifconfig ${DEV} up" 
