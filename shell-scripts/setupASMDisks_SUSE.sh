#!/bin/bash
##: Title       : USPS Automatic Storage Management Provisioning Tool
##: Date Rel    : 08/01/2008
##: Date Upd    : 09/08/2010
##: Author      : "Sam Zaydel" <sam.zaydel@usps.gov>
##: Version     : 0.1.4
##: Release     : Beta
##: Description : ASM Storage Provisioning script improved over original
##: Options     : -f -hH -o -u
##: Filename    : setupASMDisks_SUSE.sh
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
## : 08/01/2010 - Script is in alpha stage with revisions ongoing.
## : 08/09/2010 - Added sections necessary to flush and update multipath.
## : 08/16/2010 - Need to develop a logging mechanism, no logging at the moment.
## : 09/01/2010 - Added redirection of some lines to LOG files
## : ********** - Modified getopts to make sure that Force flag is not '-f'
## : 09/02/2010 - Improved logging by incorporating DEBUG output
## : 09/07/2010 - Improved getopts construct to prevent possibility of 
## multiple files not being recognized as multiple files.
## : 09/08/2010 - Updated 'Usage' section
##
##
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
    printf "%s\n"
	printf "%s\n\n" "$(basename $0) - Used to setup partitioning of LUNs for use with Oracle ASM"
	printf "%s\n" "Usage:"
    printf "\t%s\n\n" "Typical Usage: Run ./$(basename $0) [-f] /path/to/file"
	printf "\t%s\n" "[-h] Will return this usage menu" "[-o] Will 'force' setup of previously partitioned LUNs"
	printf "\t%s\n" "[-u] Will only update ASM configuration on nodes other than one where LUNs were added"
	printf "%s\n" "Reminder:"
	printf "\t%s\n" "Please, do not forget to do a LUN scan prior to using $(basename $0)"
}
 
filecleanup() {
# Clean up temp files
printf "%s\n" "Cleaning up temporary files ..."
rm -f /tmp/fdisk.setup.cmds.${PID}
rm -f /tmp/multipath.${PID}
## rm -f /tmp/set_ASM_perms.${PID} <- This is deprecated
}

if [[ "$#" -lt 1 ]]; then
    printf "%s\n" "ERROR: Please, specify at least one option."
    usage
    exit 1
fi

# Check check and set arguments
LUN_RAW_INPUT_FILE=""
force=""
DEBUG=1
## Set the Options index to 1
OPTIND=1
OPT_COUNTER=0
while getopts f:ouhH ARGS
do
	case ${ARGS} in
        f)  ## Filename passed to the script with '-f' option
            LUN_RAW_INPUT_FILE="${OPTARG}"
            if [[ ! -f "${LUN_RAW_INPUT_FILE}" ]]; then
    	        printf "%s\n" "ERROR: File ${LUN_RAW_INPUT_FILE} does not exist. Cannot Continue."
	            exit 1
            fi
			;;
		o)
			force="yes"
			OPT_COUNTER=$((OPT_COUNTER + 1))
			;;
        u)
            SCAN_ONLY="yes"
            OPT_COUNTER=$((OPT_COUNTER + 1))
			;;
        h|H|*)
			usage
			exit 0
			;;
	
	esac
done

