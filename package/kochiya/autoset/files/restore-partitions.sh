#!/bin/sh
# Non-destructive restore of the eMMC p3/p4 partition entries after a
# flash that removed them but left the filesystems intact.
#
# ShiMeta AIOT-3588A, 58.24 GiB eMMC (122142720 sectors of 512 bytes):
#   p1 16 MiB   kernel
#   p2 3.6 GiB  squashfs rootfs
#   p3 30 GiB   docker   (sectors 7606272 .. 70520831)   [2026-11-21 由 16G 扩容]
#   p4 rest     emmc     (sectors 70520832 .. last ≈ 24.6 GiB)
#
# NEVER run mklabel or mkfs here: the old ext4 filesystems (and the
# docker/postgres/model-cache data) are still on the disk.
# NOTE: p4 在 2026-11-21 分区调整时按原 UUID 重建（e2284cfd-5a48-4559-8835-cc611b480214），
# fstab 按 UUID 挂载不受影响。
set -e

DEV=/dev/mmcblk0
P3_START=7606272
P3_END=70520831
P4_START=70520832

[ -b "$DEV" ] || { echo "missing $DEV"; exit 1; }

SECTORS=$(cat /sys/block/mmcblk0/size)
echo "eMMC sectors: $SECTORS"

if [ -b "${DEV}p3" ] || [ -b "${DEV}p4" ]; then
	echo "p3/p4 already present, nothing to do:"
	parted -s "$DEV" unit s print
	exit 0
fi

[ "$SECTORS" -gt "$P4_START" ] || { echo "disk smaller than expected"; exit 1; }

parted -s "$DEV" unit s mkpart primary ext4 "$P3_START" "$P3_END"
parted -s "$DEV" unit s mkpart primary ext4 "$P4_START" "$((SECTORS - 1))"
parted -s "$DEV" unit s print

echo "partition entries restored; mounting without formatting"
mkdir -p /opt/docker /mnt/emmc
mountpoint -q /opt/docker || mount "${DEV}p3" /opt/docker
mountpoint -q /mnt/emmc || mount "${DEV}p4" /mnt/emmc
df -h /opt/docker /mnt/emmc
blkid "${DEV}p3" "${DEV}p4"
echo "now start docker: /etc/init.d/dockerd start"
