#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)."
  exit 1
fi

# 1. Get the current running kernel version
KERNEL_VERSION=$(uname -r)
echo "Current kernel version: ${KERNEL_VERSION}"

# 2. Define standard paths for the kernel image and initramfs
# Note: Paths vary slightly between Linux distributions.
if [ -f "/boot/vmlinuz-${KERNEL_VERSION}" ]; then
    KERNEL_IMG="/boot/vmlinuz-${KERNEL_VERSION}"
elif [ -f "/boot/vmlinux-${KERNEL_VERSION}" ]; then
    KERNEL_IMG="/boot/vmlinux-${KERNEL_VERSION}"
else
    echo "Error: Kernel image for ${KERNEL_VERSION} not found in /boot."
    exit 1
fi

# Find matching initramfs / initrd
if [ -f "/boot/initramfs-${KERNEL_VERSION}.img" ]; then
    INITRD_IMG="/boot/initramfs-${KERNEL_VERSION}.img"
elif [ -f "/boot/initrd.img-${KERNEL_VERSION}" ]; then
    INITRD_IMG="/boot/initrd.img-${KERNEL_VERSION}"
elif [ -f "/boot/initrd-${KERNEL_VERSION}" ]; then
    INITRD_IMG="/boot/initrd-${KERNEL_VERSION}"
else
    echo "Error: Initramfs/Initrd image for ${KERNEL_VERSION} not found in /boot."
    exit 1
fi

echo "-> Found Kernel: ${KERNEL_IMG}"
echo "-> Found Initrd: ${INITRD_IMG}"

# 3. Load the kernel into memory with the current boot command-line arguments
echo "Loading kernel into kexec memory..."
kexec -l "${KERNEL_IMG}" --initrd="${INITRD_IMG}" --reuse-cmdline

if [ $? -eq 0 ]; then
    echo "Kernel successfully loaded."
    echo "Rebooting now via systemd (graceful)..."

    # 4. Trigger the kexec reboot sequence
    # This shuts down services cleanly before jumping to the new kernel.
    systemctl kexec
else
    echo "Failed to load the kernel into kexec."
    exit 1
fi
