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
## 08/01/2010 - Script is in alpha stage with revisions ongoing.
## 08/16/2010 - Need to develop a logging mechanism, no logging at the moment.
##
##
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

###############################################################################
### Step 1 : Define Variables and Functions used throughout the script
###############################################################################

###############################################################################
### Step 1a : Initialization functions required to setup script functionality
###############################################################################

usage() {
	printf "%s\n\n" "setupASMDisks_SUSE.sh - used to setup partitioning of LUNs for use under ASM"
	printf "%s\n" "Usage:"
    printf "\t%s\n\n" "Run ./setupASMDisk.ksh [-f] /path/to/file"
	printf "\t%s\n" "[-f] Force setup of previously partitioned LUNs" "[-h] Will return this usage menu"
	printf "\t%s\n" "[-u] Will only update ASM configuration on nodes other than one where LUNs were added"
}
 
filecleanup() {
# Clean up temp files
printf "%s\n" "Cleaning up temporary files ..."
rm -f /tmp/fdisk.setup.cmds.${PID}
rm -f /tmp/multipath.${PID}
rm -f /tmp/set_ASM_perms.${PID}
}

# Check check and set arguments
force=""
while getopts "ufhH" ARGS
do
	case ${ARGS} in
		f)
			force="yes"
			;;
        u)
            SCAN_ONLY="yes"
			;;
	h|H|*)
			usage
			exit 1
			;;
	esac
done

# Check for file(s) passed
shift $(($OPTIND - 1))

if [[ "${SCAN_ONLY}" = "yes" ]]; then
    clear
    printf "%s\n" "###############################################################################"    
    printf "%s\n" "Updating Oracle ASM after New LUNs were provisioned on another node..."
    printf "%s\n" "###############################################################################" 
    oracleasm scandisks > /dev/null 2>&1;
    filecleanup
    exit 0
fi

