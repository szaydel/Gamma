#!/bin/bash
##: Title       : USPS Local Disk to SAN LUN Replication script for boot devices
##: Date Rel    : 10/01/2010
##: Date Upd    : 12/02/2010
##: Author      : "Sam Zaydel" <sam.zaydel@usps.gov>
##: Version     : 1.0.3
##: Release     : Beta
##: Description : 
##: Options     : 
##: Filename    : local-boot-to-san-boot-sync.sh
###############################################################################
### NOTES: ####################################################################
###############################################################################
## This script is not really designed to be very flexible as far as what is
## being replicated. The reason for this is that we use a mix of tools here
## some specific to LVM. This automation, in its current form will look for
## very specific items, and if they are not present, it will fail right away
###############################################################################
### Index/Description of Functions included in Library ########################
###############################################################################
##
###############################################################################
### Revisions: ################################################################
###############################################################################
## 11/08/2010 : Added return code to directory creation function
## 12/02/2010 : Added LV-offline, LV-online Function
## Modified flush_mpath() function commenting out LVM bits
## Due to change to /boot mount, made adjustments to compensate
##
##
###############################################################################
################# Major objectives and expected behavior ######################
###############################################################################
### IMPORTANT:
### 1. multipath should allow us to flush the LUN to which we are replicating
### if we cannot flush the LUN, this is likely due to LVM volumes in vg_rootsan
### being Active
### 2. we are very cautious, so most errors will result in early termination
### 3. WWID of Mirror device is derived through LVM, so we have to have another
### LVM 'VG' with an attached 'PV'
### 4. in step 1b, we check a bunch of things, and if anything is not as
### expected we bail
### 5. We make sure that /boot is not mounted when we 'dd' its contents to a 
### LUN on SAN
### 6. After using LVM Snapshot technology to replicate rootdisk components
### we fsck each device, to make sure that the filesystem is clean when the
### server boots up in DR
### 
###############################################################################
###############################################################################
### Step 1 - Variables and Preliminary Checks
###############################################################################
#
#
###############################################################################
### Step 1a - Definition of critical Variables
###############################################################################
# Define Source Boot Device and LVM Device 
# SRCBOOT=$(egrep "\/boot" /etc/fstab | cut -d " " -f1) # Extracting boot device from 'fstab'
SRCBOOT=/dev/disk/by-label/boot # This should be consistent across ALL servers
## This is our source, and it is invariable, but we could choose to 
## change this script to run it with options where inputs 
## are source 'VG' and destination 'VG'
SRCVOLGRP=vg_rootdisk
MIRVOLGRP=vg_rootsan
## Depending upon how a server was built, LVM may be filtering 'by-name' or 'by-id'
## We want to make sure that we account for both situations
MIRBOOTWWN=$(pvscan 2>/dev/null | grep "${MIRVOLGRP}"| sed -r -e "s/(\/dev\/disk\/by.(id|name))(\/scsi-|\/)//g" -e "s/^  PV //g" | cut -d "-" -f1)
## MIRBOOTDISK=/dev/disk/by-id/scsi-${MIRBOOTWWN}  ## Changed line to get away from /dev/disk/by-id on 09/28/2010
MIRBOOTDISK="/dev/mapper/${MIRBOOTWWN}"

## MIRBOOTDM="/dev/mapper/${MIRBOOTWWN}-part1"
MIRBOOTDM="${MIRBOOTDISK}-part1"
## Array containing logical volumes 'lvs' which we need to duplicate
MYLVS=( root var swap export )
## Timeout value used throughout the script
TIMEOUT=5
###############################################################################
### Step 1b - Verify that critical variables are correctly set
###############################################################################
    ## If the 'MIRVOLGRP' variable does not exist, we cannot continue
    if [[ $(vgscan 2>/dev/null | grep -q "${MIRVOLGRP}"; echo $?) -ne "0" ]]; then
        printf "%s\n" "CRITICAL: Unable to locate Volume Group ${MIRVOLGRP}. Cannot continue."
        exit 1
    ## We cannot continue if our 'MIRBOOTWWN' variable is not defined
    elif [[ -z "${MIRBOOTWWN}" ]]; then
        printf "%s\n" "CRITICAL: Unable to identify Device ID for our SAN Mirror. Cannot continue."
        exit 1
    ## We cannot continue if for some reason our LUN does not appear to be a block device
    elif [[ ! -b "${MIRBOOTDISK}" ]]; then
        printf "%s\n" "CRITICAL: SAN LUN does not appear to be a Block Device. Cannot continue."
        exit 1  
    ## Here we test to make sure that our device ID is exactly 33 characters long
    elif [[ ! "${#MIRBOOTWWN}" -eq "33" ]]; then
        printf "%s\n" "CRITICAL: Length of Device ID for our SAN Mirror is not correct. Cannot continue."
        exit 1
    ## Here we check if we can stat first partition on our SAN LUN
    elif [[ $(stat "${MIRBOOTDM}"; echo $?) -ne 0 ]]; then
        printf "%s\n" "CRITICAL: Unable to determine if SAN BOOT Device exists. Cannot continue."
        exit 1

    fi

