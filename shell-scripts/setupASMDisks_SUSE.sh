#!/bin/bash
##: Title       : USPS Automatic Storage Management Provisioning Tool
##: Date Rel    : 08/01/2008
##: Date Upd    : 01/27/2010
##: Author      : "Sam Zaydel" <sam.zaydel@usps.gov>
##: Version     : 0.1.5
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
## : 01/24/2010 - Modifying script to act as a wrapper for automation being
## built by Mitch Tishmack.
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
    printf "\t%s\n\n" "Typical Usage: Run ./$(basename $0) -argument"
	printf "\t%s\n" "[-h] Will return this help screen" "[-o] Will 'force' setup of previously partitioned LUNs"
	printf "\t%s\n" "[-p] Start provisioning and ASM setup of new LUNs"
	printf "\t%s\n" "[-s] Will scan/update ASM configuration on nodes other than one where LUNs were added"
	printf "%s\n" "Reminder:"
	printf "\t%s\n" "Important: do not forget to do a LUN scan prior to using $(basename $0)"
}

if [[ "$#" -lt 1 ]]; then
    printf "%s\n" "" "ERROR: At least one argument is reqiured to continue."
    usage
    exit 1
fi

# Check check and set arguments

force=""
DEBUG=1
## Set the Options index to 1
OPTIND=1
OPT_COUNTER=0
## If both of these are empty, we cannot continue
PROVISION=""
SCAN_ONLY=""

while getopts f:opshH ARGS
do
	case ${ARGS} in
        f)  ## Filename passed to the script with '-f' option
#            LUN_RAW_INPUT_FILE="${OPTARG}"
#            if [[ ! -f "${LUN_RAW_INPUT_FILE}" ]]; then
#    	        printf "%s\n" "ERROR: File ${LUN_RAW_INPUT_FILE} does not exist. Cannot Continue."
#	            exit 1
#            fi
			;;
		o)
			force="yes"
			OPT_COUNTER=$((OPT_COUNTER + 1))
			;;
        p)
            PROVISION="yes"
            OPT_COUNTER=$((OPT_COUNTER + 1))
            ;;
        s)
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
CUT=/usr/bin/cut
TR=/usr/bin/tr
AWK=/usr/bin/awk
SED=/usr/bin/sed
GREP=/usr/bin/grep
MPATH_CMD=/sbin/multipath
DATE=$(date "+%Y%m%d")
TIMESTAMP=$(date "+%T")
PID=$$
INFO_LOG="/tmp/setupASM-INFO-${DATE}.${PID}"
ERR_LOG="/tmp/setupASM-ERR-${DATE}.${PID}"
MPINFO="/tmp/multipath.${PID}"
SERVICE_DIR=/sa/info/services
EIR_TAB="${SERVICE_DIR}/etc/eir.tab"
DEV_COUNTER="0"
APP_NAME=""
LUN_RAW_INPUT_FILE=""
SR_NUM=""
SR_ENV=""
EIR_NUM=""
#SEP_LINE=$(printf "%80s\n"|tr ' ' '#')
###############################################################################
### Step 1c : Variables used globally in the script
###############################################################################

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

if [[ ! "${PROVISION}" = "yes" ]]; then
    ## Looks like we are done here, since we do not
    ## need to do anything further, we will exit at this point
    exit 0
fi

#if [[ ! -f "${LUN_RAW_INPUT_FILE}" ]]; then
#    printf "%s\n" "ERROR: Something went wrong. Please, review usage."
#    usage
#    exit 1
#fi

[[ "${DEBUG}" -ge "2" ]] && sleep 3600 ## Added for troubleshooting purposes

###############################################################################
### Step 2a : Functions called later throughout the script
###############################################################################
linesep ()
{
## Print a line separator 80-characters long
printf "%80s\n"|tr ' ' '#'
}

loginfo ()
{
## Prefix output with loginfo for any lines that should print to screen
## and to log file at the same time

    local NOW=$(date "+%F %T")
    local LINE="$@"
    printf "%s\n" "${NOW} ${LINE}" | tee -a "${INFO_LOG}"
}

