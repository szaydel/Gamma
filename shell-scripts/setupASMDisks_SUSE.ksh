#!/bin/bash

PID=$$

usage() {
	print "setASMDisk.ksh - used to setup paritioning of disks for use in ASM"
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

### This is where we define the input file from which we extract
### two elements - Whether the disk is DB or FRA and LUN Number

LUN_RAW_INPUT_FILE=$@  ## Added by Sam
# LUN_RAW_INPUT_FILE=$(cat "${LUN_RAW_INPUT_FILE}" | tr '[:upper:]' '[:lower:]')

# LUNLIST=$@
# LUNCOUNT=$(cat ${LUNLIST} | wc -l)

# Prompt if FRA or DB disks
# DISK_TYPE=""
# while [[ "${DISK_TYPE}" == "" ]]
# do
#        DISK_TYPE=` echo $1 | awk -F. '{ print $3 }'`
#	echo "disk type is ${DISK_TYPE}"
#	printf "Are these disks for FRA or DB? ${DISK_TYPE} "
#	read DISK_TYPE
#	if [[ "${DISK_TYPE}" == "db" || "${DISK_TYPE}" == "fra" ]]; then
#		break
#	else
#		DISK_TYPE=""
#		echo "Please enter \"fra\" or \"db\""
#	fi
# done

# Get array with LUN/diskname
# set -A SINGLEPATH ""
#set -A MULTIPATH ""
# set -A WWN ""
#set -A SYMARRAY ""
#set -A LUN ""
#typeset -u WWN
# COUNTER=0

echo partprobe
echo multipath -ll > /tmp/multipath.${PID}

# for n in `cat $LUNLIST`
#do
#	WWN[${COUNTER}]=$n

#	SINGLEPATH[${COUNTER}]="/dev/`grep -A3 ${WWN[${COUNTER}]} /tmp/multipath.${PID} | tail -1 | awk '{print $3}'`"
#        if [[ "${SINGLEPATH[${COUNTER}]}" == "" || ! -a ${SINGLEPATH[${COUNTER}]} ]]; then
#                echo "ERROR: Could not find a single path at ${SINGLEPATH[${COUNTER}]} for ${WWN[${COUNTER}]}"
#                filecleanup
#                exit
#        fi

#        COUNTER=`echo ${COUNTER}+1 | bc`
# done


###############################################################################
################### Sam's modified version of above ###########################
###############################################################################
### IMPORTANT:
### 1. multipath "MUST" show four paths for each LUN being provisioned
### 2. we error-out of condition 1 is not met.
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
FRA_LUN_LIST=($(grep -i fra ${LUN_RAW_INPUT_FILE} | awk '{print "3"$NF}' | tr '[:upper:]' '[:lower:]'))
FRA_LUN_COUNT=$(printf "%s\n" ${FRA_LUN_LIST[@]} | wc -l)

## Individual ARRAY for DATA Disks being provisioned to the cluster
DATA_LUN_LIST=($(grep -i data "${LUN_RAW_INPUT_FILE}" | awk '{print "3"$NF}' | tr '[:upper:]' '[:lower:]'))
DATA_LUN_COUNT=$(printf "%s\n" ${DATA_LUN_LIST[@]} | wc -l)

TOTAL_LUN_COUNT=$(printf "%s\n" "${FRA_LUN_COUNT} + ${DATA_LUN_COUNT}" | bc)

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
    SINGLE_PATH_ARRAY=($(grep -A7 "${EACH_LUN}" /tmp/multipath-meq000.txt | grep sd | sed -e "s/[\,_,  *]/ /g" | awk '{print "/dev/" $2}'))
    
    printf "%s\n" "Individual Paths for DEV[${COUNTER}] :"
    printf "%s\n" "${SINGLE_PATH_ARRAY[@]}"
    
    ## We check to make sure that SINGLE_PATH_ARRAY has four elements in it
    ## If it does, we assume that we have the right number of paths to proceed
    if [[ "${#SINGLE_PATH_ARRAY[@]}" -eq "4" ]]; then 
        printf "%s\n\n" "Good Count..."
        COUNTER=$(echo ${COUNTER}+1 | bc)
    else
        printf "%s\n" "Expected number of paths to LUN ${EACH_LUN} must equal to 4."
        return 1 
    fi
    done
}  

###############################################################################
## BEGIN Tested Block of code 07/23/2010 
###############################################################################
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
            
            ## If we choose not to proceed with 
            if [[ ${ANS} != "y" && ${ANS} != "Y" ]]; then
                return 1
            fi 
        fi
    fi