###############################################################################
### Step 2 - Definition of Functions used later in the script
###############################################################################

start_stop_lvs ()
{
## Function is used to start and stop Logical Volumes
## passed to this function as an array
## Normally, the function should be unsed as follows:
## start_stop_lvs online "${ARRAYNAME[@]}" to start Volumes
## start_stop_lvs offline "${ARRAYNAME[@]}" to stop Volumes

local LV_NAME=""
local ACTION="$1"
shift 1
local LV_ARRAY=("$@")

    ## Define Action we are expecting to perform, should be
    ## online '-ay', or offline '-an'
    if [[ "${ACTION}" = "offline" ]]; then
        local ACTION=-an
        local LV_STATE="Offline"
    elif [[ "${ACTION}" = "online" ]]; then
        local ACTION=-ay
        local LV_STATE="Online"
    else
        printf "%s\n" "Unexpected parameter ${ACTION} was passed to this function. Cannot continue."
        return 1
    fi

    for LV_NAME in "${LV_ARRAY[@]}"
        do
            printf "%s\n" "[INFO] Changing state of ${MIRVOLGRP}/lv_${LV_NAME} to ${LV_STATE}" 
            lvchange "${ACTION}" "${MIRVOLGRP}/lv_${LV_NAME}" &> /dev/null

            sleep 2
            ## lvchange "${ACTION}" ${MIRVOLGRP}/lv_${LV_NAME} &> /dev/null
        done
## We need to make sure Device-Mapper and UDEV have a chance to settle down
printf "%s\n"
printf "%s\n" "###############################################################################"
printf "%s\n" "[INFO] Waiting for ${TIMEOUT} seconds for Device-Mapper and UDEV to settle."
printf "%s\n" "###############################################################################"
printf "%s\n"

sleep "${TIMEOUT}"

    for LV_NAME in "${LV_ARRAY[@]}"
        do
        local SYM_LINK_LV_MIR="/dev/${MIRVOLGRP}/lv_${LV_NAME}"
            ## Test if Symlink exists, assuming State required is Online
            if [[ "${LV_STATE}" = "Online" && -b "${SYM_LINK_LV_MIR}" ]]; then
                printf "%s\n" "[INFO] Logical Volume ${MIRVOLGRP}/lv_${LV_NAME} is now Online."
            elif
            ## Test if Symlink is gone, assuming State required is Offline
                [[ "${LV_STATE}" = "Offline" && ! -b "${SYM_LINK_LV_MIR}" ]]; then
                printf "%s\n" "[INFO] Logical Volume ${MIRVOLGRP}/lv_${LV_NAME} is now Offline."
            else
                printf "%s\n" "###############################################################################"
                printf "%s\n" "[WARNING] Logical Volume ${MIRVOLGRP}/lv_${LV_NAME} is not ${LV_STATE}."
                printf "%s\n" "###############################################################################"
                local RET_CODE=1
            fi
        done
return "${RET_CODE:-0}"
}

