# tpm2-luks

Back in the day when the world was just adopting smartphones, we came up with the [idea](https://www.google.com/patents/US7971229) of a non-obtrusive system for securing a mobile phone.

The idea was that if a particular "agent" was installed on the device, the device would function as per normal. However, if the "agent" was removed/changed, the device would be locked out and safe.

Fast-forward many-many years later and we have the [Trusted Platform Module](https://en.wikipedia.org/wiki/Trusted_Platform_Module). The idea is that the hardware (BIOS) + Software (OS) create a few unique properties stored in memory locations called [Platform Configuration Registers (PCRs)](https://docs.microsoft.com/en-us/windows/device-security/tpm/switch-pcr-banks-on-tpm-2-0-devices).

The TPM architecture also allows non-volatile storage of information that can be "sealed" based on the value of the PCRs. If the PCRs do not change, the OS can retrieve the stored information transparently (for example, the pass-phrase for a [LUKS](https://guardianproject.info/code/luks/) encrypted volume). 

But if the PCRs change, the information cannot be retrieved and the encrypted drive is forever locked out.

## TPM 1.2 and LUKS

While researching how to create a secure partition on Ubuntu (16.04 LTS), I came across a few articles on [how to do this](http://tomkowapp.com/2016/04/09/Ubuntu-TPM-encryption/) for devices with TPM 1.2.

However, for TPM 2.0, information was scarce and fragmented. Since I spent a fair amount of time in researching the tools, I thought I would put together a short note + a few files for future reference and to help others who might be wishing to do a similar thing.

## TPM 2.0 Installing the Tools

First, you can install all the dependencies in one go:

```
sudo apt -y install \
  autoconf-archive \
  libcmocka0 \
  libcmocka-dev \
  build-essential \
  git \
  pkg-config \
  gcc \
  g++ \
  m4 \
  libtool \
  automake \
  autoconf \
  libdbus-glib-1-dev \
  libssl-dev \
  glib2.0 \
  cmake \
  libssl-dev \
  libcurl4-gnutls-dev
```

Once you are done with that, you need to build and install the [TPM Software Stack (tpm2-tss) library](https://github.com/01org/tpm2-tss) which you can obtain from [here](https://github.com/01org/tpm2-tss/releases/tag/1.2.0). I downloaded the .tar.gz file. 

After that, you can uncompress the file in a folder and execute the following:

```
cd tpm2-tss-1.2.0
./configure
make
sudo make install
sudo ldconfig
cd ..
```

The next tool we need is the [TPM Access Broker and Resource Manager](https://github.com/01org/tpm2-abrmd) which you can get from [here](https://github.com/01org/tpm2-abrmd/releases/tag/1.1.1). Again, I downloaded the .tar.gz file. 

Following that, after uncompressing the file, you can execute the following steps:

### Adding user:
```
sudo useradd --system --user-group ts
```

### Build:
```
cd tpm2-abrmd-1.1.1
./configure --with-dbuspolicydir=/etc/dbus-1/system.d --with-systemdsystemunitdir=/lib/systemd/system --with-udevrulesdir=/etc/udev/rules.d
make
sudo make install
cd ..
```

### Post-build:
```
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo pkill -HUP dbus-daemon
sudo systemctl daemon-reload
sudo ldconfig
sudo systemctl enable tpm2-abrmd
sudo service start tpm2-abrmd
```


You can verify that this was installed successfully by checking the status:
```
systemctl status tpm2-abrmd.service
```
Which should give you an output like the following:
```
● tpm2-abrmd.service - TPM2 Access Broker and Resource Management Daemon
   Loaded: loaded (/lib/systemd/system/tpm2-abrmd.service; enabled; vendor preset: enabled)
   Active: active (running) since Thu 2017-10-05 22:04:25 SGT; 1h 9min ago
 Main PID: 1027 (tpm2-abrmd)
   CGroup: /system.slice/tpm2-abrmd.service
           └─1027 /usr/local/sbin/tpm2-abrmd

Oct 05 22:04:25 seventhsense-cpu-01 systemd[1]: Starting TPM2 Access Broker and Resource Management Daemon...
Oct 05 22:04:25 seventhsense-cpu-01 systemd[1]: Started TPM2 Access Broker and Resource Management Daemon.
```


The third tool to install is the [TPM 2 Tools](https://github.com/01org/tpm2-tools) which you can download from [here](https://github.com/01org/tpm2-tools/releases/tag/2.1.0). Again, I downloaded the tar file and uncompressed it in my working folder.

Then build and install:
```
cd tpm2-tools-2.1.0
# Note the following command needs to be executed twice
./bootstrap
./bootstrap
./configure
make
sudo make install
cd ..
```

Now, we are ready to install the final tool which is called [cryptfs-tpm2](https://github.com/WindRiver-OpenSourceLabs/cryptfs-tpm2) which has no releases (as on the date of this writing). So, we need to clone the repository:
```
git clone https://github.com/WindRiver-OpenSourceLabs/cryptfs-tpm2
cd cryptfs-tpm2
make
sudo make install
sudo ldconfig
```

Next, you can take ownership of the TPM module:
```
tpm2_takeownership -c
tpm2_takeownership -L some_password
```

You may get an error after `tpm2_takeownership -L some_password`, but you can verify that ownership has indeed been taken by trying `tpm2_takeownership -c` again which should now return an error.

## Configuration changes

With the default configuration of GRUB, a user can enter recovery mode and be root at the shell. We want to disable this option.

Let's edit the GRUB configuration file. Type the following to open the file:
```
sudo gedit /etc/default/grub
```
Change the commented line from:
```
#GRUB_DISABLE_RECOVERY="true"
```
to
```
GRUB_DISABLE_RECOVERY="true"
```

Then:
```
sudo update-grub
```

Also, it might be advisable to disable the guest account. To do so, create a file `/etc/lightdm/lightdm.conf.d/50-no-guest.conf` by typing `sudo gedit /etc/lightdm/lightdm.conf.d/50-no-guest.conf`. Then put the following contents in the file and save.

```
[SeatDefaults]
allow-guest=false
```

One more step which I would recommend is setting up a password for your BIOS.

**As these steps can affect the PCR values, it is advisable you complete them before the next step.**

## LUKS

For this section, it is assumed that you have an Ext4 partition that is not currently mounted. Here, the name of the partition is `/dev/sda4`. If the partition is mounted, first unmount it:
```
sudo umount /dev/sda4
```

Next, lets create and store the passphrase in the TPM:
```
# Switch to volatile RAM to avoid leaving traces of passphrase on the disk.
cd /dev/shm
mkdir keysetup
cd keysetup
sudo cryptfs-tpm2 -v seal all -P auto
sudo cryptfs-tpm2 unseal passphrase -P auto -o passphrase
```

Now, we have a 32 byte passphrase in `/dev/shm/keysetup/passphrase`. We can now create the LUKS container and mount it:
```
sudo cryptsetup -y -v luksFormat /dev/sda4 --key-file passphrase
sudo cryptsetup luksOpen /dev/sda4 secure --key-file passphrase
sudo mkfs.ext4 /dev/mapper/secure
# Remove transient passphrase
rm passphrase
cd ..
rm -rf keysetup
sudo mkdir /secure
sudo mount /dev/mapper/secure /secure
```

## Auto-mounting the partition on boot

Ideally, we would like for this partition to be auto-mounted on boot so that we can install secure services/data on this partition seamlessly.

Then, if the system is tampered with, the mounting of this partition will fail (due to changed PCRs) and data/IP will not be compromised.

First, we want to ensure that `/secure` (where we mounted the partition) is accessible for both your current account (here `account`) and a special account we create to be able to run systemd services from this partition.

For this purpose, we first create a group called `secure`:
```
# Create the group
sudo groupadd secure
# Add 'account' to the group
sudo usermod -a -G secure account
# Change ownership of the mount point
sudo chown account:secure /secure
# Allow members of secure group to read/write/execute from /secure
sudo chmod -R g+rwx /secure
# Allow no other users to access /secure
sudo chmod -R o-rww /secure
# Add a system account to run systemd services from /secure
sudo useradd --system secservice
# Add the user to the secure group
sudo usermod -a -G secure secservice
```

We are almost done! Now we just need to create a systemd service that mounts the drive on boot:
```
# Our shell scripts to be executed by the service
sudo mkdir /secmount
cd <your working directory for this tutorial>
sudo cp *.* /secmount
sudo systemctl enable /secmount/secmount.service
sudo service secmount start
systemctl status secmount
```
If all went well, you should see:
```
● secmount.service - Mounts the encrypted partition
   Loaded: loaded (/secmount/secmount.service; enabled; vendor preset: enabled)
   Active: active (exited) since Thu 2017-10-05 22:04:27 SGT; 1h 37min ago
  Process: 1097 ExecStart=/secmount/mount.sh (code=exited, status=0/SUCCESS)
 Main PID: 1097 (code=exited, status=0/SUCCESS)
   CGroup: /system.slice/secmount.service

Oct 05 22:04:25 seventhsense-cpu-01 systemd[1]: Starting Mounts the encrypted partition...
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Thu Oct  5 22:04:25 SGT 2017: [INFO] Use tabrmd as the default tcti interfa
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Thu Oct  5 22:04:25 SGT 2017: [INFO] SHA-1 PCR bank voted
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Cryptfs-TPM 2.0 tool
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: (C)Copyright 2016-2017, Wind River Systems, Inc.
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Version: 0.6.0+git-cf736b0fe06e8ce46232e9bc6f24817405f902b9
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Build Machine: seventhsense@Linux seventhsense-cpu-01 4.10.0-35-generic #39
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Build Time: Oct  5 2017 19:45:27
Oct 05 22:04:25 seventhsense-cpu-01 mount.sh[1097]: Thu Oct  5 22:04:25 SGT 2017: [INFO] Succeed to unseal the passphrase (32-b
Oct 05 22:04:27 seventhsense-cpu-01 systemd[1]: Started Mounts the encrypted partition.
```

You should be able to access `/secure` just like any other directory. 
```
cd /secure
touch my_new_file
ls
```

To test it a bit more, you can turn off the service:
```
sudo service secmount stop
```
When stopped, the directory `/secure` will be empty. Then start it back up again:
```
sudo service secmount start
```
Now the directory will have your file.

## Moving PostgreSQL 9.6 to the secure partition

If you have PostgreSQL installed, the following snippet can help you move it to the secure partition. A similar technique may be applied to MySQL or any other database. You may change the snippet below as per your needs
```
# Move postgresql database
sudo systemctl stop postgresql
sudo rsync -av /var/lib/postgresql /secure
sudo mv /var/lib/postgresql/9.6/main /var/lib/postgresql/9.6/main.bak
sudo sed -i "s/data_directory = '\/var\/lib\/postgresql\/9.6\/main'/data_directory = '\/secure\/postgresql\/9.6\/main'/" /etc/postgresql/9.6/main/postgresql.conf
sudo sed -i "s/\[Unit\]/\[Unit\]\nAfter=secmount.service/" /lib/systemd/system/postgresql.service
sudo sed -i "s/\[Unit\]/\[Unit\]\nAfter=secmount.service/" /lib/systemd/system/postgresql@.service
sudo systemctl daemon-reload
sudo systemctl start postgresql
```

After verifying that it is working (even after a reboot), you can delete the backup folder:
```
sudo rm -rf /var/lib/postgresql/9.6/main.bak
```

## Caution

Please use the work presented here responsibly and **AT YOUR OWN RISK**. Its purpose is mainly to serve as an introduction to TPM 2.0 and LUKS. 

This method is tested using Ubuntu version:
```
> lsb_release -a
No LSB modules are available.
Distributor ID:	Ubuntu
Description:	Ubuntu 16.04.3 LTS
Release:	16.04
Codename:	xenial

```
and on Intel NUC6i7KYK. 

### **IF YOUR SETUP IS DIFFERENT, THE STEPS MAY NOT WORK AS DESCRIBED HERE.**

It is also advisiable to maintain a copy of the passphrase on some secure medium so that you can change the passphrase in case the PCRs change (Linux GRUB update might change them for example).

I have an encrypted home folder. While setting up Ubuntu, if you chose this option, then you can store the passphrase in your home folder.

```
cd ~
sudo cryptfs-tpm2 unseal passphrase -P auto -o passphrase
```

Now you should have a copy of the passphrase in your home directory. If the PCRs change, you can change the passphrase by supplying the old passphrase saved in your encrypted home directory.

## License

```
MIT License

Copyright (c) 2017 Varun Chatterji

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

