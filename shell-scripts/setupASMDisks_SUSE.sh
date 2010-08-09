#!/bin/bash

###############################################################################
### NOTES: ####################################################################
###############################################################################
## This script was converted from a ksh version and was fundamentally changed
## in order to streamline the process, and improve disk verification
##
###############################################################################
### Index/Description of Functions included in Library
###############################################################################
##
###############################################################################
### Revisions: ################################################################
###############################################################################
##
##
##
##
###############################################################################
### Step 1 : Define Variables and Functions used throughout the script
###############################################################################

###############################################################################
### Step 1a : Variables used globally in the script
###############################################################################
PID=$$
LOG_FILE=/tmp/ASM-disk-setup.${PID}
LUN_RAW_INPUT_FILE=$@  ## Variable pointing to the path of the input file
DATESTAMP=$(date "+%Y%m%e")
DEBUG=1


###############################################################################
################# Major objectives and expected behavior ######################
###############################################################################
### IMPORTANT:
### 1. multipath "MUST" show four paths for each LUN being provisioned
### 2. we error-out if condition 1 is not met.
### 3. LUNs could contain letters, we need to make sure that 
### ALL input from the input file is converted to lowercase
### 4. strong check is required to make sure LUN is not already used
### 5. If LUN is in use, and user does not want to re-write the partition
### table, we exist with the return code 1.
### 6. all fdisk'ing "MUST" happen against a '/dev/mapper' device
### 
###############################################################################

### Build our LUN Array based on RAW input file - testing with /tmp/asm_setup_input.raw
### We need two ARRAYS one for FRA disks and one for DB disks

### Also we create a variable with the count of LUNs in the list
### which we will later use to compare against the count of verified LUNs 
### those which we know have four individual paths
### 'TOTAL_LUN_COUNT' should contain a sum of LUNs in the two variables :
### 'DATA_LUN_COUNT' and 'FRA_LUN_COUNT'

## Individual ARRAY for FRA Disks being provisioned to the cluster
FRA_LUN_LIST=( $(cat "${LUN_RAW_INPUT_FILE}" | tr '[:upper:]' '[:lower:]' | awk '/fra/ {print "3"$NF}' | sort -u) )

## Individual ARRAY for DATA Disks being provisioned to the cluster
DATA_LUN_LIST=( $(cat "${LUN_RAW_INPUT_FILE}" | tr '[:upper:]' '[:lower:]' | awk '/data/ {print "3"$NF}' | sort -u) )