flush_mpath ()
{
## Multipath flush function is required to make sure that we will not have a 
## problem with LVM and device-mapper
## Several instances have been observed where 'dm' device under /dev/mapper
## for Part-1 or Part-2 is gone
## This script relies heavily on /dev/mapper for its block devices and will
## rapidly fail if there is a an issue with the device-mapper

## First, let's make sure that the mirror 'VG' is offline, otherwise multipath
## will complain and faile to flush the device
printf "%s\n"
printf "%s\n" "[INFO] Flushing multipath for ${MIRBOOTWWN}"

#local COUNT="3"
#while [[ $(ls "/dev/mapper/${MIRVOLGRP}-lv_*" 2>/dev/null) && "${COUNT}" -gt "0" ]]
#    do
#        vgchange -an "${MIRVOLGRP}"; RET_CODE=$?
#        sleep "${TIMEOUT}"
#        local COUNT=$((COUNT-1))
#    done

#    if [[ "${RET_CODE}" -ne "0" ]]; then
#        printf "%s\n" "###############################################################################"
#        printf "%s\n" "[WARNING] Unable to offline All Volumes in ${MIRVOLGRP}"
#        printf "%s\n" "###############################################################################"
#        RET_CODE="1"
#        return "${RET_CODE}"
#    fi

local COUNT="3"
while [[ $(multipath -l "${MIRBOOTWWN}" 2>/dev/null) && "${COUNT}" -gt "0" ]]
    do
        multipath -f "${MIRBOOTWWN}"
        sleep "${TIMEOUT}"
        local COUNT=$((COUNT-1))
    done
    
    if [[ $(multipath -l "${MIRBOOTWWN}" 2>/dev/null) ]]; then
            printf "%s\n" "###############################################################################"
            printf "%s\n" "[WARNING] Unable to flush multipath for ${MIRBOOTWWN}"
            printf "%s\n" "###############################################################################"
            RET_CODE="1"
        else
            printf "%s\n"
            printf "%s\n" "[INFO] Flushed multipath for ${MIRBOOTWWN}"
            printf "%s\n"
            printf "%s\n" "[INFO] Re-scanning multipath Devices."
            multipath -v2
            sleep "${TIMEOUT}"
            RET_CODE="0"
    fi     
return "${RET_CODE}"
}

cleanup-snap()
{
## Clean-up function used to remove snaps after a copy has been made, or
## if something has not gone as expected in the process,
## because we do not want to keep snapshots
## Function can accept one argument $1, which should be one of
## values from the MYLVS array

## Return Code 4 - Snapshot volume was never created
## Return Code 5 - Snapshot and Mirror volumes unmounted and snapshot not removed
## Return Code 6 - Snapshot and Mirror volumes unmounted and snapshot removed
local LV_NAME=$1
local SYM_LINK_LVSNAP="/dev/${SRCVOLGRP}/lv_snap_${LV_NAME}"

## We check for existence of a symlink for the snapshot volume
## under /dev/vg_rootdisk/
    if [ ! -h "${SYM_LINK_LVSNAP}" ]; then
        printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Does Not Exist." 
        return 4
    fi
 
## Remove the snapshot volume that was created
printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} is being removed, please wait..."
COUNT=3  ## We will try to remove the snaptshot LV a total of 3 times 
while [ -h "${SYM_LINK_LVSNAP}" -a "${COUNT}" -gt 0 ]
    do
        ## Because we do not want to keep snapshots for any period of time,
        ## we are going to attempt to remove each snapshot after replication
        ## of a given 'LV' is done
        ## We will also clean-up snapshots in the case something has gone wrong
        lvremove -f "${SYM_LINK_LVSNAP}" &> /dev/null
        sleep ${TIMEOUT}
        COUNT=$((${COUNT}-1))
    done

[ -h "${SYM_LINK_LVSNAP}" ]; RET_CODE=$?  ## If '0' is returned the snapshot is still there
    if [[ "${RET_CODE}" -eq "0" ]]; then
        printf "%s\n" "###############################################################################"
        printf "%s\n" "TEMP Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Still Exists, Please Check."
        printf "%s\n" "###############################################################################"
        RET_CODE=5
    else
        printf "%s\n" "###############################################################################"
        printf "%s\n" "TEMP Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Removed Successfully."
        printf "%s\n" "###############################################################################"
        RET_CODE=6
    fi
return "${RET_CODE}"    
}