filecleanup()

{
## Any temporary files created should be removed once we are done
## log files remain untouched
printf "%s\n" "Cleaning up temporary files ..."
rm -f "${MPINFO}"
}

get_env_eir ()

{
## We need collect Environment and Application 'EIR'
local counter="0"
#SR_NUM=""
SR_ENV=""

local counter="0"

while [[ -z "${EIR_NUM}" ]]
    do
        linesep
        printf "%s" "Please enter Application EIR Number: "; read EIR_NUM

        local EIR_NOALPHA=$(printf "${EIR_NUM}" | egrep -v "[[:alpha:]]")

        ## If the field was left blank, prompt user
        if [[ -z "${EIR_NUM}" ]]; then
            printf "%s\n" "EIR Number cannot remain blank. Try Again."
            EIR_NUM=""

        ## If the field is longer than four characters, prompt user
        elif [[ "${#EIR_NOALPHA}" -lt 4 ]]; then
            printf "%s\n" "EIR Number should be 4 digits long. Try Again."
            EIR_NUM=""

        ## If EIR not a valid number, prompt user
        elif [[ ! "${EIR_NUM}" -eq "${EIR_NUM}" ]]; then
            printf "%s\n" "EIR Number does not appear to be valid. Try Again."
            EIR_NUM=""
        fi
    done


while [[ "${counter}" -lt 3 && -z "${SR_ENV}" ]]
    do
        linesep
        printf "%s" "Select Evironment, for SR# ${SR_NUM}: ([C]cat, [D]dev, [P]prod, [S]sit): "; read SR_ENV
        if  [[ ! "${SR_ENV}" =~ [CcDdPpSs] ]]; then
            printf "%s\n" "Environment is not one of the options. Enter ['Q','q'] to quit, or select Environment to continue."
        fi
        linesep

        ## If the environment does not match one of the expected values, raise an error
        ## Also, we need to offer an option to quit at this point, if the user is unsure

        case "${SR_ENV}" in
        C|c) ## Environment is CAT
                SR_ENV="cat"
            ;;
        D|d)  ## Environment is DEV
                SR_ENV="dev"
            ;;
        P|p) ## Environment is PROD
                SR_ENV="prod"
            ;;
        S|s)  ## Environment is DEV
                SR_ENV="sit"
            ;;
        Q|q)  ## User chose to quit
                RET_CODE="1"
            ;;
        *)  ## Environment is ALL
                SR_ENV=""
            ;;
        esac
    local counter=$((counter+1))
    done

if [[ ! -f "${EIR_TAB}" ]]; then
    linesep
    printf "%s\n" "[WARNING] Unable to locate EIR Table, file not found."
    printf "%s" "Please, manually enter Acronym for EIR ${EIR_NUM}: "; read APP_NAME
else
    APP_NAME=$("${GREP}" "^${EIR_NUM}" "${EIR_TAB}" | "${CUT}" -d":" -f3)
    fi

## If the name is still not filled in, we will use a dummy name here
## this is really the last resort
if [[ -z "${APP_NAME}" ]]; then
    APP_NAME="ZZZZ"
fi

return "${RET_CODE:-0}"
}


get_request_num ()

{
## This function is used to get input from user on what SR number and the
## environment are for the storage request to be processed.
##

[ "${DEBUG}" = "1" ] && printf "%s\t%s\n" "${TIMESTAP} Function name : get_request_num" >> "${INFO_LOG}"

local counter="0"

while [[ "${counter}" -lt 3 && -z "${SR_NUM}" ]]
    do
        printf "%s" "Please enter Storage Request Number (i.e. 999999): "; read SR_NUM
        if [[ -z "${SR_NUM}" ]]; then
            counter=$((counter+1))
            printf "%s\n\n" "[Try ${counter}] Looks like the Storage Request Number is missing. Please try again."
            local RET_CODE="1"
        fi
    done

## If we return '1' from this function we do not have all the required info
## to continue with provisioning this request, at this point we should bail
## from the script and return '1'
return "${RET_CODE:-0}"
}

