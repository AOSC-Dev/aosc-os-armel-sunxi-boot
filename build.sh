#! /bin/bash

. ./list.sh

# Logic Code

echo "Checking whether the sources tarball is unique..."
if [ "$(echo linux-*.tar.* | wc -w)" != "1" ]; then
	echo "More than one linux kernel sources. Exit."
	exit 1
fi
if [ "$(echo u-boot-*.tar.* | wc -w)" != "1" ]; then
	echo "More than one u-boot sources. Exit."
	exit 1
fi
LINUX_SRC="https://github.com/AOSC-Dev/linux"
UBOOT_SRC="https://github.com/AOSC-Dev/u-boot"

LINUX_BRANCH="aosc-sunxi-4.13-rc6"
UBOOT_BRANCH="aosc-sunxi-v2017.09-rc1"

LINUX_DIR="linux"
UBOOT_DIR="u-boot"

UBOOT_CLONE_DIR="u-boot-repo"

echo "Cloning u-boot..."
rm -rf "$UBOOT_CLONE_DIR"
git clone "$UBOOT_SRC" "$UBOOT_CLONE_DIR" -b "$UBOOT_BRANCH" --depth 1

OUT_DIR="${PWD}/out"
mkdir -p "$OUT_DIR"

LOG_DIR="${PWD}/log"
mkdir -p "$LOG_DIR"
mkdir -p "$LOG_DIR"/patches

echo "Building u-boot..."

[ "$BUILD_UBOOT" != "0" ] &&
for i in $UBOOT_TARGETS
do
	UBOOT_CNAME="$(echo $i | cut -d = -f 1)"
	UBOOT_AOSCNAME="$(echo $i | cut -d = -f 2)"
	echo "Building u-boot for device $UBOOT_AOSCNAME..."
	rm -rf "$UBOOT_DIR"
	cp -r "$UBOOT_CLONE_DIR" "$UBOOT_DIR"
	pushd "$UBOOT_DIR"
	mkdir -p "$LOG_DIR"/u-boot-"$UBOOT_AOSCNAME"
	make "${UBOOT_CNAME}"_defconfig > "$LOG_DIR"/u-boot-"$UBOOT_AOSCNAME"/config.log 2>&1
	sed -i 's/# CONFIG_OF_LIBFDT_OVERLAY is not set/CONFIG_OF_LIBFDT_OVERLAY=y/g' .config # Configure fdt overlay command
	echo "Configured"
	make CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf- -j$(nproc) > "$LOG_DIR"/u-boot-"$UBOOT_AOSCNAME"/build.log 2>&1
	echo "Built"
	mkdir -p "$OUT_DIR"/u-boot-"$UBOOT_AOSCNAME"/
	cp u-boot-sunxi-with-spl.bin "$OUT_DIR"/u-boot-"$UBOOT_AOSCNAME"/
	echo "Copied"
	popd
	rm -rf "$UBOOT_DIR"
done

echo "Building linux..."

if [ "$BUILD_LINUX" != "0" ]; then
	echo "Building linux for KVM-disabled sunxi CPUs..."
	rm -rf "$LINUX_DIR"
	git clone "$LINUX_SRC" -b "$LINUX_BRANCH" --depth 1
	pushd "$LINUX_DIR"
	mkdir -p "$LOG_DIR"/linux-sunxi-nokvm
	cp ../sunxi-nokvm-config .config
	echo "Configured"
	# FIXME: hard coded parallel.
	make ARCH=arm CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf- DTC_FLAGS=-@ -j$(nproc) > "$LOG_DIR"/linux-sunxi-nokvm/build.log 2>&1
	echo "Built"
	TMPDIR=$(mktemp -d)
	make ARCH=arm CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf- INSTALL_MOD_PATH="$TMPDIR" modules_install > "$LOG_DIR"/linux-sunxi-nokvm/modules_install.log 2>&1
	mkdir -p "$OUT_DIR"/linux-sunxi-nokvm
	cp arch/arm/boot/zImage "$OUT_DIR"/linux-sunxi-nokvm/
	EXTRA_KMOD_DIR="$(echo "$TMPDIR"/lib/modules/*)/kernel/extra"
	mkdir -p "$EXTRA_KMOD_DIR"
	for i in ../extra-kmod/*
	do
		export KDIR=$PWD ARCH=arm CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf-
		pushd $i
		sh build.sh >> "$LOG_DIR"/linux-sunxi-nokvm/extra_kmod.log 2>&1
		cp *.ko "$EXTRA_KMOD_DIR/"
		popd
		unset KDIR
	done
	depmod -b "$TMPDIR" $(basename $(readlink -f $EXTRA_KMOD_DIR/../..))
	echo "Extra modules built"
	cp -r "$TMPDIR"/lib/modules/ "$OUT_DIR"/linux-sunxi-nokvm/
	rm -r "$TMPDIR"
	echo "Copied"
	echo "Building linux for KVM-enabled sunxi CPUs..."
	mkdir -p "$LOG_DIR"/linux-sunxi-kvm
	cp ../sunxi-kvm-config .config
	echo "Configured"
	make ARCH=arm CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf- DTC_FLAGS=-@ -j$(nproc) > "$LOG_DIR"/linux-sunxi-kvm/build.log 2>&1
	echo "Built"
	TMPDIR=$(mktemp -d)
	make ARCH=arm CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf- INSTALL_MOD_PATH="$TMPDIR" modules_install > "$LOG_DIR"/linux-sunxi-kvm/modules_install.log 2>&1
	mkdir -p "$OUT_DIR"/linux-sunxi-kvm
	cp arch/arm/boot/zImage "$OUT_DIR"/linux-sunxi-kvm/
	EXTRA_KMOD_DIR="$(echo "$TMPDIR"/lib/modules/*)/kernel/extra"
	mkdir -p "$EXTRA_KMOD_DIR"
	for i in ../extra-kmod/*
	do
		export KDIR=$PWD ARCH=arm CROSS_COMPILE=/opt/abcross/armel/bin/armv7a-aosc-linux-gnueabihf-
		pushd $i
		sh build.sh >> "$LOG_DIR"/linux-sunxi-kvm/extra_kmod.log 2>&1
		cp *.ko "$EXTRA_KMOD_DIR/"
		popd
		unset KDIR
	done
	depmod -b "$TMPDIR" $(basename $(readlink -f $EXTRA_KMOD_DIR/../..))
	echo "Extra modules built"
	cp -r "$TMPDIR"/lib/modules/ "$OUT_DIR"/linux-sunxi-kvm/
	rm -r "$TMPDIR"
	echo "Copied"
	popd
fi

echo "Building DTBs..."

[ "$BUILD_DTB" != "0" ] &&
for i in $DTB_TARGETS
do
	DTB_CNAME="$(echo $i | cut -d = -f 1)"
	DTB_AOSCNAME="$(echo $i | cut -d = -f 2)"
	mkdir -p "$OUT_DIR"/dtb-"$DTB_AOSCNAME"
	cp "$LINUX_DIR"/arch/arm/boot/dts/"$DTB_CNAME".dtb "$OUT_DIR"/dtb-"$DTB_AOSCNAME"/dtb.dtb
	echo "Copied dtb for $DTB_AOSCNAME"
done