make_required_dirs ()
{

## This function is part legacy, but it is still required
## to verify/create a necessary structure under /mnt
## which is where we temporarily mount 'boot' and 'root'
## to allow for localized adjustments of files, after the
## sync process is done
local MIRBOOT_BASE=/mnt/mir3
[ ! -d "${MIRBOOT_BASE}" ] && /bin/mkdir "${MIRBOOT_BASE}"

for DIR in boot root var
    do
        if [[ -d "${MIRBOOT_BASE}/${DIR}" ]]; then
                printf "%s\n" "[INFO] Directory ${MIRBOOT_BASE}/${DIR} exists."
            else
                /bin/mkdir "${MIRBOOT_BASE}/${DIR}"
                RET_CODE=$?
            fi
    done
return "${RETCODE:-0}"
}

modify_grub ()
{

## Grub needs to be modified to boot from /dev/vg_rootsan/lv_root
## Function assumes that there is already another version of menu.lst
## available on /boot/grub
## We basically have stage menu.lst.DR on our /boot, and we are simply
## flipping real file to .prod and the .DR to menu.lst

local MIRBOOTMP=/mnt/mir3/boot
local GRUBDIR=/mnt/mir3/boot/grub
local GRUB_MENU=${GRUBDIR}/menu.lst

mount ${MIRBOOTDM} ${MIRBOOTMP}; RETCODE=$?

    if [ -d /mnt/mir3/boot/grub ]; then
    
        chattr -i ${GRUB_MENU}.DR ${GRUB_MENU} ## We need to make sure that we can rename/move menu.lst and menu.lst.DR
        mv ${GRUB_MENU} ${GRUB_MENU}.prod
        mv ${GRUB_MENU}.DR ${GRUB_MENU}
        chattr +i ${GRUB_MENU}
        
        umount "${MIRBOOTMP}"
        printf "%s\n" "Adjusted GRUB boot loader configuration to boot from SAN."
    else
        printf "%s\n" "${MIRBOOTDM} cannot be mounted. Please check filesystem. fsck ${MIRBOOTDM}"
        return 1
    fi
}

unmount_boot ()
{
## Unmount /boot prior to using dd to copy block-level from /dev/cciss/c0d0p1 to /dev/dm-XXX
printf "%s\n" "Unmounting /boot prior to running dd, please wait..."
COUNT=3  ## In case /boot is busy, we will try 3 times with a 15 second wait per attempt

    while [ -d /boot/grub -a "${COUNT}" -gt "0" ] ## We are assuming that /boot is mounted if /boot/grub exists
        do
            umount /boot &> /dev/null
            sleep ${TIMEOUT}
            COUNT=$((${COUNT}-1))
        done

## Test to make sure /boot has been unmounted successfully
## mount|egrep "\/boot" > /dev/null 2>&1; MOUNT_RC=$?

    if [[ $(mount|egrep -q "\/boot"; echo $?) -eq "0" ]]; then
            printf "%s\n" "Directory /boot is still mounted. Aborting..."; RET_CODE=1 
        else
            printf "%s\n" "Directory /boot has been unmounted Successfully."; RET_CODE=0
    fi

return "${RET_CODE}"
}

sync_boot ()
## Function is used to duplicate /boot, which should be
## unmounted prior to this function running
{
if [[ -b "${SRCBOOT}" && -b "${MIRBOOTDM}" ]]; then
        local DD_CMD=/bin/dd
        printf "%s\n" "###############################################################################"
        printf "%s\n" "[INFO] Performing copy using ${DD_CMD} of /boot..."
        printf "%s\n" "###############################################################################"
        unmount_boot || return 1        
        "${DD_CMD}" if="${SRCBOOT}" of="${MIRBOOTDM}" bs=1M
        RET_CODE=$?
    else
        printf "%s\n" "###############################################################################"
        printf "%s\n" "[WARNING] It appears that ${MIRBOOTDM} is invalid." 
        printf "%s\n" "[WARNING] Please check your SAN_BOOT device."
        printf "%s\n" "###############################################################################"
        exit 1
        RET_CODE=1
fi

if [ "${RET_CODE}" -eq "0" ]; then
        ## We are labeling our /boot filesystem [partition 1] with "SAN_BOOT"
        ## just for ease of identification in the future
        local LABEL_CMD=/sbin/tune2fs
        "${LABEL_CMD}" -L "SAN_BOOT" "${MIRBOOTDM}" &> /dev/null
        remount_boot || printf "%s\n" "Failed to re-mount directory /boot, Please check manually."
        printf "%s\n" "###############################################################################"
        printf "%s\n" "Duplicated local ${SRCBOOT} to SAN ${MIRBOOTDM} Successfully."
        printf "%s\n" "###############################################################################"
     else
        remount_boot || printf "%s\n" "Failed to re-mount directory /boot, Please check manually."
        printf "%s\n" "###############################################################################"
        printf "%s\n" "Duplication from local ${SRCBOOT} to SAN ${MIRBOOTDM} Failed. Exiting..."
        printf "%s\n" "###############################################################################"
fi

return "${RET_CODE}"
}