build_lun_arrays ()

{
### Build our LUN Array based on RAW input file - testing with /tmp/asm_setup_input.raw
### We need two ARRAYS one for FRA disks and one for DB disks

### Also we create a variable with the count of LUNs in the list
### which we will later use to compare against the count of verified LUNs
### those which we know have four individual paths
### 'TOTAL_LUN_COUNT' should contain a sum of LUNs in the two variables :
### 'DATA_LUN_COUNT' and 'FRA_LUN_COUNT'

LUN_RAW_INPUT_FILE="/sa/teams/storage/site-local/requests/${SR_NUM}/vmax-allocate.output.report"
if [[ ! -f "${LUN_RAW_INPUT_FILE}" ]]; then
    LUN_RAW_INPUT_FILE=""
    printf "%s\n" ""
    linesep
    loginfo "[CRITICAL] Unable to locate report file for SR ${SR_NUM}"
    linesep
    local counter="0"
    while [[ "${counter}" -lt 3 && -z "${LUN_RAW_INPUT_FILE}" ]];
        do
            printf "%s\n%s\n" "" "################/ Try [$(($counter+1))] Please provide Full Path to SR file /#################"
            printf "%s" ">>> "; read LUN_RAW_INPUT_FILE
            local counter=$(($counter+1))
        done
    if [[ "${counter}" -eq 3 && ! -f "${LUN_RAW_INPUT_FILE}" ]]; then
        local RET_CODE="1"
        printf "%s\n" \
        "################################################################################" \
        "#### CRITICAL: Unable to locate report file for SR ${SR_NUM}" \
        "################################################################################"
        return "${RET_CODE}"
    fi
fi

DATA_LUN_LIST=()
FRA_LUN_LIST=()
OCR_LUN_LIST=()

local ALL_LUNS=( $(/usr/bin/egrep "Data" "${LUN_RAW_INPUT_FILE}" | ${AWK} '{print $NF}' | /usr/bin/sort -u) )
## printf "%s\n" "${ALL_LUNS[@]}"

for line in "${ALL_LUNS[@]}"
    do
        printf "%s\n" "##############/ Please define Application for the following LUN /###############"
        cat "${LUN_RAW_INPUT_FILE}" | /usr/bin/egrep "${line}" | ${SED} -e "s/  */ /g"
        printf "%80s\n" " "|tr " " "#"
        ## We have to make sure that we reset the value of 'LUN_FUNCTION' for each LUN
        ## Normally, on our systems all LUNs begin with '3', which we have to prepend
        ## if we do not do this, LUN will not be provisioned correctly
        local line="3${line}"
        local LUN_FUNCTION=""
        local counter="0"
        while [[ "${counter}" -lt 3 && -z "${LUN_FUNCTION}" ]];
            do
                printf "%s" "Possible applications for the LUN are ([D]Data,[F]FRA,[O]OCR), select one: "; read LUN_FUNCTION
                printf "%s\n" ""
                local counter=$((counter+1))
                if [[ "${counter}" -eq 3 && -z "${LUN_FUNCTION}" ]]; then
                    printf "%s\n" "Unable to continue without defining application for LUN. Exiting."
                    local LUN_FUNCTION="q"
                fi

                    case "${LUN_FUNCTION}" in
                        D|d) ## If LUN is intended to be a Data LUN
                                DATA_LUN_LIST+=(${line})
                            ;;
                        F|f) ## If LUN is intended to be a Flash Recovery Archive LUN
                                FRA_LUN_LIST+=(${line})
                            ;;
                        O|o) ## If LUN is intended to be an OCR LUN
                                OCR_LUN_LIST+=(${line})
                            ;;

                        Q|q) ## User chose to quit
                                local RET_CODE="1"; return "${RET_CODE}"
                            ;;
                        *) ## Unknown option selected
                                printf "%s\n" "Try [$(($counter+1))] Selection not one of available options."
                                local LUN_FUNCTION=""
                            ;;
                        esac
            done
    done

