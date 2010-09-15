#!/bin/bash

### Step 1 - Variables and Preliminary Checks

### Step 1a - Variables and Functions
# Define Source Boot Device and LVM Device 
SRCBOOT=$(egrep "\/boot" /etc/fstab | cut -d " " -f1) # Extracting boot device from 'fstab'
SRCVOLGRP=vg_rootdisk

## Define Target Boot Device and LVM Device

## We do not want to rely on 'inq' utility to obtain DISKID
# MIRBOOTWWN=$(/sa/teams/storage/inq/inq.linux -sym_wwn -nodots | grep "${MIRBOOTDM} " |awk {'print 3$4'})
MIRBOOTWWN=$(pvscan 2>/dev/null | grep 'vg_rootsan' | awk '{print $2}' | sed -e "s/[\/\-]/ /g" | awk '{print $6}')
MIRBOOTDISK=/dev/disk/by-id/scsi-${MIRBOOTWWN}  ## Changed line to use /dev/disk/by-id on 06/16/2010

## Because label may be missing, we do not want to rely on it
# MIRBOOTDM=$(blkid -t LABEL="SAN_BOOT" | egrep "\/dm" | awk {'print $1'} | sed 's/://g')
MIRBOOTDM=$(ls -l /dev/mapper/${MIRBOOTWWN}-part1 | awk '{print "/dev/dm-"$6}')
MIRVOLGRP=vg_rootsan
MYLVS=( root var export swap )

TIMEOUT=5

### Begin Changes made on 05/21/2010
## Clean-up function for when things do not go right
## Function can accept one argument $1, which should be one of
## values from the MYLVS array
cleanup-snap()
{
## Return Code 4 - Snapshot volume was never created
## Return Code 5 - Snapshot and Mirror volumes unmounted and snapshot not removed
## Return Code 6 - Snapshot and Mirror volumes unmounted and snapshot removed
local LV_NAME=$1
local SYM_LINK_LVSNAP=/dev/${SRCVOLGRP}/lv_snap_${LV_NAME}

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
        lvremove -f "${SYM_LINK_LVSNAP}" &> /dev/null
        sleep ${TIMEOUT}
        COUNT=$((${COUNT}-1))
    done

[ -h ${SYM_LINK_LVSNAP} ]; LVREMOVE_RC=$?  ## If '0' is returned the snapshot is still there
    if [ ! "${LVREMOVE_RC}" = "0" ]; then
        printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Still Exists, Please Check."
        return 5
    else
        printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Removed Successfully."
        return 6
    fi
}
### End Changes made on 06/11/2010

# Grub needs to be modified to boot from /dev/vg_rootsan/lv_root
modify_grub ()
{
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

clear
printf "%s\n" "Unmounting /boot prior to running dd, please wait..."
COUNT=3  ## In case /boot is busy, we will try 3 times with a 15 second wait per attempt

    while [ -d /boot/grub -a ${COUNT} -gt 0 ] ## We are assuming that /boot is mounted if /boot/grub exists
        do
            umount /boot &> /dev/null
            sleep ${TIMEOUT}
            COUNT=$((${COUNT}-1))
        done

## Test to make sure /boot has been unmounted successfully
mount|egrep "\/boot" > /dev/null 2>&1; MOUNT_RC=$?

    if [ ! ${MOUNT_RC} = "0" ]; then
        printf "%s\n" "Directory /boot is still mounted. Aborting..."; RET_CODE=1 
    else
        printf "%s\n" "Directory /boot has been unmounted Successfully."; RET_CODE=0
    fi

return "${RET_CODE}"
}

remount_boot ()
{
## After performing a dd copy, we need to remount /boot
clear
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
        lvcreate -L2G -s -n lv_snap_${LV_NAME} ${SRCVOLGRP}/lv_${LV_NAME}; LVCREATE_RC=$?
        if [ "${LVCREATE_RC}" = "0" ]; then
            printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Created Successfully."            
        else
            printf "%s\n" "Snapshot Volume ${SRCVOLGRP}/lv_snap_${LV_NAME} Not Created. Cleaning-up and Exiting."
            cleanup-snap ${LV_NAME}; RC_CLEAN=$?; exit ${RC_CLEAN}
        fi       
clear
printf "%s\n" "Performing -dd- copy of ${LV_NAME} from ${SRCVOLGRP}/lv_snap_${LV_NAME} to ${MIRVOLGRP}/lv_${LV_NAME}"
# ls -l /dev/mapper/${SRCVOLGRP}-lv_snap_${DIR} /dev/mapper/${MIRVOLGRP}-lv_${DIR}
    
        if [ -b "/dev/mapper/${MIRVOLGRP}-lv_${LV_NAME}" ]; then
            dd if=/dev/mapper/${SRCVOLGRP}-lv_snap_${LV_NAME} of=/dev/mapper/${MIRVOLGRP}-lv_${LV_NAME} bs=4k 
        else
            printf "%s\n" "WARNING: /dev/mapper/${MIRVOLGRP}-lv_${DIR} may not be a Block Special Device."
            cleanup-snap; RC_CLEAN=$?; exit ${RC_CLEAN}
        fi
}