done
return 0
}

### This is where we execute our verification function to confirm that
### we have correct number of paths for each LUN, if we do not,
### we are going to exit at this point to allow for manual troubleshooting
verify_lun_number_of_paths; RET_CODE=$?

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

###############################################################################
## END Tested Block of code 07/23/2010
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
cat > /tmp/fdisk.setup.cmds.${PID} << EOF
o
n
p
1


w
EOF

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



# Check that disks are not formatted or labeled
# COUNTER=0
# if [[ "${force}" != "yes" ]]; then
# while [[ $LUNCOUNT -gt $COUNTER ]]; do
	# fdisk -l ${SINGLEPATH[${COUNTER}]}
#	if [[ "`fdisk -l ${SINGLEPATH[${COUNTER}]} | grep \"Device Boot\"`" != "" && "`fdisk -l ${SINGLEPATH[${COUNTER}]} | grep \"Device Boot\" -A 1 | tail -1 | awk '{print $1\" \"$2}`" != "Device Boot" ]]; then
#		echo ""
#		echo "WARNING: ${SINGLEPATH[${COUNTER}]} (WWN: ${WWN[${COUNTER}]} is already partitioned."
#		printf "Do you want to view the disk partitioning? [y/n] "
#		read "ANS"
#		if [[ ${ANS} == "y" || ${ANS} == "Y" ]]; then
#			fdisk -l ${SINGLEPATH[${COUNTER}]}
#			echo ""
#		fi
#
#		echo ""
#		echo "Do you want to continue to setup ASM on"
#		echo "${SINGLEPATH[${COUNTER}]} (WWN: ${WWN[${COUNTER}]}"
#		printf "and wipe out its partitioning? [y/n] "
#		read "ANS"
#		if [[ ${ANS} != "y" && ${ANS} != "Y" ]]; then
#			echo "ASM Disk Setup cancelled ..."
#			filecleanup
#			exit
#		fi
#	fi
#	COUNTER=`echo ${COUNTER}+1 | bc`
#done
#fi

# Partitions may have been modified, run partprobe
partprobe

clear

# fdisk each disk
echo ""
echo "Execute fdisk on all disks ..."
COUNTER=0
while [[ $LUNCOUNT -gt $COUNTER ]]; do
	echo ""
	echo "Executing fdisk on ${SINGLEPATH[${COUNTER}]} ..."

	fdisk ${SINGLEPATH[${COUNTER}]} < /tmp/fdisk.setup.cmds.${PID}
	if [[ $? -ne 0 ]]; then
		echo "ERROR: fdisk received error on"
		echo "SINGLEPATH: ${SINGLEPATH[${COUNTER}]}"
		echo "WWN: ${WWN[${COUNTER}]}"
		echo "ERROR: Please check that manually"
		echo ""
	else
		dd if=/dev/zero of=${SINGLEPATH[${COUNTER}]}1 bs=1M count=100
	fi

	COUNTER=`echo ${COUNTER}+1 | bc`
done

# Partitions have been modified, run partprobe
partprobe

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

#cp /tmp/set_ASM_perms.${PID} /var/tmp/set_ASM_perms
#if [[ ! -f /etc/init.d/set_ASM_perms ]]; then
#	cp /tmp/set_ASM_perms.${PID} /etc/init.d/set_ASM_perms
#	chmod 755 /etc/init.d/set_ASM_perms
#	chkconfig set_ASM_perms on
#	service set_ASM_perms start
#else
#	echo "WARNING: /etc/init.d/set_ASM_perms already exists!"
#	echo "Copy provided in /var/tmp/set_ASM_perms"
#	echo "Review and merge /var/tmp/set_ASM_perms into /etc/init.d/set_ASM_perms as needed"
#	echo "Then run:"
#	if [[ "`chkconfig -l | grep set_ASM_perms | grep on`" == "" ]]; then
#		echo "chmod 755 /etc/init.d/set_ASM_perms"
#		echo "chkconfig set_ASM_perms on"
#	fi
#	echo "service set_ASM_perms start"
#	echo ""
#fi

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
#echo "Copy /var/tmp/set_ASM_perms to other systems with same ASM disks into /etc/init.d "
#echo "then run on other nodes after copying:"
#echo "chmod 755 /etc/init.d/set_ASM_perms"
#echo "chkconfig set_ASM_perms on"
#echo "service set_ASM_perms start"