remount_boot ()
{
## After performing a dd copy, we need to remount /boot
printf "%s\n" "Re-mounting /boot after completion of dd, please wait..."
COUNT=3  ## In case /boot is busy, we will try 3 times with a $TIMEOUT value wait per attempt

    while [[ ! -d /boot/grub && "${COUNT}" > "0" ]]
        do
            mount /boot > /dev/null 2>&1
            sleep ${TIMEOUT}
            COUNT=$((${COUNT}-1))
        done

## Test to make sure /boot has been mounted successfully
mount|egrep "\/boot" &> /dev/null; MOUNT_RC=$?
[[ "${MOUNT_RC}" = "0" ]] && RET_CODE=0 || RET_CODE=1
return "${RET_CODE}"
}

sync_lvs ()
{
# This is where we create a temporary snapshot volume and perform a 'dd'
# operation. Upon completion of 'dd' we remove the snapshot.
# If we cannot create a snapshot our return code "LVCREATE_RC" will not equal '0'.
# If the return code is not '0' we run the "cleanup-snap" function and exit
# with return code supplied by the "cleanup-snap" function.
# Variable LV_NAME is iterated based on array defined at the top of the script.

local LV_NAME=$1
local TMP_LV_NAME="lv_snap_${LV_NAME}"
local DD_SOURCE="/dev/mapper/${SRCVOLGRP}-${TMP_LV_NAME}"
local DD_MIRROR="/dev/mapper/${MIRVOLGRP}-lv_${LV_NAME}"
        ## This is where we actually create our temporary 'snapshot' 'LVs'
        lvcreate -L4G -s -n "${TMP_LV_NAME}" ${SRCVOLGRP}/lv_${LV_NAME} &>/dev/null; RET_CODE=$?
        if [[ "${RET_CODE}" -eq "0" ]]; then
                printf "%s\n" "###############################################################################"
                printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/${TMP_LV_NAME} Created Successfully."
                printf "%s\n" "###############################################################################"  
            else
                printf "%s\n" "###############################################################################"
                printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/${TMP_LV_NAME} Not Created. Cleaning-up and Exiting."
                printf "%s\n" "###############################################################################"
                return 1
        fi

    printf "%s\n" ""
    printf "%s\n" "###############################################################################"
    printf "%s\n" "[INFO] Running BLOCK-LEVEL Copy" "FROM: ${SRCVOLGRP}/${TMP_LV_NAME}" "TO: ${MIRVOLGRP}/lv_${LV_NAME}"
    printf "%s\n" "###############################################################################"
    printf "%s\n" ""
        ## We need to make sure that our source and destination are both block-special devices
        ## If for some reason this is not the case, we have to stop right away, before causing
        ## any potential harm to the system
        if [[ -b "${DD_MIRROR}" && -b "${DD_SOURCE}" ]]; then
                /bin/dd if="${DD_SOURCE}" of="${DD_MIRROR}" bs=1M
                printf "%s\n" "[INFO] Checking Filesystem Consistency on ${DD_MIRROR}."
                /sbin/fsck -p "${DD_MIRROR}"
                # sleep "${TIMEOUT}"
                return 0
            else
                printf "%s\n" "[WARNING] Source or Destination may not be a Block Special Device."
                ## 09-28-2010 Moved cleanup-snap line outside of this function for better flow
                ## cleanup-snap "${LV_NAME}"; RC_CLEAN=$?; exit "${RC_CLEAN}"
                return 1
        fi
}

offline_lvs ()
{
local LV_NAME=$1
lvchange -an ${MIRVOLGRP}/lv_${LV_NAME} &> /dev/null && printf "%s\n" "Volume ${MIRVOLGRP}/lv_${LV_NAME} is now Inactive..."
}

###############################################################################
### Step 3 - Begin execution of main part of the script
###############################################################################