offline_lvs ()
{
local LV_NAME=$1
lvchange -an ${MIRVOLGRP}/lv_${LV_NAME} &> /dev/null && printf "%s\n" "Volume ${MIRVOLGRP}/lv_${LV_NAME} is now Inactive..."
}

### Step 1b - Preliminary Checks
## Let's make sure our Source Boot device is mounted, according to output of 'mount'

### Begin Changes made on 06/11/2010
## mount | grep -q "${SRCBOOT}"
### End Changes made on 06/11/2010

stat ${SRCBOOT} &> /dev/null; RETCODE=$?
    if [ "${RETCODE}" != "0" ]; then
        printf "%s\n" "Our Source Boot Device ${SRCBOOT} is not mounted. Unable to proceed until fixed."
        exit 1
    fi

# If ${MIRBOOTDM} is empty, we do not know our SAN Boot device, exiting
if [ -z ${MIRBOOTDM} -o -z ${MIRBOOTWWN} ]; then
   printf "%s\n" "One or more critical variables is missing. Please check defined variables. Lines 10-14 in this script." 
     exit 1
   else
  clear
  printf "%s\n SOURCE BOOT : ${SRCBOOT}  DESTINATION BOOT : ${MIRBOOTDM}\n SOURCE ROOTDISK (LVM) : ${SRCVOLGRP} DESTINATION ROOTDISK (LVM) : ${MIRVOLGRP}\n"
  sleep ${TIMEOUT} 
fi 

### Step 2 - Verify Mirror Rootdisk
## Need a method to verify that we have correct Mirror Boot Disk
#
#
#

### Step 3 - Create necessary directories
## Make sure necessary directory structure is in place under /mnt

# for DIR in mir3 snap ## First tier directories
#   do
#   [ ! -d /mnt/${DIR} ] && echo mkdir /mnt/${DIR}
#   done

# for DIR in root var export ## Second tier directories
#   do
#   [ ! -d /mnt/mir3/${DIR} ] && echo mkdir /mnt/mir3/${DIR}
#   [ ! -d /mnt/mir3/${DIR} ] && echo mkdir /mnt/snap/${DIR}
#   done

# [ ! -d /mnt/mir3/boot ] && echo mkdir /mnt/mir3/boot


### Step 4 - Check for, and create LVs and filesystems as necessary 
## Check for existance of filesystem on ${MIRBOOT}
#
# Need to establish method for this step
#

## Check for existance of Mirror PV Device
printf "%s\n" "...Checking for existance of PV Devices on Mirrored Storage..."

if [ -h ${MIRBOOTDISK}p2  ]; then
   pvdisplay -s ${MIRBOOTDISK}p2 ; RETCODE=$? # Check for Partition 2 labeled <diskid>p2 and return status
   [ ${RETCODE} = 0 ] && printf "%s\n" "PV Device ${MIRBOOTDISK}p2 was found"
elif [ -h ${MIRBOOTDISK}-part2  ]; then
   pvdisplay -s ${MIRBOOTDISK}-part2 ; RETCODE=$? # Check for Partition 2 labeled <diskid>-part2 and return status
   [ ${RETCODE} = 0 ] && printf "%s\n" "PV Device ${MIRBOOTDISK}-part2 was found"