if [[ $# -lt 1 ]]; then
	usage
	printf "%s\n" "ERROR: no files specified"
	exit 1
fi

if [[ $# -gt 1 ]]; then
	usage
	printf "%s\n" "ERROR: multiple files specified:"
	for f in "$@"
	do
		echo "${f}"
	done
	exit 1
fi

###############################################################################
### Step 1b : Variables used globally in the script
###############################################################################

PID=$$
LOG_FILE=/tmp/ASM-disk-setup.${PID}
LUN_RAW_INPUT_FILE=$@  ## Variable pointing to the path of the input file
DATESTAMP=$(date "+%Y%m%e")
DEBUG=1

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
### Step 1c : Functions called later in the script
###############################################################################


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
    
fdisk "/dev/mapper/${EACH_LUN}" <<EOF 1> /dev/null 2&>1;
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
  
    if [[ ! "${RET_CODE}" = "0" ]]; then
        
        clear
        printf "%s\n" "ERROR: Something went wrong while Partitioning New LUN"
        printf "\t%s\n" "LUN:" "${EACH_LUN}"
        printf "\t%s\n\n" "Possible Cause: fdisk not being able to re-read the Partition Table"
        printf "%s" "Do you want to continue [y], or stop here and troubleshoot [n]? [y/n] "
        read "ANS"
        ## If no answer is supplied we will assume the answer is no
        if  [[ "${ANS}" =~ [Yy] ]]; then
            printf "%s\n" "Continuing..."
            sleep 2
            RET_CODE=0
        elif [[ -z "${ANS}" || "${ANS}" =~ [Nn] ]]; then
            printf "%s\n" "Aborting Partitioning..."
            sleep 2
            RET_CODE=1
            break
        fi
    fi
done
return "${RET_CODE}"
}

### Doing partprobe at this stage should be unneccessary
## partprobe

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

return "${RET_CODE:=0}"
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
    		printf "\t%s" "Do you want to view the disk partitioning? [y/n] "
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
    ## printf "%s\n" "Flushing MPATH and Creating New Mappings for Partitions on LUN: ${EACH_LUN}"   

    [ "${DEBUG}" = "1" ] &&  printf "%s\n" "Executing multipath -f ${EACH_LUN}"
    multipath -f "${EACH_LUN}" > /dev/null 2>&1; multipath -l "{EACH_LUN}" > /dev/null 2>&1;
    ## Success from multipath -f "LUN" always returns "1", as such we need to make sure
    ## That we can correctly identify whether multipath was really successful, and it if was
    ## We want to finx the return code to be "0" instead of "1"
    RET_CODE=$?; RET_CODE="${RET_CODE:+0}"

	if [[ ! "${RET_CODE}" = "0" ]]; then
            printf "%s\n"
            printf "%s\n" "###############################################################################"
            printf "%s\n" "ERROR: Multipathd encountered a problem with LUN" "LUN: ${EACH_LUN}"
            printf "%s\n" "###############################################################################"
            sleep 2
		else
		    printf "%s\n"
            printf "%s\n" "###############################################################################"
            printf "%s\n" "SUCCESS: Flushed Multipathd and Device-Mapper for LUN" "LUN: ${EACH_LUN}"            
            printf "%s\n" "###############################################################################"
            sleep 2
	fi
done

## We need to update multipath to make sure that it picks-up LUNs we flushed
## and adds newly created partitions to the system

clear
printf "%s\n" "Please, be patient... Gathering information from multipath."
multipath -v2 >> "${LOG_FILE}"
RET_CODE=0

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do 
   	kpartx -a -p -part /dev/mapper/${EACH_LUN};
    sleep 4
## Here we check whether or not block-device abd symlink were created
## A warning is printed if the mpath block device or symlink missing

    if [[ ! -b "/dev/mapper/${EACH_LUN}-part1" ||  ! -h "/dev/disk/by-id/scsi-${EACH_LUN}-part1" ]]; then
            printf "%s\n" "###############################################################################"
            printf "%s\n" "ERROR: DM Device or Symlink creation with kpartx failed for LUN" "LUN: ${EACH_LUN}"
            printf "%s\n" "###############################################################################"
            printf "%s\n" "This issue will need to be resolved manually."
            sleep 2
            
            [ "{DEBUG}" = "1" ] && stat "/dev/mapper/${EACH_LUN}-part1" "/dev/disk/by-id/scsi-${EACH_LUN}-part1"
            RET_CODE=1
        else
            printf "%s\n"
            printf "%s\n" "###############################################################################"            
            printf "%s\n" "Success: Created DM-Device and Symlink for LUN" "LUN: ${EACH_LUN}"
            printf "%s\n" "###############################################################################"
            sleep 2
    fi
	
done

return "${RET_CODE}"
}


add_LUN_to_ASM ()

{
for EACH_LUN in ${DATA_LUN_LIST[@]}

do 

    LUN_LABEL=$(printf "${EACH_LUN}" | awk '{print toupper(substr($1, 17, 17))}')
    /usr/sbin/oracleasm createdisk "DB_${LUN_LABEL}" /dev/mapper/${EACH_LUN}-part1; ## false

	if [[ ! "$?" = "0" ]]; then
        printf "%s\n" "###############################################################################"
	    printf "%s\n" "ERROR: Failed to add DATA LUN to Oracle ASM" "LUN: ${EACH_LUN}"
        printf "%s\n" "###############################################################################"	
	    RET_CODE=1
	fi
	
done

for EACH_LUN in ${FRA_LUN_LIST[@]}

do 

    LUN_LABEL=$(printf "${EACH_LUN}" | awk '{print toupper(substr($1, 17, 17))}')
    /usr/sbin/oracleasm createdisk "FRA_${LUN_LABEL}" /dev/mapper/${EACH_LUN}-part1; ## false

	if [[ ! "$?" = "0" ]]; then
        printf "%s\n" "###############################################################################"
	    printf "%s\n" "ERROR: Failed to add FRA LUN to Oracle ASM" "LUN: ${EACH_LUN}"
        printf "%s\n" "###############################################################################"
	    RET_CODE=1
	fi

done

return "${RET_CODE:=0}"
}

###############################################################################
### Step 2 : Begin Execution of Main part of the script
###############################################################################

## If we passed the update option to the script, we are only going to scan ASM
## to update node's ASM configuration, assming LUNs were already provisioned
## on another node in the cluster

multipath -v2
multipath -ll > /tmp/multipath.${PID}

### This is where we execute our verification function to confirm that
### we have correct number of paths for each LUN, if we do not,
### we are going to exit at this point to allow for manual troubleshooting
verify_lun_number_of_paths; RET_CODE=$?; [ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

[ "${DEBUG}" = "1" ] && printf "%s\n" "Total LUN Count is ${TOTAL_LUN_COUNT} Counter is at ${COUNTER}"

### We expect that COUNTER from above will match TOTAL_LUN_COUNT
if [[ "${TOTAL_LUN_COUNT}"  != "${COUNTER}" ]]; then
    printf "%s\n" "Some of the LUNs being Provisioned do not have correct number of paths. Cannot Continue..."

    filecleanup  ## We make sure that any files that we create are removed upon exit 
    exit "${RET_CODE}"
else
    printf "%s\n" "All LUNs being Provisioned have correct number of paths. Continuing..."
    sleep 2
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
            printf "%s\n" "ASM Provisioning of the following LUNs was cancelled...:"
            printf "\t%s\n" "${FRA_LUN_LIST[@]}" "${DATA_LUN_LIST[@]}"
            printf "%s\n\n" "###############################################################################"
            printf "%s\n" "" "Please, re-check the LUN(s), and adjust input file, if LUN(s) should be excluded."
            
            filecleanup  ## We make sure that any files that we create are removed upon exit
            exit "${RET_CODE}"
        else
            printf "%s\n" "All LUNs were verified as OK to re-partition. Continuing..."
            sleep 2
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

device_map_create_each_LUN; RET_CODE=$?; [[ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

if [[ "${RET_CODE}" != "0" ]]; then
        clear
        printf "%s\n" "###############################################################################"
        printf "%s\n" "WARNING: Created DM Devices and Symlinks, but some errors were encountered."
        printf "%s\n" "###############################################################################"
    else
        printf "%s\n" "###############################################################################"
        printf "%s\n" "SUCCESS: Created DM Devices and Symlinks without any errors."
        printf "%s\n" "###############################################################################"
fi

[ "${DEBUG}" = "1" ] && printf "%s\n" "DM and Symlink Creation Function Return Code: ${RET_CODE}"

add_LUN_to_ASM; RET_CODE=$?; [[ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

if [[ "${RET_CODE}" != "0" ]]; then
        clear
        printf "%s\n" "###############################################################################"
        printf "%s\n" "WARNING: At least one LUN was not added to Oracle ASM."
        printf "%s\n" "###############################################################################"
    else
        printf "%s\n" "###############################################################################"
        printf "%s\n" "SUCCESS: Configured all LUNs under Oracle ASM."
        printf "%s\n" "###############################################################################"
fi

[ "${DEBUG}" = "1" ] && printf "%s\n" "LUN ASM Config Function Return Code: ${RET_CODE}"

###############################################################################
## END Tested Block of code 07/23/2010
###############################################################################


# List out ASMLib disks
# echo "Listing out disks setup into ASMLib:"
# /etc/init.d/oracleasm listdisks
#
## Function defined at the beginning of the script
filecleanup

printf "%s" "Completed setup of New LUNs..." 

if [[ "${WARN_ON_EXIT}" = "Y" ]]; then
        printf "%s\n" " However some issues were encountered."
        exit 1
    else
        exit 0
fi