## Here we calculate number of parameters passed minus number of optional
## parameters like '-o' or '-u'.
REQ_PARAMS_COUNT=$(( $# - ${OPT_COUNTER} ))

## Section used for debugging the getopts construct above
## This should normally be disabled using the 'DEBUG' flag

    if [[ "${DEBUG}" -ge "2" ]]; then
        echo Options Index is at "${OPTIND}"
        echo Options Count is at "${OPT_COUNTER}"
        echo Number of arguments passed "$#"
        echo Index minus Options Count "${REQ_PARAMS_COUNT}"
        ## sleep 600
    fi  

###############################################################################
### Step 1b : Variables used globally in the script
###############################################################################

DATE=$(date "+%Y%m%d")
TIMESTAP=$(date "+%T")
PID=$$
INFO_LOG="/tmp/setupASM-INFO-${DATE}.${PID}"
ERR_LOG="/tmp/setupASM-ERR-${DATE}.${PID}"

if [[ "${SCAN_ONLY}" = "yes" ]]; then
    clear
    printf "%s\n" "###############################################################################"    
    printf "%s\n" "Updating Oracle ASM after New LUNs were provisioned on another node..."
    printf "%s\n" "###############################################################################" 
    oracleasm scandisks 1>> "${INFO_LOG}" 2>> "${ERR_LOG}"
    filecleanup
    exit 0
fi

if [[ "${REQ_PARAMS_COUNT}" -gt 2 ]]; then ## Added on 09/05/2010
	printf "%s\n" "ERROR: Multiple files specified, unable to proceed."
	usage
	exit 1
fi

if [[ ! -f "${LUN_RAW_INPUT_FILE}" ]]; then
    printf "%s\n" "ERROR: Something went wrong. Please, review usage."
    usage
    exit 1
fi
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

[[ "${DEBUG}" -ge "2" ]] && sleep 3600 ## Added for troubleshooting purposes

###############################################################################
### Step 1c : Functions called later throughout the script
###############################################################################
loginfo ()
## Function to log to 'INFO_LOG'
{
tee -a "${INFO_LOG}"
}


check_if_LUN_partitioned ()

{
## Block of code to confirm whether LUN is already partitioned and ask user
## for input of what action to take has been tested with partitioned and 
## non-partitioned disk

[ "${DEBUG}" = "1" ] && printf "%s\t%s\n" "${TIMESTAP} Function name : check_if_LUN_partitioned" >> "${INFO_LOG}"

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

partition_each_LUN ()

{
## Block of code to apply partition table to a LUN in the two arrays
## DATA_LUN_LIST and FRA_LUN_LIST
## We are partitioning disks and allocating the entire disk to Part-1
## We do this to make sure that even if someone blows away the MBR on the LUN
## the ASM Metadata is still intact, because it is not stored in the MBR
## rather, it is sitting at the beginning of Part-1

[[ "${DEBUG}" -ge "1" ]] && printf "%s\t%s\n" "${TIMESTAP} Function name : partition_each_LUN" >> "${INFO_LOG}"

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do   
    printf "%s\n" "Applying New Partition Table to LUN ${EACH_LUN}" | loginfo
    unset ANS
    
## Do not adjust line spaces after fdisk command and EOF
## CR's are necessary to pass returns to fdisk
fdisk "/dev/mapper/${EACH_LUN}" <<EOF 1>> "${INFO_LOG}" 2>> "${ERR_LOG}"
o
n
p
1
    
    
w
EOF
    RET_CODE=$?

[[ "${DEBUG}" -ge "1" ]] && printf "%s\n" "Return Code from fdisk is: ${RET_CODE}" >> "${INFO_LOG}"

## We will stop looping through list of LUNs if any failure is encountered
## while we are partitioning a LUN
## We want to give user a choice to continue or to stop
  
    if [[ ! "${RET_CODE}" = "0" ]]; then

        printf "%s\n" "ERROR: Something went wrong while Partitioning New LUN"
        printf "\t%s\n" "LUN:" "${EACH_LUN}"
        printf "\t%s\n\n" "Possible Cause: fdisk not being able to re-read the Partition Table"
        printf "%s" "Do you want to continue [y], or stop here and troubleshoot [n]? [y/n] "
        read "ANS"
        ## If no answer is supplied we will assume the answer is no
        if  [[ "${ANS}" =~ [Yy] ]]; then
            printf "%s\n" "Continuing..."
            sleep 2
            RET_CODE=0 ## Function will return 0 - success
        elif [[ -z "${ANS}" || "${ANS}" =~ [Nn] ]]; then
            printf "%s\n" "Aborting Partitioning..."
            sleep 2
            RET_CODE=1 ## Function will return 1 - failure
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

[[ "${DEBUG}" -ge "1" ]] && printf "%s\t%s\n" "${TIMESTAP} Function name : verify_lun_number_of_paths" >> "${INFO_LOG}"

COUNTER=0  ## We start out at zero, and expect to match the number with FRA_LUN_COUNT
# clear

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}
    do
    printf "%s\n" "DEV[${COUNTER}]=${EACH_LUN}" | loginfo

    ## Here we create an ARRAY SINGLE_PATH_ARRAY, which will contain four paths for each LUN
    ## Our goal is to make sure that we have four paths to each LUN, if we do not
    ## we likely need to stop and do some manual troubleshooting 
    SINGLE_PATH_ARRAY=($(grep -A7 "${EACH_LUN}" "/tmp/multipath.${PID}" | grep sd | sed -e "s/[\,_,  *]/ /g" | awk '{print "/dev/" $2}'))

[[ "${DEBUG}" -ge "1" ]] && printf "%s\n" "Multipath registered ${#SINGLE_PATH_ARRAY[@]} paths to device /dev/mapper/${EACH_LUN}." >> "${INFO_LOG}"
    
    printf "%s\n" "Individual Paths for DEV[${COUNTER}] :" | loginfo
    printf "%s\n" "${SINGLE_PATH_ARRAY[@]}" | loginfo
    
    ## We check to make sure that SINGLE_PATH_ARRAY has four elements in it
    ## If it does, we assume that we have the right number of paths to proceed
        if [[ "${#SINGLE_PATH_ARRAY[@]}" -eq "4" ]]; then 
            printf "%s\n\n" "Confirmed 4 available paths to Device." | loginfo
            COUNTER=$((COUNTER + 1))
        else
            printf "%s\n" "Expected number of paths to LUN ${EACH_LUN} must equal to 4." | loginfo
            RET_CODE=1
        fi

    done

return "${RET_CODE:=0}"
}

device_map_create_each_LUN ()

{
## Block of code to flush multipath after partitioning operation took place
## on each LUN being provisioned in DATA_LUN_LIST and FRA_LUN_LIST
## We want to make sure that system will create a new DM-device for -Part1
## and new symlinks for the device and -Part1 under /dev/disk/by-... tree
[[ "${DEBUG}" -ge "1" ]] && printf "%s\t%s\n" "${TIMESTAP} Function name : device_map_create_each_LUN" >> "${INFO_LOG}"

for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

do   
    printf "%s\n" "Flushing MPATH and Creating New Mappings for Partitions on LUN: ${EACH_LUN}" | loginfo

[ "${DEBUG}" = "1" ] &&  printf "%s\n" "Executing multipath -f ${EACH_LUN}"  >> "${INFO_LOG}"

    multipath -f "${EACH_LUN}" > /dev/null 2>&1; multipath -l "{EACH_LUN}" > /dev/null 2>&1;
    ## Success from multipath -f "LUN" always returns "1", as such we need to make sure
    ## That we can correctly identify whether multipath was really successful, and it if was
    ## We want to fix the return code to be "0" instead of "1"
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
printf "%s\n" "Please, be patient... Gathering information from multipath."
# clear

multipath -v2 >> "${INFO_LOG}"
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
            
            [ "{DEBUG}" = "1" ] && stat "/dev/mapper/${EACH_LUN}-part1" "/dev/disk/by-id/scsi-${EACH_LUN}-part1" >> "${INFO_LOG}"
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
[[ "${DEBUG}" -ge "1" ]] && printf "%s\t%s\n" "${TIMESTAP} Function name : add_LUN_to_ASM" >> "${INFO_LOG}"

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
        [[ "${DEBUG}" -ge "1" ]] && /usr/sbin/oracleasm querydisk "/dev/mapper/${EACH_LUN}-part1" >> "${INFO_LOG}"
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
        [[ "${DEBUG}" -ge "1" ]] && /usr/sbin/oracleasm querydisk "/dev/mapper/${EACH_LUN}-part1" >> "${INFO_LOG}"
    done

return "${RET_CODE:=0}"
}

###############################################################################
### Step 2a : Begin Execution of Main part of the script
###############################################################################

## If we passed the update option to the script, we are only going to scan ASM
## to update node's ASM configuration, assming LUNs were already provisioned
## on another node in the cluster
printf "%s\n" "Please, be patient... Gathering information from multipath."
multipath -v2  >> "${INFO_LOG}"
multipath -ll > /tmp/multipath.${PID}

### This is where we execute our verification function to confirm that
### we have correct number of paths for each LUN, if we do not,
### we are going to exit at this point to allow for manual troubleshooting
verify_lun_number_of_paths; RET_CODE=$?; [[ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

[ "${DEBUG}" = "1" ] && printf "%s\n" "Total LUN Count is ${TOTAL_LUN_COUNT} Counter is at ${COUNTER}" >> "${INFO_LOG}"

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
[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : check_if_LUN_partitioned" "LUN MBR Check Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"

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

###############################################################################
### Step 2b : If all checks succeed we begin to partition LUNs
###############################################################################

### This is where we execute our partitioning function used to create one
### partition covering the whole disk 

partition_each_LUN; RET_CODE=$?
[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : partition_each_LUN" "LUN Partitioning Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"

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

[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : device_map_create_each_LUN" "DM and Symlink Creation Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"

###############################################################################
### Step 2c : Last step is to add LUNs to ASM for DBSS
###############################################################################

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

[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : add_LUN_to_ASM" "LUN ASM Config Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"


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