fi

    if [ ${RETCODE} != 0  ]; then # Looks like the PV for SAN Rootdisk is not found, so we create it
        printf "%s\n" "CRITICAL: Could not identify Physical Volume from SAN Disk defined in LVM. Please check manually..."
        exit 1
        # MYLVS=( root var export swap )
        ## Create Physical Volume and Group for LVM
        #   echo pvcreate ${MIRBOOTDISK}p2 \
        #   && printf "%s\n" "Created PV ${MIRBOOTDISK}p2"
        #   echo vgcreate ${MIRVOLGRP} ${MIRBOOTDISK}p2 \
        #   && printf "%s\n" "Created VG ${MIRVOLGRP} using ${MIRBOOTDISK}p2"
        
        ## Create Logical Volumes in new Group and 'mkfs' them
        #   for LV in "${MYLVS[@]: 0:2}" # These two are 4GB LVs and filesystems
        #      do
        #      echo lvcreate --name lv_${LV} -L4G ${MIRVOLGRP} \
        #      && printf "%s\n" "Created LV lv_${LV} in ${MIRVOLGRP}"
        #     echo mkfs -t ext3 /dev/${MIRVOLGRP}/lv_${LV} &> /dev/null
        #      done
              
        #   for LV in "${MYLVS[@]: 2:4}" # These two are 1GB LVs and filesystems
        #      do
        #      echo lvcreate --name lv_${LV} -L1G ${MIRVOLGRP} \
        #      && printf "%s\n" "Created LV lv_${LV} in ${MIRVOLGRP}"
        #      echo mkfs -t ext3 /dev/${MIRVOLGRP}/lv_${LV} &> /dev/null 
        #      done
   
    else  # If return code is "0", we are assuming that PV was created

        (vgchange -ay ${MIRVOLGRP} \
        && printf "%s\n" "Changed status of ${MIRVOLGRP} to Active...") || exit 1
           
        for LV in "${MYLVS[@]: 0:2}" # These two are 4GB LVs and filesystems
            do
            [ ! -h /dev/${MIRVOLGRP}/lv_${LV} ] && lvcreate --name lv_${LV} -L4G ${MIRVOLGRP}
            # mkfs -t ext3 /dev/${MIRVOLGRP}/lv_${LV}
            done
              
        for LV in "${MYLVS[@]: 2:4}" # These two are 1GB LVs and filesystems
            do
            [ ! -h /dev/${MIRVOLGRP}/lv_${LV} ] && lvcreate --name lv_${LV} -L1G ${MIRVOLGRP}
            # mkfs -t ext3 /dev/${MIRVOLGRP}/lv_${LV}
            done
        fi

### Step 5 - Replicate data between SAN and Local Disk
## Replicate /boot

stat ${MIRBOOTDM} &> /dev/null; RETCODE=$?
 
    if [ "${RETCODE}" != "0" ]; then # If return code is not 'zero' we need to re-make the filesystem
        clear
        printf "%s\n" "It appears that ${MIRBOOTDM} is invalid. Please check your SAN_BOOT device"
        exit 1     
    else
        clear
        printf "%s\n" "Performing copy -dd- of /boot..."
        unmount_boot || exit 1
    
        dd if=${SRCBOOT} of=${MIRBOOTDM} bs=4k; RETCODE=$?
        if [ "${RETCODE}" = "0" ]; then
             tune2fs -L "SAN_BOOT" ${MIRBOOTDM} &> /dev/null
             remount_boot || printf "%s\n" "Failed to re-mount directory /boot, Please check manually."
             printf "%s\n" "Duplicated local ${SRCBOOT} to SAN ${MIRBOOTDM} Successfully."
         else
             remount_boot || printf "%s\n" "Failed to re-mount directory /boot, Please check manually."
             printf "%s\n" "Duplication from local ${SRCBOOT} to SAN ${MIRBOOTDM} Failed. Exiting..."
             exit 1
         fi
    fi

### Begin Changes made on 06/17/2010
## Replicate Logical Volumes

for LV_NAME in "${MYLVS[@]: 0:3}" 
    do
        sync_lvs ${LV_NAME}
        cleanup-snap ${LV_NAME}; RC_CLEAN=$?
   done
### End Changes made on 06/17/2010

### Step 6 - This is where we make changes to various configuration files on our SAN disk
modify_grub

### Step 7 - Need to offline LVM SAN Logical Volumes and Volume Group
## Function offline_lvs is defined above and takes only one argument.
## Variable DIR is iterated based on the list of LVs which we defined in
## the MYLVS Array at the top of the script. 

for DIR in "${MYLVS[@]}"
    do
        offline_lvs ${DIR} 
    done

vgchange -an ${MIRVOLGRP}