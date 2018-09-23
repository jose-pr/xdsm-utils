# xdsm-utils
Xpenology Build and server helper functions

Based on the tutorial at https://xpenology.club/compile-drivers-xpenology-with-windows-10-and-build-in-bash/ I made some helper functions to help with creating the virtio modules but can be used for any other modules.

To use download xdsm-build-utils.sh
The you can use it as follows:
For all commands you can specify
--version [6.1,6.2] defaults to 6.1
--arch [bromolow,broadwell] defaults to bromolow
--path [/path/to/use/as/working/directory] defaults to ./dsm

Download syno src for the linux kernel and the toolchain, also downloads install.sh and xdsm-utils.sh
and a modified jun.patch 
You will need to manually download the synoboot.img for your system and place it in the dsm/srcs folder named as : [arch]-[version]-synoboot.img ex: bromolow-6.2-synoboot.img

xdsm-build-utils.sh downloadSrcFiles --arch bromolow --version 6.2

Prepare Staging area will unpack srcs and toolchain

xdsm-build-utils.sh prepareStagingArea

Add modules for KVM/QUEMU 
virtio_net virtio_pci virtio_scsi 
Also sriov ixgbevf igbvf

xdsm-build-utils.sh addKVMModules

Compile Modules

xdsm-build-utils.sh compileModules

modify synoboot.img with new modules

xdsm-build-utils.sh modifySynoboot

Theere are also other nice functions such as to mount synoboot grub or synoboot partition
xdsm-build-utils.sh mountGrub synoimage.img /mnt/point
xdsm-build-utils.sh mountSynoboot synoimage.img /mnt/point


As this is a simple bash script you can open it and view some of the other helpers such as to unpack/pack lzma files.


The xdsm-utils is installed on the xpenology device and has some functions to obtian real macs for the eth devices, generate a random serial number, get the boot device pid/vid and also to modofu the grub enviromental values or to read them.
/opt/xpenology-elves/bin/xdsm-utils getRealMACs
/opt/xpenology-elves/bin/xdsm-utils setMACsEnv
/opt/xpenology-elves/bin/xdsm-utils generateSerial
/opt/xpenology-elves/bin/xdsm-utils setSerialEnv
/opt/xpenology-elves/bin/xdsm-utils getBootDevInfo
/opt/xpenology-elves/bin/xdsm-utils setBootEnvs
/opt/xpenology-elves/bin/xdsm-utils getGrubEnvVars
/opt/xpenology-elves/bin/xdsm-utils setGrubEnvVar
/opt/xpenology-elves/bin/xdsm-utils mountGrub /mnt/point (defaults to /boot)
/opt/xpenology-elves/bin/xdsm-utils mountSynoboot mnt/point (defaults to /mnt/xpenoboot)

You can open the file with a text editor and see all the functions there.