clear
## If all tests at the beginning of the script succeed, 
## we can safely state the following successes
printf "%s\n" "###############################################################################"
printf "%s\n" "[INFO] Success: Located Mirror Volume Group ${MIRVOLGRP}"
printf "%s\n" "[INFO] Success: Confirmed Existance of LUN ${MIRBOOTWWN}"
printf "%s\n" "[INFO] Success: Confirmed Existance of Mirror Boot Device"
printf "%s\n" "###############################################################################"
printf "%s\n" ""
printf "%s\n %s\n""[INFO] SRC BOOT: ${SRCBOOT} DEST BOOT: ${MIRBOOTDM}" \
"[INFO] SRC ROOT (LVM): ${SRCVOLGRP} DEST ROOT (LVM): ${MIRVOLGRP}"
printf "%s\n" ""
printf "%s\n" ""
printf "%s" "Are we ready to continue? [Y/N]: "
read USER_INPUT

case "${USER_INPUT}" in

    [Yy])
        printf "%s\n\n" "Continuing..."
        sleep ${TIMEOUT}
        ;;

    [Nn])
        exit 1
        ;;

    *)
        printf "%s\n" "Input not understood. Bailing."
        exit 1
        ;;
    
esac

start_stop_lvs offline "${MYLVS[@]}" || exit 1

flush_mpath || exit 1

start_stop_lvs online "${MYLVS[@]}" || exit 1
## Make sure necessary directory structure is in place under /mnt

make_required_dirs || exit 1

###############################################################################
### Step 4 - Check for, and create LVs and filesystems as necessary 
###############################################################################

## Check for existance of Mirror PV Device
printf "%s\n" "...Checking for existance of PV Devices on Mirrored Storage..."

if [ -b "${MIRBOOTDISK}p2" ]; then
    pvdisplay -s "${MIRBOOTDISK}p2"; RET_CODE=$? # Check for Partition 2 labeled <diskid>p2 and return status
    [ "${RET_CODE}" -eq 0 ] && printf "%s\n" "PV Device ${MIRBOOTDISK}p2 was found"
elif [ -b "${MIRBOOTDISK}-part2" ]; then
    pvdisplay -s "${MIRBOOTDISK}-part2"; RET_CODE=$? # Check for Partition 2 labeled <diskid>-part2 and return status
    [ "${RET_CODE}" -eq 0 ] && printf "%s\n" "PV Device ${MIRBOOTDISK}-part2 was found"
else
    printf "%s\n" "###############################################################################"
    printf "%s\n" "[CRITICAL] Could not identify PV Device on ${MIRBOOTWWN}"
    printf "%s\n" "###############################################################################"
    exit 1
fi

    (vgchange -ay ${MIRVOLGRP} \
    && printf "%s\n" "Changed status of ${MIRVOLGRP} to Active...") || exit 1
       
    for LV_NAME in "${MYLVS[@]: 0:3}" # These two are 4GB LVs and filesystems
        do
        [ ! -h "/dev/${MIRVOLGRP}/lv_${LV_NAME}" ] && lvcreate --name "lv_${LV_NAME}" -L4G "${MIRVOLGRP}"
        done
          
    for LV_NAME in "${MYLVS[@]: 2:4}" # These two are 1GB LVs and filesystems
        do
        [ ! -h "/dev/${MIRVOLGRP}/lv_${LV_NAME}" ] && lvcreate --name "lv_${LV_NAME}" -L1G "${MIRVOLGRP}"
        done

### Step 5 - Replicate data between SAN and Local Disk
## Replicate /boot

sync_boot || exit 1


## Replicate Logical Volumes

for LV_NAME in "${MYLVS[@]: 0:3}" 
    do
        sync_lvs "${LV_NAME}"; RET_CODE=$?

        if [[ "${RET_CODE}" -ne "0" ]]; then
                cleanup-snap "${LV_NAME}"
                exit 1
            else
                cleanup-snap "${LV_NAME}"
        fi
   done

### Step 6 - This is where we make changes to various configuration files on our SAN disk
modify_grub

### Step 7 - Need to offline LVM SAN Logical Volumes and Volume Group
## Function start_stop_lvs is defined above and takes two arguments.
## First argument is action 'online', or 'offline' 
## Second argument is the Array of LVs

start_stop_lvs offline "${MYLVS[@]}" || exit 1

