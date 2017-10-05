#!/bin/sh
cd /dev/shm && \
mkdir secmount && \
cd secmount && \
cryptfs-tpm2 unseal passphrase -P auto -o passphrase && \
cryptsetup luksOpen /dev/sda4 secure --key-file passphrase && \
mount /dev/mapper/secure /secure && \
rm passphrase && \
cd .. && \
rm -rf secmount