## Individual ARRAY for DATA LUNs being provisioned to the cluster
DATA_LUN_LIST=( $(echo "${DATA_LUN_LIST[@]}" | tr '[:upper:]' '[:lower:]') )
## Individual ARRAY for FRA LUNs being provisioned to the cluster
FRA_LUN_LIST=( $(echo "${FRA_LUN_LIST[@]}" | tr '[:upper:]' '[:lower:]') )
## Individual ARRAY for OCR LUNs being provisioned to the cluster
OCR_LUN_LIST=( $(echo "${OCR_LUN_LIST[@]}" | tr '[:upper:]' '[:lower:]') )

## We determine a sum of 'DATA_LUN_COUNT' and 'FRA_LUN_COUNT', and substitute '0',
## if either variable is not present, which may be because only DATA or only
## FRA LUNs are being provisioned
TOTAL_LUNS=$(( ${#FRA_LUN_LIST[@]} + ${#DATA_LUN_LIST[@]} + ${#OCR_LUN_LIST[@]} ))
TOTAL_ORIG_LUNS="${#ALL_LUNS[@]}"


printf "%s\n" "################/ Summary of assigned Data, FRA and OCR LUNs /##################"
printf "%s %22s\n" "Total of DATA LUNs:" "[${#DATA_LUN_LIST[@]}]"
printf "%s %23s\n" "Total of FRA LUNs:" "[${#FRA_LUN_LIST[@]}]"
printf "%s %23s\n" "Total of OCR LUNs:" "[${#OCR_LUN_LIST[@]}]"
printf "%s %8s\n" "Number of unique LUNs from Input:" "[${TOTAL_ORIG_LUNS}]"
printf "%s %8s\n" "Number of LUNs to be Provisioned:" "[${TOTAL_LUNS}]"
printf "%80s\n" " "|tr " " "#"

## If we have a mismatch between input and output LUN count, we cannot continue
if [[ ! "${TOTAL_LUNS}" -eq "${TOTAL_ORIG_LUNS}" ]]; then
    printf "%s\n" "Number of input LUNs ${TOTAL_ORIG_LUNS} not equal to assigned LUNs ${TOTAL_LUNS}"
    local RET_CODE="1"
fi

return "${RET_CODE:-0}"
}

#check_if_LUN_partitioned ()

#{
### Block of code to confirm whether LUN is already partitioned and ask user
### for input of what action to take has been tested with partitioned and
### non-partitioned disk

#[ "${DEBUG}" = "1" ] && printf "%s\t%s\n" "${TIMESTAP} Function name : check_if_LUN_partitioned" >> "${INFO_LOG}"

#clear
#for EACH_LUN in ${FRA_LUN_LIST[@]} ${DATA_LUN_LIST[@]}

#do
#    if [[ "${force}" != "yes" ]]; then
#        ## This statement has to eval true, before message below is printed
#        if [[ $(parted -s "/dev/mapper/${EACH_LUN}" print | egrep "msdos|type\=83") != "" && $(sfdisk -l "/dev/mapper/${EACH_LUN}" | egrep -E "^\/dev/" | wc -l) = "4" ]]; then

#            printf "%s\n"
#    		printf "%s\n" "WARNING: ${EACH_LUN} is already partitioned."
#    		printf "\t%s" "Do you want to view the disk partitioning? [y/n] "
#    		read "ANS"

#            if [[ ${ANS} == "y" || ${ANS} == "Y" ]]; then
#                clear
#        		fdisk -l "/dev/mapper/${EACH_LUN}"
#        		printf "%s\n"
#    		fi

#            printf "%s\n"
#            printf "%s\n" "Do you want to continue to setup ASM on LUN ${EACH_LUN}"
#            printf "and wipe out its partitioning? [y/n] "
#            read "ANS"

#            [[ "${ANS}" =~ [Yy] ]] && printf "%s\n" "Your answer is : [YES]"
#            [[ "${ANS}" =~ [Nn] ]] && printf "%s\n" "Your answer is : [NO]"

#            ## If we choose not to proceed with partitioning an already partitioned
#            ## LUN, we are going to break out of the loop, and will
#            if  [[ ! "${ANS}" =~ [Yy] ]]; then
#                    RET_CODE=1
#                    break
#                else
#                    RET_CODE=0
#            fi
#        fi
#    fi
#done
#return "${RET_CODE}"
#}


validate_lun_paths ()

{
local DMSETUP=/sbin/dmsetup
local EACH_LUN="$1"

### We read the multipath output file and extract devices for each multipath
### target in this format '0:0:0:0' expecting to get a list of 4 devices
### These are wrapped into one array, and for each item we validate that the
### device is functional

### Also we create a variable with the count of LUNs in the list
### which we will later use to compare against the count of verified LUNs
### those which we know have four individual paths
### 'TOTAL_LUN_COUNT' should contain a sum of LUNs in the two variables :
### 'DATA_LUN_COUNT' and 'FRA_LUN_COUNT'

[[ "${DEBUG}" -ge "1" ]] && printf "%s\t%s\n" "${TIMESTAP} Function name : validate_lun_paths" >> "${INFO_LOG}"

local counter="0"  ## We start out at zero, and expect to match the number with FRA_LUN_COUNT
# clear

loginfo "DEV[${DEV_COUNTER}]=${EACH_LUN}"
linesep

## Validate that 'dmsetup' is able to see the Multipath Device
## this does not mean that the block device under '/dev/mapper' exists,
## and we check for its existance also

"${DMSETUP}" info "${EACH_LUN}" &> /dev/null; local RET_CODE="$?"
    if [[ "${RET_CODE}" -ne "0" ]]; then
        loginfo "[CRITICAL] Device not a VALID Device-Mapper Block Device."
        loginfo "Failed: ${DMSETUP} info ${EACH_LUN}"
        local RET_CODE="1"; break
    elif
        ## Validation of Device-mapper
        [[ ! -b "/dev/mapper/${EACH_LUN}" ]]; then
        loginfo "[CRITICAL] DEV[${counter}] missing Device-Mapper Block Device. [Check Device!]"
        local RET_CODE="1"; break
    else
        loginfo "[SUCCESS] LUN has a VALID Device-Mapper Device."
        local RET_CODE="0"
    fi

printf "%s\n" "${SEP_LINE}"

DEV_COUNTER=$((DEV_COUNTER+1))

## If we fail our validation tests above, there is no sense to continue and waste any more time.
[[ "${RET_CODE}" -eq "1" ]] && return 1

## Here we create an ARRAY 'SINGLE_PATH_ARRAY', which will contain four paths for each LUN
## Our goal is to make sure that we have four paths to each LUN, in a running
## state, and if not, we likely need to stop and do some manual troubleshooting

SINGLE_PATH_ARRAY=($(grep -A7 "${EACH_LUN}" "${MPINFO}" | egrep --regexp="([0-9]{0,2}:[0-9]{0,2})" | sed -e "s/[\_]/ /g" -e "s/^  *//g" | cut -d" " -f1))
[[ "${DEBUG}" -ge "1" ]] && printf "%s\n" "Multipath registered ${#SINGLE_PATH_ARRAY[@]} paths to device /dev/mapper/${EACH_LUN}." >> "${INFO_LOG}"

## Create a one-line list of paths for a device
    list_paths ()
    {
    local counter="0"
        for i in "${SINGLE_PATH_ARRAY[@]}"
            do printf "%s" "[${counter}] [${i}] "
            local counter=$((counter+1))
        done
    }

printf "%s\n" "########################/ Validating Block Device Path /########################"
linesep

loginfo "$(list_paths)"

## First Check :: confirm that SINGLE_PATH_ARRAY has four elements in it
## If it does, we assume that we have the right number of paths to proceed
    if [[ "${#SINGLE_PATH_ARRAY[@]}" -eq "4" ]]; then
        loginfo "[SUCCESS] Confirmed 4 available paths to Device."

        ## Second Check :: Make sure that each path 'sd' is in a running state
        ## If not, we should not continue because paths may be stale
        for P in "${SINGLE_PATH_ARRAY[@]}"
            do
                local STATE=$(cat "/sys/bus/scsi/devices/${P}/state")

                if [[ ! "${STATE}" = "running" ]]; then ## Should be in a running state
                    printf "%s\n" "${SEP_LINE}"
                    loginfo "[FAILURE] DEV[${counter}], PATH ${P} is not in a Running State. [Check Device!]"
                    printf "%s\n" "${SEP_LINE}"
                    local RET_CODE="1"
                    break
                else
                    loginfo "[SUCCESS] Sub-path [${P}] is in a Running State."
                    local counter=$((counter + 1))
                    local RET_CODE="0"
                fi
            done
    else
        loginfo "Expected number of paths to LUN ${EACH_LUN} must equal to 4."
        local RET_CODE=1
        break
    fi
linesep

if [[ ! "${RET_CODE}" -eq "0" ]]; then
    printf "%s\n" "[FAILURE] Unable to Provision this LUN correctly." \
    "If more than one LUN is to be provisioned, moving on onto next LUN."
    sleep 3
fi

return "${RET_CODE:-0}"
}

provision_lun ()

{
## Function will use variables set by earlier functions
## along with two positional arguments passed to function by main script
## to build argument list and pass them to the main code

local EACH_LUN="$1"
local ASM_FUNC="$2"

printf "%s\n" "ARGS which we will pass to the main script :" \
"--device=${EACH_LUN}" \
"--asm-function=${ASM_FUNC}" \
"--request-number=${SR_NUM}" \
"--environment=${SR_ENV}" \
"--eir-number=${EIR_NUM}" \
"--app-name=${APP_NAME}" \
"--provision"
linesep

local RET_CODE="$?"
return "${RET_CODE:-0}"
}



###############################################################################
### Step 3 : Begin Execution of Main part of the script
###############################################################################

## If we passed the update option to the script, we are only going to scan ASM
## to update node's ASM configuration, assming LUNs were already provisioned
## on another node in the cluster
printf "%s\n" "Please, be patient... Gathering information from multipath."
"${MPATH_CMD}" -v2  >> "${INFO_LOG}"
"${MPATH_CMD}" -ll > "${MPINFO}"

## We need to gather information about the 'Storage Request' number, and purpose
## for each LUN in the report file
get_request_num || exit 1
get_env_eir || exit 1
build_lun_arrays || exit 1

### This is where we execute our verification function to confirm that
### we have correct number of paths for each LUN, if we do not,
### we are going to exit at this point to allow for manual troubleshooting

for EACH_LUN in "${DATA_LUN_LIST[@]}"
    do
        validate_lun_paths "${EACH_LUN}" && provision_lun "${EACH_LUN}" "DATA"
    done

for EACH_LUN in "${FRA_LUN_LIST[@]}"
    do
        validate_lun_paths "${EACH_LUN}" && provision_lun "${EACH_LUN}" "FRA"
    done

for EACH_LUN in "${OCR_LUN_LIST[@]}"
    do
        validate_lun_paths "${EACH_LUN}" && provision_lun "${EACH_LUN}" "OCR"
    done


#RET_CODE=$?; [[ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

#[ "${DEBUG}" = "1" ] && printf "%s\n" "Total LUN Count is ${TOTAL_LUN_COUNT} Counter is at ${COUNTER}" >> "${INFO_LOG}"

### We expect that COUNTER from above will match TOTAL_LUN_COUNT
#if [[ "${TOTAL_LUN_COUNT}"  != "${COUNTER}" ]]; then
#    printf "%s\n" "Some of the LUNs being Provisioned do not have correct number of paths. Cannot Continue..."

#    filecleanup  ## We make sure that any files that we create are removed upon exit
#    exit "${RET_CODE}"
#else
#    printf "%s\n" "All LUNs being Provisioned have correct number of paths. Continuing..."
#    sleep 2
#fi

### This is where we execute our partition verification function to check
### that LUNs are not already partitioned, which may mean that they are
### already in use by the system

#check_if_LUN_partitioned; RET_CODE=$?
#[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : check_if_LUN_partitioned" "LUN MBR Check Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"

#    if [[ "${RET_CODE}" != "0" ]]; then
#            clear
#            printf "%s\n\n" "One or more LUNs already partitioned. You chose not to continue with re-partitioning."
#            printf "%s\n" "###############################################################################"
#            printf "%s\n" "ASM Provisioning of the following LUNs was cancelled...:"
#            printf "\t%s\n" "${FRA_LUN_LIST[@]}" "${DATA_LUN_LIST[@]}"
#            printf "%s\n\n" "###############################################################################"
#            printf "%s\n" "" "Please, re-check the LUN(s), and adjust input file, if LUN(s) should be excluded."

#            filecleanup  ## We make sure that any files that we create are removed upon exit
#            exit "${RET_CODE}"
#        else
#            printf "%s\n" "All LUNs were verified as OK to re-partition. Continuing..."
#            sleep 2
#    fi

###############################################################################
### Step 2b : If all checks succeed we begin to partition LUNs
###############################################################################

### This is where we execute our partitioning function used to create one
### partition covering the whole disk

#partition_each_LUN; RET_CODE=$?
#[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : partition_each_LUN" "LUN Partitioning Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"

#if [[ "${RET_CODE}" != "0" ]]; then
#        clear
#        printf "%s\n\n" "Error was encountered and you chose to abort."
#        printf "%s\n" "###############################################################################"
#        printf "%s\n" "Please, manually re-check LUNs with which errors were encountered."
#        printf "%s\n" "###############################################################################"
#        filecleanup  ## We make sure that any files that we create are removed upon exit
#        exit "${RET_CODE}"
#    else
#        printf "%s\n" "All LUNs were partitioned. Continuing..."
#        # sleep 15
#fi

#device_map_create_each_LUN; RET_CODE=$?; [[ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

#if [[ "${RET_CODE}" != "0" ]]; then
#        clear
#        printf "%s\n" "###############################################################################"
#        printf "%s\n" "WARNING: Created DM Devices and Symlinks, but some errors were encountered."
#        printf "%s\n" "###############################################################################"
#    else
#        printf "%s\n" "###############################################################################"
#        printf "%s\n" "SUCCESS: Created DM Devices and Symlinks without any errors."
#        printf "%s\n" "###############################################################################"
#fi

#[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : device_map_create_each_LUN" "DM and Symlink Creation Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"

###############################################################################
### Step 2c : Last step is to add LUNs to ASM for DBSS
###############################################################################

#add_LUN_to_ASM; RET_CODE=$?; [[ ! "${RET_CODE}" = "0" ]] && WARN_ON_EXIT=Y

#if [[ "${RET_CODE}" != "0" ]]; then
#        clear
#        printf "%s\n" "###############################################################################"
#        printf "%s\n" "WARNING: At least one LUN was not added to Oracle ASM."
#        printf "%s\n" "###############################################################################"
#    else
#        printf "%s\n" "###############################################################################"
#        printf "%s\n" "SUCCESS: Configured all LUNs under Oracle ASM."
#        printf "%s\n" "###############################################################################"
#fi

#[ "${DEBUG}" = "1" ] && printf "%s\n" "Function Name : add_LUN_to_ASM" "LUN ASM Config Function Return Code: ${RET_CODE}" >> "${INFO_LOG}"


# List out ASMLib disks
# echo "Listing out disks setup into ASMLib:"
# /etc/init.d/oracleasm listdisks
#
## Function defined at the beginning of the script
filecleanup

printf "%s\n" "Completed setup of New LUNs..."

if [[ "${WARN_ON_EXIT}" = "Y" ]]; then
        printf "%s\n" " However some issues were encountered."
        exit 1
    else
        exit 0
fi

