P=$1
qemu-img convert $P $(basename $P vmdk)cow
