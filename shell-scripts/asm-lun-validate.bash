asm-disk-chk ()
{
## Function is used to check a disk using its device ID against 
## a number of subsystems on the server to determine logical device paths
## label on the disk/partition, if any, and ASM storage management 
## to determine whether this disk is configured under ASM

if [ $UID -ne "0" ]; then
   printf "%s\n" "You are not currently root. Run this function as root."
   return 1
fi

# local DIV=$(printf "%80s\n"|tr ' ' - )
local GREP_OPTIONS="-r -E --color=never"
local DIV=$(printf "%80s\n"|tr ' ' - )
local TMP_FILE=/tmp/LUN-detail-${HOST}.info
local BYID_PATH=/dev/disk/by-id
local BYNM_PATH=/dev/disk/by-name
local DM_PATH=/dev/mapper
local SYS_BUS_DEV=/sys/class/scsi_disk
local LSSCSI_CMD="/usr/bin/lsscsi -vlk"
local MPATH_CMD="/sbin/multipath -l"
local SYST_CMD="/usr/bin/systool -p -c scsi_disk"
local FDISK_CMD="/sbin/sfdisk -d"
## We make sure that we have 'MPATH_ARRAY' defined, 
## to avoid "Undefined Variable" error
local MPATH_ARRAY=""
[ -f ] && rm -f 

> ${TMP_FILE}

insert_break ()
{
printf "%s\n" ${DIV} 
}

while [ -z "${MYDISK}" ]
    do 
    clear
    printf "%s\n" "###############################################################################"
    printf "%s\n" "######################## Please, enter LUN Device ID ##########################"
    printf "%s\n" "###############################################################################"
    printf "%s\n\n" "Hint: 'multipath -l' or 'dmsetup ls' will return all LUNs visible to the system."
    printf "%s" "LUN ID (33-char): "   
    [[ ! -z "$1" ]] && local ID="$1" || read ID
        
        if [[ $(echo "${ID}" | egrep -e ^3600) && $(echo "${ID}" | wc -m) -eq "34" ]];
            then
                printf "%s\n" "Length of device ID acceptable, and disk name begins with 3600 as expected...continuing..."
                local MYDISK="${ID}"
             else
                clear
                insert_break
                printf "%s\n" "Length of device ID not acceptable or device ID does not begin with [3600]"
                insert_break
                shift 1
                local MYDISK=""
        fi
    done
                
## We first generate a hwinfo output file, which we will query for additional disk information
## We also generate a lssci output file, which we will also query for block device information and SysFS path information
printf "%s\n\n\n"
printf "%-25s %s\n" "### PLEASE WAIT ###" "Generating list of devices visible to $(hostname)..."
## Capture output of 'multipath -l device_id' into a file
${MPATH_CMD} "${MYDISK}" >> "${TMP_FILE}"

## Below we create an array using multipath, which should contain all four paths to LUN
## information is in H:C:T:L format = 2:0:3:76 2:0:2:76 0:0:5:76 0:0:4:76
## We will use results of this array to gather all the necessary additional info about
## the state of the LUN, system paths, etc.
local MPATH_ARRAY=( $(awk '/sd[a-z]/ {print $2}' "${TMP_FILE}") )
## local MPATH_ARRAY=( $(multipath -l ${MYDISK} | awk '/sd[a-z]/ {print $2}') )
# printf "%s\n" "${MULTIPATH_ARRAY[@]}" ## Uncomment if troubleshooting

## We derive the block devices through the 'lsscsi' command, using 'MPATH_ARRAY' array
## as the input, as such our 'MPATH_ARRAY' has to be defined already
## We should have four block devices in this array: /dev/sdXX /dev/sdYY /dev/sdZZ
local BLOCK_DEVICE_ID_ARRAY=( $(awk '/sd[a-z]/ {print $3}' "${TMP_FILE}") )

## We need to store part of the Disk Label in a Variable, and will use blkid to check for it                
local DISK_LABEL=$(echo ${MYDISK} | cut -b 17- | tr '[:lower:]' '[:upper:]')
               

insert_break
printf "%s\n" "LUN "${MYDISK}" has "${#MPATH_ARRAY[@]}" subpaths:"
insert_break

insert_break
printf "%s\n" "According to SysFS the following is known about this LUN:"
insert_break

for EACH_PATH in "${!MPATH_ARRAY[@]}"
    do 
## We create a detailed Array here, and format output to produce four lines with information
    local DETAIL_ARRAY=( $(${LSSCSI_CMD} "${MPATH_ARRAY[${EACH_PATH}]}" | sed -e :a -e '$!N; s/\n/ /; ta' -e "s/  */ /g"))
    local FSYSB_PATH=$(${SYST_CMD} "${MPATH_ARRAY[${EACH_PATH}]}" | sed -e "s/  */ /g" -e "s/[\"\=]//g" | awk '$1 ~ /Device/ && $2 ~ /path/ {print $3}')
    printf "%s\n" "${DETAIL_ARRAY[0]} : LUN Details: ${DETAIL_ARRAY[2]} ${DETAIL_ARRAY[3]} ${DETAIL_ARRAY[4]}"
    printf "%s\n" "${DETAIL_ARRAY[0]} : Associated Block Device: /dev/"${BLOCK_DEVICE_ID_ARRAY[${EACH_PATH}]}" "
    printf "%s\n" "${DETAIL_ARRAY[0]} : Full System BUS Path: "${FSYSB_PATH}" "
    printf "%s\n" "${DETAIL_ARRAY[0]} : Short System BUS Path: /sys/bus/scsi/devices/"${MPATH_ARRAY[${EACH_PATH}]}" "
    insert_break
    done
    
insert_break
    printf "%s\n" "Device has the following \"Friendly-name\" Paths:"
insert_break

## Does /dev/mapper/device_id exist?
    if [[ -b "${DM_PATH}/${MYDISK}" ]]; then
        printf "%s\n" "DM Block Device Exists: ${DM_PATH}/${MYDISK}" 
        else
        printf "%s\n" "Unable to locate : ${DM_PATH}/${MYDISK}" 
    fi
    ## Does /dev/disk/by-name/device_id exist?
    if [[ -h "${BYNM_PATH}/${MYDISK}" ]]; then
        printf "%s\n" "Symlink Exists : ${BYNM_PATH}/${MYDISK}"
        else
        printf "%s\n" "Unable to locate : ${BYNM_PATH}/${MYDISK}"
    fi
    ## Does /dev/disk/by-id/scsi-device_id exist?
    if [[ -h "${BYID_PATH}/scsi-${MYDISK}" ]]; then
        printf "%s\n" "Symlink Exists : ${BYID_PATH}/scsi-${MYDISK}"  
        else
        printf "%s\n" "Unable to locate : ${BYID_PATH}/scsi-${MYDISK}" 
    fi

## We use blkid to look for the part of the disk label, which we stored in the DISK_LABEL variable
insert_break
    printf "%s\n" "Disk with partial label ${DISK_LABEL} Information:"
insert_break

## sfdisk output gives information about the partition table on the given disk
    ${FDISK_CMD} "${DM_PATH}/${MYDISK}" 2> /dev/null | egrep --regex "^\/dev"
    local RET_CODE=$?
insert_break

    if [ "${RET_CODE}" -eq "0" ]; then
            insert_break
            printf "%s\n" "According to Oracle ASM:" 
            insert_break
            oracleasm querydisk "${DM_PATH}/${MYDISK}-part1"                      
            insert_break

        else
            insert_break
            printf "%s\n" "Partition table may be invalid, or does not exist."
            printf "%sLUN ${MYDISK} appears to be un-labeled.\nExpecting ASM Disk Label...\n\n" 
            printf "%s\n" "According to Oracle ASM:" 
            [[ $(oracleasm querydisk "${DM_PATH}/${MYDISK}-part1" &> /dev/null) ]] || (printf "%s\n" "Disk is not configured as part of Oracle ASM." ) 
            insert_break
    fi

## Remove our temporary file here
rm -f "${TMP_FILE}"

## Return either 0, or 'RET_CODE'
return "${RET_CODE:-0}"
}
