#!/bin/sh
USERID=`whoami`
cd $HOME/qemu

# load kqemu kernel module
#sudo modprobe kqemu major=0

# QEMU binary
qemu="kvm"

usage () {
    echo "usage: $0 hd|cd|fd|grub|grml"
    echo " $0 hd hda.img"
    echo " $0 cd grm.iso"
    echo " $0 fd -hdb hdb.img"
    echo " $0 grml|grub"
    exit 1
}

# generate mac from  string
gen_mac () {
    mac=$(echo $1 |  md5sum | perl -ne '$_=~s/(..)/$1:/g; print substr($_,0,5);')
}

# networking with tap devices as bridge ports
net_tap () {
    echo "=== Setup tun/tap"
    netscript=./bin/ifup-bridgeport.sh
    #sudo chown root:adm /dev/net/tun
    #sudo chmod g+rw     /dev/net/tun
    iface=$(sudo tunctl -b -u $USERID)
    gen_mac $image
    networkopts="-net nic,macaddr=52:54:00:12:${mac},model=virtio -net tap,ifname=$iface,script=$netscript"
    trap  "echo '=== deinit $iface'; sudo tunctl -d $iface" 0 1 2 3 15
}

# vde networking
net_vde () {
    echo "=== Setup vde"
    #if ! sudo ./bin/setup-vde.sh; then
    if ! sudo ./bin/setup-vde-masq.sh; then
        echo "Exiting..."
        exit 1
    fi
    qemu="vdeq $qemu"
    #networkopts="-net nic,vlan=0 -net vde,vlan=0,sock=/tmp/vde.ctl"
    if [ -z $QEMU_MAC ]; then
        n1=$( perl -e 'print int(rand(100));' )
        n2=$( perl -e 'print int(rand(100));' )
        QEMU_MAC="52:54:00:12:${n1}:${n2}"
    fi
    networkopts="-net nic,macaddr=$QEMU_MAC -net vde,sock=/tmp/vde.ctl"
}

# FIXME getopt
# commandline options
func=$1

if [ "$2" ]; then
  image=$2
  shift 2
else
  shift 1
fi
opt="-m 1024 -usb -usbdevice tablet $*" #-soundhw all

# init network
#net_vde
net_tap

# /usr/bin/kvm
# 	-S
# 	-M pc
# 	-m 830
# 	-smp 1
# 	-name hostname
# 	-uuid 7faf780b-ed56-49a2-9ec4-948707f34789
# 	-monitor unix:/var/run/libvirt/qemu/hostname.monitor,server,nowait
# 	-boot c
# 	-drive file=,if=ide,media=cdrom,index=2
# 	-drive file=/dev/Debian/Router,if=virtio,index=0,boot=on
# 	-drive file=/dev/mapper/data,if=virtio,index=1
# 	-net nic,macaddr=00:01:01:01:01:00,vlan=0,model=virtio,name=virtio.0
# 	-net tap,fd=16,vlan=0,name=tap.0
# 	-net nic,macaddr=00:01:01:01:01:01,vlan=1,model=virtio,name=virtio.1
# 	-net tap,fd=17,vlan=1,name=tap.1
# 	-serial pty
# 	-parallel none
# 	-usb
# 	-usbdevice tablet
# 	-vnc 10.1.1.2:0
# 	-k en-us
# 	-vga cirrus


# qemu options
# method: hda|fda|cdrom
#   boot:  c | a | d
case "$func" in
    # generic boot targets, provide image
    qemu)
        [ "$image" ] || usage
        cmd="$qemu $networkopts -hda $image $opt"
        echo $cmd; $cmd
    ;;
    hd)
        [ "$image" ] || usage
        cmd="$qemu $networkopts -drive file=${image},if=virtio,index=0,boot=on $opt"
        echo $cmd; $cmd
    ;;
    cd|cdiso)
        [ "$image" ] || usage
        #$qemu $networkopts -boot d -cdrom $image $opt
        $qemu $networkopts -boot d -drive file=${image},if=ide,media=cdrom,index=0,boot=on $opt
    ;;
    install)
        # fixup parameters
        image2=`expr "$opt" : '.* \(.*\)'`    # LAST ARGUMENT
        opt=`expr "$opt" : '\(.*\) .*'`       # ALL BUT LAST ARGUMENT
        $qemu $networkopts -boot d \
          -drive file=${image},if=ide,media=cdrom,index=1 \
          -drive file=${image2},if=virtio,index=0,boot=on $opt
    ;;
    fd|floppy)
        [ "$image" ] || usage
        $qemu $networkopts -boot a -fda $image $opt
    ;;
    # special os boot targets
    games)
        $qemu $networkopts -hda winxppro-host-planescape.qcow -soundhw es1370 -std-vga $opt
    ;;
    *)
        usage
    ;;
esac


