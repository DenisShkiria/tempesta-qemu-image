#!/bin/sh
set -e

git clone --depth 1 https://github.com/tempesta-tech/linux-5.10.35-tfw

# TODO
#cd linux-5.10.35-tfw
#make clean && make mrproper
#cp /boot/config-$(uname -r) .config
#sed -i 's/CONFIG_SYSTEM_TRUSTED_KEYRING/#CONFIG_SYSTEM_TRUSTED_KEYRING/' .config
#sed -i 's/CONFIG_SYSTEM_TRUSTED_KEYS/#CONFIG_SYSTEM_TRUSTED_KEYS/' .config
#sed -i 's/CONFIG_DEFAULT_SECURITY_/#CONFIG_DEFAULT_SECURITY_/' .config
#sed -i 's/CONFIG_LSM=/#CONFIG_LSM=/' .config
#sed -i 's/CONFIG_DEBUG_INFO_BTF=/#CONFIG_DEBUG_INFO_BTF=/' .config
#echo 'CONFIG_LSM="tempesta,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf"' >> .config
#
#echo "Kernel config:"
#cat .config
#
#make olddefconfig
#
#echo "Build .deb for kernel"
#make deb-pkg -j$(nproc)