## We determine a sum of 'DATA_LUN_COUNT' and 'FRA_LUN_COUNT', and substitute '0',
## if either variable is not present, which may be because only DATA or only
## FRA LUNs are being provisioned 
TOTAL_LUN_COUNT=$(( ${#FRA_LUN_LIST[@]} + ${#DATA_LUN_LIST[@]} ))


###############################################################################
### Step 1b : Functions called later in the script
###############################################################################

usage() {
	print "setASMDisk.ksh - used to setup partitioning of disks for use in ASM"
	print "Usage: setupASMDisk.ksh [-f] /path/to/file"
	print "   -f   Force setup of disks that are already labelled"
}
 
filecleanup() {
        # Clean up temp files
        echo "Cleaning up temporary files ..."
        rm -f /tmp/fdisk.setup.cmds.${PID}
	rm -f /tmp/multipath.${PID}
	rm -f /tmp/set_ASM_perms.${PID}
}

# Check check and set arguments
force=""
while getopts "fhH" arg
do
	case $arg in
		f)
			force="yes"
			;;
		h|H|*)
			usage
			exit 1
			;;
	esac
done

# Check for file(s) passed
shift $(($OPTIND - 1))
if [[ $# -lt 1 ]]; then
	usage
	print "ERROR: no files specified"
	exit 1
fi

if [[ $# -gt 1 ]]; then
	usage
	print "ERROR: multiple files specified:"
	for f in "$@"
	do
		echo "${f}"
	done
	exit 1
fi

###############################################################################
## BEGIN Tested Block of code 07/27/2010 
###############################################################################

### Function to actually partition individual LUN with Partition 1
### Taking up the whole disk - ASM metadata is applied to Partition 1
partition_each_LUN ()

{
## Block of code to apply partition table to a LUN in the two arrays
## DATA_LUN_LIST and FRA_LUN_LIST
## We are partitioning disks and allocating the entire disk to Part-1
## We do this to make sure that even if someone blows away the MBR on the LUN
## the ASM Metadata is still intact, because it is not stored in the MBR
## rather, it is sitting at the beginning of Part-1

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do   
    printf "%s\n" "Applying New Partition Table to LUN ${EACH_LUN}"   
    unset ANS
    
fdisk "/dev/mapper/${EACH_LUN}" <<EOF
o
n
p
1
    
    
w
EOF
    RET_CODE=$?

[ "${DEBUG}" = "1" ] && printf "%s\n" "Return Code from fdisk is: ${RET_CODE}"

## We will stop looping through list of LUNs if any failure is encountered
## while we are partitioning a LUN
## We want to give user a choice to continue or to stop
  
    if [[ "${RET_CODE}" -ne "0" ]]; then
        
        clear
        printf "%s\n" "ERROR: Something went wrong while Partitioning New LUN"
        printf "%s %5s\n\n\n" "LUN:" "${EACH_LUN}"
        printf "%s" "Do you want to continue [y], or stop here and troubleshoot [n]? [y/n] "
        read "ANS"
        [ -z "${ANS}" ] &&         
        
        [[ "${ANS}" =~ [Yy] ]] && ( printf "%s\n" "Continuing..."; sleep 2 )
        [[ "${ANS}" =~ [Nn] ]] && ( printf "%s\n" "Aborting Partitioning..."; sleep 2 )

         if  [[ ! "${ANS}" =~ [Yy] ]]; then                            
                RET_CODE=1
                break                
            else
                RET_CODE=0            
        fi                       
    fi
done
return "${RET_CODE}"
}

echo partprobe
multipath -ll > /tmp/multipath.${PID}


### We need to make sure that each supplied LUN is underscored by four paths
### on the system, and if not, we need to error out somewhere

verify_lun_number_of_paths ()

{
COUNTER=0  ## We start out at zero, and expect to match the number with FRA_LUN_COUNT
clear

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}
    do
    printf "%s\n" "DEV[${COUNTER}]=${EACH_LUN}" 

    ## Here we create an ARRAY SINGLE_PATH_ARRAY, which will contain four paths for each LUN
    ## Our goal is to make sure that we have four paths to each LUN, if we do not
    ## we likely need to stop and do some manual troubleshooting 
    SINGLE_PATH_ARRAY=($(grep -A7 "${EACH_LUN}" "/tmp/multipath.${PID}" | grep sd | sed -e "s/[\,_,  *]/ /g" | awk '{print "/dev/" $2}'))
    
    printf "%s\n" "Individual Paths for DEV[${COUNTER}] :"
    printf "%s\n" "${SINGLE_PATH_ARRAY[@]}"
    
    ## We check to make sure that SINGLE_PATH_ARRAY has four elements in it
    ## If it does, we assume that we have the right number of paths to proceed
    if [[ "${#SINGLE_PATH_ARRAY[@]}" -eq "4" ]]; then 
        printf "%s\n\n" "Confirmed 4 available paths to Device."
        COUNTER=$((COUNTER + 1))
    else
        printf "%s\n" "Expected number of paths to LUN ${EACH_LUN} must equal to 4."
        RET_CODE=1
    fi
    done
[ "${DEBUG}" = "1" ] && printf "%s\n" "Counter is currently at ${COUNTER}"

return "${RET_CODE}"
}

check_if_LUN_partitioned ()

{
## Block of code to confirm whether LUN is already partitioned and ask user
## for input of what action to take has been tested with partitioned and 
## non-partitioned disk
clear
for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do
    if [[ "${force}" != "yes" ]]; then
        ## This statement has to eval true, before message below is printed
        if [[ $(parted -s "/dev/mapper/${EACH_LUN}" print | egrep "msdos|type\=83") != "" && $(sfdisk -l "/dev/mapper/${EACH_LUN}" | egrep -E "^\/dev/" | wc -l) = "4" ]]; then

            printf "%s\n"
    		printf "%s\n" "WARNING: ${EACH_LUN} is already partitioned."
    		printf "Do you want to view the disk partitioning? [y/n] "
    		read "ANS"
    
            if [[ ${ANS} == "y" || ${ANS} == "Y" ]]; then
                clear
        		fdisk -l "/dev/mapper/${EACH_LUN}"
        		printf "%s\n"
    		fi
    		
            printf "%s\n"
            printf "%s\n" "Do you want to continue to setup ASM on LUN ${EACH_LUN}"
            printf "and wipe out its partitioning? [y/n] "
            read "ANS"
                       
            [[ "${ANS}" =~ [Yy] ]] && printf "%s\n" "Your answer is : [YES]"
            [[ "${ANS}" =~ [Nn] ]] && printf "%s\n" "Your answer is : [NO]"
            
            ## If we choose not to proceed with partitioning an already partitioned
            ## LUN, we are going to break out of the loop, and will 
            if  [[ ! "${ANS}" =~ [Yy] ]]; then                            
                    RET_CODE=1
                    break                
                else
                    RET_CODE=0            
            fi
        fi
    fi
done
return "${RET_CODE}"
}

device_map_create_each_LUN ()

{
## Block of code to flush multipath after partitioning operation took place
## on each LUN being provisioned in DATA_LUN_LIST and FRA_LUN_LIST
## We want to make sure that system will create a new DM-device for -Part1
## and new symlinks for the device and -Part1 under /dev/disk/by-... tree

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do   
    printf "%s\n\n" "Flushing MPATH and Creating New Mappings for Partitions on LUN: ${EACH_LUN}"   

    [ "${DEBUG}" = "1" ] &&  printf "%s\n" "Executing multipath -f ${EACH_LUN}"    
    multipath -f "${EACH_LUN}"; RET_CODE=$?

	if [[ ! "${RET_CODE}" = "0" ]]; then
            printf "%s\n" "###############################################################################"
            printf "%s\n" "ERROR: Multipathd encountered a problem with LUN" "LUN: ${EACH_LUN}"
            printf "%s\n" "###############################################################################"
		else
            printf "%s\n" "###############################################################################"
            printf "%s\n" "Success: Flushed Multipathd and Device-Mapper for LUN" "LUN: ${EACH_LUN}"            
            printf "%s\n" "###############################################################################"
	fi
done

## We need to update multipath to make sure that it picks-up LUNs we flushed
## and adds newly created partitions to the system

multipath -v2
RET_CODE=0

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do 
   	kpartx -a -p -part /dev/mapper/${EACH_LUN};

## Here we check whether or not block-device abd symlink were created
## A warning is printed if the mpath block device or symlink missing

    if [[ ! -b "/dev/mapper/${EACH_LUN}-part1" ||  ! -h "/dev/disk/by-id/scsi-${EACH_LUN}-part1" ]]; then
            printf "%s\n" "###############################################################################"
            printf "%s\n" "ERROR: DM Device or Symlink creation with kpartx failed for LUN" "LUN: ${EACH_LUN}"
            printf "%s\n" "###############################################################################"
            printf "%s\n" "This issue will need to be resolved manually."
            [ "{DEBUG}" = "1" ] && stat "/dev/mapper/${EACH_LUN}-part1" "/dev/disk/by-id/scsi-${EACH_LUN}-part1"
            RET_CODE=1
        else
            printf "%s\n" "###############################################################################"            
            printf "%s\n" "Success: Created DM-Device and Symlink for LUN" "LUN: ${EACH_LUN}"
            printf "%s\n" "###############################################################################"
    fi
	
done

return "${RET_CODE}"
}

### This is where we execute our verification function to confirm that
### we have correct number of paths for each LUN, if we do not,
### we are going to exit at this point to allow for manual troubleshooting
verify_lun_number_of_paths >> "${LOG_FILE}" 2&>1; RET_CODE=$?

[ "${DEBUG}" = "1" ] && printf "%s\n" "Total LUN Count is ${TOTAL_LUN_COUNT} Counter is at ${COUNTER}"

### We expect that COUNTER from above will match TOTAL_LUN_COUNT
if [[ "${TOTAL_LUN_COUNT}"  != "${COUNTER}" ]]; then
    printf "%s\n" "Some of the LUNs being Provisioned do not have correct number of paths. Cannot Continue..."

    filecleanup  ## We make sure that any files that we create are removed upon exit 
    exit "${RET_CODE}"
else
    printf "%s\n" "All LUNs being Provisioned have correct number of paths. Continuing..."
    sleep 5
fi

### This is where we execute our partition verification function to check
### that LUNs are not already partitioned, which may mean that they are 
### already in use by the system

check_if_LUN_partitioned; RET_CODE=$?
[ "${DEBUG}" = "1" ] && printf "%s\n" "LUN MBR Check Function Return Code: ${RET_CODE}"

if [[ "${RET_CODE}" != "0" ]]; then
    clear
    printf "%s\n\n" "One or more LUNs already partitioned. You chose not to continue with re-partitioning."
    printf "%s\n" "###############################################################################"
    printf "%s\n" "ASM Provisioning of the following LUNs was cancelled..."
    printf "%s\n" "###############################################################################"
    printf "%s\n" "${FRA_LUN_LIST[@]}" "${DATA_LUN_LIST[@]}"
    printf "%s\n\n" "###############################################################################"
    printf "%s\n" "" "Please, re-check the LUN(s), and adjust input file, if LUN(s) should be excluded."
    
    filecleanup  ## We make sure that any files that we create are removed upon exit
    exit "${RET_CODE}"
else
    printf "%s\n" "All LUNs were verified as OK to re-partition. Continuing..."
    sleep 5
fi

### This is where we execute our partitioning function used to create one
### partition covering the whole disk 

partition_each_LUN; RET_CODE=$?
[ "${DEBUG}" = "1" ] && printf "%s\n" "LUN Partitioning Function Return Code: ${RET_CODE}"

if [[ "${RET_CODE}" != "0" ]]; then
        clear
        printf "%s\n\n" "Error was encountered and you chose to abort."
        printf "%s\n" "###############################################################################"
        printf "%s\n" "Please, manually re-check LUNs with which errors were encountered."
        printf "%s\n" "###############################################################################"
        filecleanup  ## We make sure that any files that we create are removed upon exit
        exit "${RET_CODE}"
    else
        printf "%s\n" "All LUNs were partitioned. Continuing..."
        # sleep 15
fi

device_map_create_each_LUN; RET_CODE=$?
[ "${DEBUG}" = "1" ] && printf "%s\n" "DM and Symlink Creation Function Return Code: ${RET_CODE}"

if [[ "${RET_CODE}" != "0" ]]; then
        clear
        printf "%s\n" "###############################################################################"
        printf "%s\n" "Created DM Devices and Symlinks, but some errors were encountered."
        printf "%s\n" "###############################################################################"
    else
        printf "%s\n" "###############################################################################"
        printf "%s\n" "Created DM Devices and Symlinks without any errors."
        printf "%s\n" "###############################################################################"
fi

###############################################################################
## END Tested Block of code 07/23/2010
###############################################################################

###############################################################################
## BEGIN : Exiting early while testing the script
###############################################################################

exit

###############################################################################
## END : Exiting early while testing the script
###############################################################################




# DEBUG: Print varibles so far
#COUNTER=0
#while [[ $LUNCOUNT -gt $COUNTER ]]; do
#	echo ${SINGLEPATH[${COUNTER}]}
#	echo ${WWN[${COUNTER}]}
#	echo "" 
#	COUNTER=`echo ${COUNTER}+1 | bc`
#done
#filecleanup
#exit

# Check that COUNTER matches amount of LUNs in list
# if [[ $COUNTER -ne $LUNCOUNT ]]; then
#	echo "ERROR: Not all LUNs provided were matched"
#	echo "Number of LUNs provided: ${LUNCOUNT}"
#	echo "Number of paths found: ${COUNTER}"
#	filecleanup
#	exit 1
# fi

# Create files with fdisk commands we will/may use later
# cat > /tmp/fdisk.setup.cmds.${PID} << EOF
#o
#n
#p
#1
#
#
#w
#EOF

# Add check that all paths in multipath have same partition layout

### We are going to be acting on the multipathed device, not an individual path
### When individual paths instead of the device-mapper device are used we run
### into a situation where the kernel does not get updated correctly

## Here we test the LUN against two conditions, to make sure that it does not
## actually have a partition table on it
## The conditions which we test against are :
## 1. When we use 'parted', and grep for "msdos" or "type=83"  do we return
## a positive result and if so we do an additional check
## 2. We check that 'sfdisk' returns "four" lines when we query the disk
## this indicates that we have a standard msdos partition table on the disk 


# Partitions may have been modified, run partprobe
partprobe

clear

# fdisk each disk
# echo ""
# echo "Execute fdisk on all disks ..."
# COUNTER=0
# while [[ $LUNCOUNT -gt $COUNTER ]]; do
#	echo ""
# echo "Executing fdisk on ${SINGLEPATH[${COUNTER}]} ..."
#
#	fdisk ${SINGLEPATH[${COUNTER}]} < /tmp/fdisk.setup.cmds.${PID}
#	if [[ $? -ne 0 ]]; then
#		echo "ERROR: fdisk received error on"
#		echo "SINGLEPATH: ${SINGLEPATH[${COUNTER}]}"
#		echo "WWN: ${WWN[${COUNTER}]}"
#		echo "ERROR: Please check that manually"
#		echo ""
#	else
#		dd if=/dev/zero of=${SINGLEPATH[${COUNTER}]}1 bs=1M count=100
#	fi
#
#	COUNTER=`echo ${COUNTER}+1 | bc`
#done

# Partitions have been modified, run partprobe
## This should not be necessary, when using fdisk against /dev/mapper device
## and during testing it appears that after fdisk 
## partprobe

# Check partitions match up

# kpartx to add multipath devices
COUNTER=0
while [[ $LUNCOUNT -gt $COUNTER ]]; do
	echo ""
	echo "Executing kpartx for ${WWN[${COUNTER}]} ..."
	kpartx -d /dev/mapper/${WWN[${COUNTER}]}
	kpartx -a -p -part /dev/mapper/${WWN[${COUNTER}]}
	if [[ $? -ne 0 ]]; then
		echo ""
		echo "ERROR: kpartx received error on"
		echo "WWN: ${WWN[${COUNTER}]}"
		echo "Reboot may be needed"
	fi

	# Check that new path was created
	if [[ ! -a /dev/mapper/${WWN[${COUNTER}]}-part1 ]]; then
		echo ""
		echo "ERROR: multipath for new partition not created at /dev/mapper/${WWN[${COUNTER}]}-part1"
		echo "Reboot may be needed"
	fi
	if [[ ! -L /dev/disk/by-name/${WWN[${COUNTER}]}-part1 ]]; then
		echo ""
		echo "ERROR: multipath for new partition not created at /dev/disk/by-name/${WWN[${COUNTER}]}-part1"
		echo "Reboot may be needed"
	fi
	COUNTER=`echo ${COUNTER}+1 | bc`
done

# Create file for setting permissions
echo ""
echo "Creating startup script to set ASM disk permissions ..."
COUNTER=0
> /tmp/set_ASM_perms.${PID}
cat > /tmp/set_ASM_perms.${PID} << EOF
### BEGIN INIT INFO
# Provides:          set_ASM_perms
# Required-Start:    multipathd
# Should-Start: 
# Required-Stop:
# Should-Stop:
# Default-Start:     3 5
# Default-Stop:      0 1 2 6
# Short-Description: Sets permissions for ASM disks
# Description:       Sets permissions for ASM disks
### END INIT INFO

case "\$1" in
	start)

EOF
while [[ $LUNCOUNT -gt $COUNTER ]]; do
	echo "chown oracle:dba /dev/mapper/${WWN[${COUNTER}]}-part1" >> /tmp/set_ASM_perms.${PID}
	echo "chmod 660 /dev/mapper/${WWN[${COUNTER}]}-part1" >> /tmp/set_ASM_perms.${PID}
	echo "chown oracle:dba /dev/disk/by-name/${WWN[${COUNTER}]}-part1" >> /tmp/set_ASM_perms.${PID}
	echo "chmod 660 /dev/disk/by-name/${WWN[${COUNTER}]}-part1" >> /tmp/set_ASM_perms.${PID}

	COUNTER=`echo ${COUNTER}+1 | bc`
done
cat >> /tmp/set_ASM_perms.${PID} << EOF

	;;
	*)
		echo "Usage: $0 {start}"
		exit 1
        ;;
esac
EOF


# Setup disks into ASMLib
COUNTER=0
while [[ $LUNCOUNT -gt $COUNTER ]]; do
	NAME_TEMP="`echo ${WWN[${COUNTER}]} | awk '{print substr($1, 17, 17)}'`"

	/etc/init.d/oracleasm createdisk ${DISK_TYPE}_${NAME_TEMP} /dev/mapper/${WWN[${COUNTER}]}-part1

	COUNTER=`echo ${COUNTER}+1 | bc`
done

# List out ASMLib disks
echo "Listing out disks setup into ASMLib:"
/etc/init.d/oracleasm listdisks

## Function defined at the beginning of the script
filecleanup
echo "Disk setup complete"
echo ""
