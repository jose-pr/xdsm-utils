set -e

base_path=$(pwd)/dsm
arch="bromolow"
version="6.2"

if [ ! -z "${DSM_ARCH}" ]; then
    arch="${DSM_ARCH}"
fi
if [ ! -z "${DSM_VERSION}" ]; then
    version="${DSM_VERSION}"
fi
if [ ! -z "${DSM_PATH}" ]; then
    base_path="${DSM_PATH}"
fi

declare -a dsm_versions=("6.1","6.2")
declare -a arch_versions=("bromolow","broadwell")

declare -A kernel_links=(['bromolow_6.1']="https://sourceforge.net/projects/dsgpl/files/Synology%20NAS%20GPL%20Source/15047branch/bromolow-source/linux-3.10.x.txz/download" ['bromolow_6.2']="https://sourceforge.net/projects/dsgpl/files/Synology%20NAS%20GPL%20Source/22259branch/bromolow-source/linux-3.10.x.txz/download" ['broadwell_6.2']="https://sourceforge.net/projects/dsgpl/files/Synology%20NAS%20GPL%20Source/22259branch/broadwell-source/linux-3.10.x.txz/download")
declare -A toolchain_links=(['bromolow_6.1']="https://sourceforge.net/projects/dsgpl/files/DSM%206.1%20Tool%20Chains/Intel%20x86%20linux%203.10.102%20%28Bromolow%29/bromolow-gcc493_glibc220_linaro_x86_64-GPL.txz/download" ['bromolow_6.2']="https://sourceforge.net/projects/dsgpl/files/DSM%206.2%20Tool%20Chains/Intel%20x86%20linux%203.10.102%20%28Bromolow%29/bromolow-gcc493_glibc220_linaro_x86_64-GPL.txz/download" ['broadwell_6.2']="https://sourceforge.net/projects/dsgpl/files/DSM%206.2%20Tool%20Chains/Intel%20x86%20Linux%203.10.102%20%28Broadwell%29/broadwell-gcc493_glibc220_linaro_x86_64-GPL.txz/download")

declare -a kvmModules=("VIRTIO_MMIO" "VIRTIO_PCI" "VIRTIO_NET" "SCSI_VIRTIO")
declare -a sriovModules=("IXGBEVF" "IGBVF")

declare -A modulesMap=(["SCSI_VIRTIO"]="virtio_scsi")
declare -a isDiskModule=("virtio_scsi")

declare -A loadedMods
declare -a extraModsSorted
declare -a diskModsSorted

declare -a args

while [ "$1" != "" ]; do
    case $1 in
        -p|--path)
            shift
            base_path="$1";shift
        ;;
        -v|--version)
            shift
            version="$1";shift
        ;;
        -a|--arch)
            shift
            arch="$1";shift
         ;;
         -*|--*)
            echo "$1 unkown option";shift
        ;;
        *)
            args+=("$1");shift                  
    esac
done



kernel="${arch}-${version}-kernel"
toolchain="${arch}-${version}-toolchain"
build_prefix="${arch}-${version}-$(date +%s)"

#SOURCES
src_path="$base_path/srcs"
kernel_src="${src_path}/${kernel}.txz"
toolchain_src="${src_path}/${toolchain}.txz"
synoboot_src="${src_path}/${arch}-${version}-synoboot"

#STAGING AREAS
staging_path="${base_path}/staging/${arch}-${version}"
kernel_path="${staging_path}/kernel"
toolchain_path="${staging_path}/toolchain"
synoboot="${staging_path}/bootloader/synoboot"

#OUTPUT
build_path="${base_path}/builds"

#COMMANDS
dsm_make="make ARCH=x86_64 CROSS_COMPILE=${toolchain_path}/bin/x86_64-pc-linux-gnu-"

