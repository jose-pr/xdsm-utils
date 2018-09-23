#!/bin/bash
set -e

declare -A grubVars
declare -A tmpMnts
declare -A realMACs
grubenv="/boot/grub/grubenv"
BOOT_LABEL=''
BOOT_PID=''
BOOT_VID=''

currentArg=""
argIndex=0

function getSystemInfo(){
    source /etc/synoinfo.conf 2>/dev/null || true
    source /etc/VERSION || true
    DeviceModel="${upnpmodelname,,}"
    echo "DeviceModel=\"$DeviceModel\""
    DSMVersion="$productversion"
    echo "DSMVersion=\"$DSMVersion\""
    KernelVersion="$(uname -r)"
    echo "KernelVersion=\"$KernelVersion\""  
	
}

function getArg(){ 
    currentArg="${args[$argIndex]}"
    argIndex=$argIndex+1
}

function getRealMACs(){
    eth_if=0
    until [ $eth_if -eq 4 ];do
        eif="eth$eth_if"
        r=$(ethtool -P "$eif" 2>/dev/null || true)
        let eth_if+=1
        if [[ "$r" == "Permanent"* ]];then 
            mac="$(echo "$r" | awk '{print $3}')";
            mac="${mac//:}"
			realMACs["mac$eth_if"]="${mac//:}"
			echo "mac$eth_if=$mac"
        fi        
    done
}
function random(){
    echo "$(shuf -i "$1-$2" -n 1)"
}
function indexOf(){
    x="${1%%$2*}"
    [[ "$x" = "$1" ]] && echo -1 || echo "${#x}"
}
function getGrubVars(){
    if [ ! ${tmpMounts["synoboot1"]+_} ]; then
        tmpMnt="/mnt/$(uuidgen)"
        mountGrub "$tmpMnt"
        tmpMnts["synoboot1"]="$tmpMnt"
        grubenv="$tmpMnt/grub/grubenv"
    fi
    while IFS='' read -r var || [[ -n "$var" ]]; do
        i=$(indexOf "$var" "=")
        if [[ "$var" != "#"* ]];then grubVars["${var:0:$i}"]="${var:$i+1:1024}";fi       
    done  < "$grubenv"
    for k in "${!grubVars[@]}";do echo "key: $k | val:${grubVars[$k]}";done
}
function setGrubVars(){
    if [[ "$1" = true  ]];then getGrubVars > /dev/null;fi
    line="# GRUB Environment Block"
    echo "$line" > "$grubenv"
    size=$((${#line}+1))
    for k in "${!grubVars[@]}";do
        line="$k=${grubVars[$k]}"
        size=$((${#line}+1+$size))
        echo "$line" >> "$grubenv"
    done
    missing=$((1024-$size))
    if [ $missing -le 0 ];then return 1;fi
    printf '#%.0s' $(seq 1 $missing)  >> "$grubenv"    
}
function setGrubVar(){
    getGrubVars > /dev/null
    if [[ ! -z "$1"  ]];then grubVars["$1"]="$2";fi
    line="# GRUB Environment Block"
    echo "$line" > "$grubenv"
    size=$((${#line}+1))
    for k in "${!grubVars[@]}";do
        line="$k=${grubVars[$k]}"
        size=$((${#line}+1+$size))
        echo "$line" >> "$grubenv"
    done
    missing=$((1024-$size))
    if [ $missing -le 0 ];then return 1;fi
    printf '#%.0s' $(seq 1 $missing)  >> "$grubenv"    
}
function unSetGrubVar(){
    getGrubVars >> /dev/null
    line="# GRUB Environment Block"
    echo "$line" > "$grubenv"
    size=$((${#line}+1))
    for k in "${!grubVars[@]}";do
        if [[ "$1" == "$k" ]];then continue;fi
        line="$k=${grubVars[$k]}"
        size=$((${#line}+1+$size))
        echo "$line" >> "$grubenv"
    done
    missing=$((1024-$size))
    if [ $missing -le 0 ];then return 1;fi
    printf '#%.0s' $(seq 1 $missing)  >> "$grubenv"    
}
function generateSerial(){
    device="${1:-$DeviceModel}"
    declare -A deviceCode=(['ds3615xs']='LW' ['ds3617xs']='OD' ['ds916+']='NZ')
    echo "$(random 11 14)30${deviceCode[$device]}N0$(random 0 2)$(printf %04d $(random 1 9999))"
}
function setSerialEnv(){
    serial="$(generateSerial)"
    setGrubVar sn "$serial"    
}
function setMACsEnv(){
    getRealMACs
    for k in "${!realMACs[@]}";do
        setGrubVar "$k" "${realMACs[$k]}" 
    done   
}
function setEthIfQty(){
    r=4
	qty=${1:-4}
	getGrubVars
    while [ $r -gt 0 ];do
		key="mac$r"
		if [ $r -gt $qty ];then unSetGrubVar "$key" 
		else 
			if [[ ! "${grubVars[$key]+_}"  ]];then grubVars["$key"]="02000000000$r";fi
		fi
        r=$(($r-1))
    done
	setGrubVars false
}
function mountSynoboot(){
    point=synoboot$1
    mnt="${2:-/mnt/$point}"
    reassign=${2:-false}
    current="$(mount | grep \"$pint\" | cut -d ' ' -f 3)"
    if [[ ! -z "$current" ]];then 
        mount --bind "$current" "$mnt" > /dev/null        
    else
        p="$PWD"
        cd /dev
        mkdir -p "$mnt"
        mount "$point" "$mnt" > /dev/null
        cd "$p"
    fi
    echo "Mounted $point at $mnt"
}

function mountGrub(){
    mountSynoboot 1 ${1:-/boot}
}

function mountXpenoboot(){
    mountSynoboot 2 ${1:-/mnt/xpenoboot}
}
#Code taken from jun.patch
function getBootDeviceLabel(){
	while read -r line
	do
		read major minor sz name <<< "$line"
		if echo $name | grep -q "^sd[[:alpha:]]*$";then
			basename=$name
			synoboot1=""
			synoboot2=""
			continue
		fi
		if [ $name = "${basename}1" -a $sz -le 512000 ]; then
			synoboot1="$name"
		elif [ $name = "${basename}2" -a $sz -le 512000 ]; then
			synoboot2="$name"
		else
			continue
		fi
		if [ -n "$synoboot1" -a -n "$synoboot2" ]; then
			BOOT_LABEL=$basename
			echo "$basename"
		fi		
	done < <(tail -n+3 /proc/partitions)
	if [[ $BOOT_LABEL = "" ]];then 
		echo "Could't find synoboot device"
		exit 1
	fi
}
function getBootDevInfo(){
	getBootDeviceLabel
	
	path=$(ls -lR /sys/devices | egrep ^/.*/$BOOT_LABEL:$)
	path="${path%*host*}"
	BOOT_PID=$(cat $path/../idProduct)
	BOOT_VID=$(cat $path/../idVendor)
	echo "BOOT_PID=$BOOT_PID"
	echo "BOOT_VID=$BOOT_VID"
}
function setBootEnvs(){
	getBootDevInfo
	setGrubVar vid "0x$BOOT_VID"
	setGrubVar pid "0x$BOOT_PID"
}

func=$1
shift
getSystemInfo > /dev/null
$func "$@"
for k in "${tmpMnts[@]}";do
    umount -f "$k" || true
    rm -R "$k" || true
done
echo "$func is Done"
exit 0