function unpackSrc(){
	src="${1:-$PWD}"
	dst="${2:-$PWD}"
    mkdir -p "${dst}"
    tar xvf "${src}" -C "${dst}" --strip-components=1 > /dev/null
}
function unpackExtraLZMA(){
	dst="${2:-$PWD/extra}"
	mkdir -p "$dst"
	cd "$dst"
	if [[ "$3" = true ]];then rm -rf ./*;fi
	lzma -d "${1:-extra.lzma}" -c | cpio -id --quiet > /dev/null
}
function packExtraLZMA(){
	dst="${2:-$PWD/extra.lzma}"
	mkdir -p "$(dirname $dst)"
	cd "${1:-$PWD}"
	(find . -name modprobe && find . \! -name modprobe) | cpio --quiet --owner root:root -oH newc | lzma -8 > "$dst"
}

function mountRawImagePartition(){
    imgpath="$1"
    partitionIndex="$2"
    mountpath="$3"
    echo "Mounting partion $partitionIndex from $imgpath on $mountpath with pwd: $(pwd)"  
    mkdir -p "$mountpath" || true
    imgInfo=$(fdisk -l "$imgpath" | grep ".img$partitionIndex")
    IFS=" " read -r -a array <<< "$imgInfo"
    mount -o loop,offset=$(((${array[1]})*512)) "$imgpath" "$mountpath" > /dev/null
}
function mountSynoboot(){
    img="${1:-$base_path/synoboot.img}"
    mnt="${2:-$base_path/synoboot}"
    mountRawImagePartition "$img" 2 "$mnt"
}
function mountGrub(){  
    img="${1:-$base_path/synoboot.img}"
    mnt="${2:-$base_path/grub}"
    mountRawImagePartition "$img" 1 "$mnt"
}

function addModuleToCompileList() {
    mod=$1
    "$kernel_path/scripts/config" --module "CONFIG_$mod"
    if [ ${modulesMap["$mod"]+_} ]; then
        driver=${modulesMap["$mod"]}
    else
        driver="${mod,,}" 
    fi
    touch "$staging_path/inserted_modules"
    grep -q -F "$driver" "$staging_path/inserted_modules" || echo "$driver" >> "$staging_path/inserted_modules"
}
function proccessModules(){	
    source "$staging_path/extra/etc/rc.modules"
    IFS=" " read -r -a extraModules <<< "$EXTRA_MODULES"
    IFS=" " read -r -a diskModules <<< "$DISK_MODULES"      
    
	while IFS='' read -r mod || [[ -n "$mod" ]]; do
        if [ -z "${mod// }" ];then continue;fi       
        if echo ${extraModules[@]} | grep -q -w -v "$mod" &&  echo ${diskModules[@]} | grep -q -w -v "$mod" ; then
            if echo ${isDiskModule[@]} | grep -q -w "$mod";then
                diskModules+=("$mod")
            else     
                extraModules+=("$mod")
            fi
        fi
    done  < "$staging_path/inserted_modules"
	
	for mod in "${diskModules[@]}";do
		proccessMod "$mod" true # > /dev/null
	done
	for mod in "${extraModules[@]}";do
		proccessMod "$mod" # > /dev/null
	done	
	#cp "$staging_path/compiled_modules/"* "$staging_path/extra/usr/lib/modules/"
    printf -v EXTRA_MODULES "%s " "${extraModsSorted[@]}"
    printf -v DISK_MODULES "%s " "${diskModsSorted[@]}"
    echo "EXTRA_MODULES=\"$EXTRA_MODULES\"" > "$staging_path/extra/etc/rc.modules"
    echo "DISK_MODULES=\"$DISK_MODULES\"" >> "$staging_path/extra/etc/rc.modules"
    echo "EXTRA_FIRMWARES=\"$EXTRA_FIRMWARES\"" >> "$staging_path/extra/etc/rc.modules"
}
function proccessMod(){
	local mod="$1"
	local depends=$(modinfo "$staging_path/compiled_modules/$mod.ko" 2> /dev/null| grep "depends:")
	depends=$(echo "${depends##*depends:}" | xargs)
	local dList=(${depends//,/ })
	for dep in "${dList[@]}";do
		if [[ ! "${loadedMods[$dep]+_}"  ]];then proccessMod "$dep" "$2";fi
	done
	loadedMods["$mod"]=true
	if [[ $2 = true ]];then diskModsSorted+=("$mod")
	else extraModsSorted+=("$mod");fi
	cp "$staging_path/compiled_modules/$mod.ko" "$staging_path/extra/usr/lib/modules/" || true
	echo "$mod"
}
function stageBootloader(){
	cd "${staging_path}"
	mkdir -p bootloader
	cp -f "$synoboot_src.img" "$synoboot.img"
	mountSynoboot "$synoboot.img" "$synoboot"
}

function prepareEnviroment(){
    mkdir -p "$base_path"
    cd "$base_path"
}

function downloadSrcFiles(){
    echo "Downloading kernel and toolchain for device ${arch} and DSM version ${version}"
    hashkey="${arch}_${version}"
    mkdir -p "$src_path"
	patchName="${arch}-${version}-modified-jun.patch"
    wget "${kernel_links[$hashkey]}" -O "${kernel_src}"
    wget "${toolchain_links[$hashkey]}" -O "${toolchain_src}" 
	wget "https://raw.githubusercontent.com/jose-pr/xdsm-utils/master/$patchName" -O "$src_path/$patchName"
	wget "https://raw.githubusercontent.com/jose-pr/xdsm-utils/master/xdsm-utils.sh" -O "$src_path/xdsm-utils.sh"
	wget "https://raw.githubusercontent.com/jose-pr/xdsm-utils/master/install.sh" -O "$src_path/install.sh"
}
function prepareStagingArea(){
    rm -R "$staging_path" 2>/dev/null || true
    mkdir -p "$staging_path"
	unpackSrc "$toolchain_src" "$toolchain_path"
	unpackSrc "$kernel_src" "$kernel_path"
    cp "$kernel_path/synoconfigs/$arch" "$kernel_path/.config"
}
function addKVMModules(){
        cd "$kernel_path"
        for mod in "${kvmModules[@]}" 
        do
            addModuleToCompileList "$mod"
        done
        for mod in "${sriovModules[@]}" 
        do
            addModuleToCompileList "$mod"
        done
        $dsm_make olddefconfig
        compareMakeConfigs
}
function compileModules(){
    cd "$kernel_path"
    $dsm_make modules
    cd "${staging_path}"
    mkdir -p compiled_modules
	rm -rf compiled_modules/*
    find ./kernel/ -iname "*.ko" -type f -exec cp -p {} ./compiled_modules/ \;
}
function createHelperFunctions(){
    mkdir -p "$staging_path/extra/opt/xpenology-elves/bin"
    cp "$src_path/${arch}-${version}-modified-jun.patch" "$staging_path/extra/etc/jun.patch"
    cp "$src_path/xdsm-utils.sh" "$staging_path/extra/opt/xpenology-elves/bin/xdsm-utils"
    cp "$src_path/install.sh" "$staging_path/extra/opt/xpenology-elves/install.sh"    
}
function modifySynoboot(){	
	stageBootloader
	unpackExtraLZMA "$synoboot/extra.lzma" "$staging_path/extra" true
    proccessModules
    createHelperFunctions
	packExtraLZMA "$staging_path/extra" "$synoboot/extra.lzma"
    umount -f "$synoboot"
	mkdir -p "$build_path"
	rm -rf "$build_path/$build_prefix-synoboot.img" "$staging_path/$build_prefix-inserted_modules.txt" > /dev/null
	cp "$synoboot.img" "$build_path/$build_prefix-synoboot.img"
	cp "$staging_path/inserted_modules" "$build_path/$build_prefix-inserted_modules.txt"
	rm -f "$build_path/synoboot.img"2>/dev/null||true
	rm -f "$build_path/inserted_modules.txt" 2>/dev/null||true
	cp "$synoboot.img" "$build_path/synoboot.img"
	cp "$staging_path/inserted_modules" "$build_path/inserted_modules.txt"
}
function clean(){
    case "$1" in
        all)
            rm -R "$base_path/"*  
        ;;
        srcs)
            rm -R "$src_path"
        ;;
		staging)
			rm -R "$staging_path"
		;;
		builds)
			rm -R "$build_path"
		;;			
    esac    
}
function resetConfig(){
    cp "$kernel_path/synoconfigs/$arch" "$kernel_path/.config"
}

function compareMakeConfigs(){
	"$kernel_path/scripts/diffconfig" "$kernel_path/synoconfigs/$arch" "$kernel_path/.config"
}
function menuConfig(){
    cd "$kernel_path"
    $dsm_make menuconfig
    compareMakeConfigs
}

func="${args[0]}"
echo "path is :$base_path arch:$arch version:$version action:$func"
"$func" "${args[1]}" "${args[2]}"
echo "Finished"




