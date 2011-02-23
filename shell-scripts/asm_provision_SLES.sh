#!/bin/bash ####################################################################
##: Title       : USPS Automatic Storage Management Provisioning Tool ##########
##: Date Rel    : 08/01/2008 ###################################################
##: Date Upd    : 02/23/2011 ###################################################
##: Author      : "Sam Zaydel" <sam.zaydel@usps.gov> ###########################
##: Version     : 0.2.2 ########################################################
##: Release     : Beta #########################################################
##: Description : ASM Storage Provisioning script improved over original #######
##: Options     : -d -hH -o -p -s -t -v ########################################
##: Filename    : asm_provision_SLES.sh ########################################
################################################################################
### NOTES: #####################################################################
################################################################################
## This script was converted from a ksh version and was fundamentally changed ##
## in order to streamline the process, and improve disk verification ###########
################################################################################
### Index/Description of Functions included in Library #########################
################################################################################
### Revisions: #################################################################
################################################################################
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
## : 02/07/2011 - Goal is to modularize the script using functions, this way it
## : will be easier to modify and enhance the script in the future by folks
## : other than the original developer
## : 02/08/2011 - Cleaned-up redundant code, removed commented-out sections
## : 02/15/2011 - Improved getopts section and made it relevant to the script
## : itself, by removing the scan-only and adding args like test and debug
################################################################################
################# Major objectives and expected behavior #######################
################################################################################
## ****** IMPORTANT ****** #####################################################
## 1. Multipath "MUST" show four paths for each LUN being provisioned, this
## script will fail if any one LUN does not have four paths visible to the OS
## 2. We also expect that each LUN will have a block device under /dev/mapper
## this is critical, because main provisioning program expects that it will find
## devices under /dev/mapper, and performs actions using the /dev/mapper pathing
## 3. LUNs could contain letters, we need to make sure that ALL input from the
## input file is converted to lowercase, which occrs when we build individual
## ARRAYs for each type of a LUN, at the moment (DATA, FRA, OCR)
## 4. We really want to make sure that we collect as much information as we can
## and as such EIR and the App Name are needed, normally EIR # is enough to get
## the name of the application dynamically
## 5. Create variables for everything to make script more easily tuned, and more
## portable, however at the moment it should only be used on a SLES system
## 6. We need to try and keep everything wrapped into individual functions,
## this way as we make this automation more robust it will remain easy to update
## and maintain it
################################################################################

################################################################################
### Step 1 : Define Variables and Functions used throughout the script #########
################################################################################

################################################################################
### Step 1a : Initialization functions required to setup script functionality ##
################################################################################

usage()

{
	printf "%s\n" "" "[$(basename $0)] - Wrapper script used to setup LUNs for use with Oracle ASM" ""
	printf "%s\n" "Usage:"
    printf "\t%s\n" "Typical Usage: Run ./$(basename $0) -argument"
	## printf "\t%s\n" "[-h] Will return this help screen" "[-f] Will 'force' setup of previously partitioned LUNs"
	printf "\t%s\n" "[-p] Start provisioning and ASM setup of new LUNs" \
	"[-d{0-2}] Set debugging level, allowable from 0 to 2" \
	"[-t] Set mode to testing - this is Work-in-Progress" \
	"[-v] Version of the script being run"
	## "" Future options to be added here
	## "" Future options to be added here
	printf "%s\n" "Reminder:"
	printf "\t%s\n" "Do not forget to do a LUN scan prior to using [-p] argument" \
	"Script $(basename $0) assumes:" ""\
	"a) HBAs have already been re-scanned, and new device(s) picked-up" \
	"b) LUN(s) to be provisioned is/are accessible by $(hostname)" \
	"c) Device-Mapper and Multipath are aware of the LUN(s)"
}

if [[ "$#" -lt 1 ]]; then
    printf "%s\n" "" "ERROR: At least one argument is reqiured to continue."
    usage
    exit 192
fi

TEST_MODE="N"
force=""
## By default, we want to make sure that the DEBUG level is set to '0'
DEBUG="0"
VER=0.2.2

## Set the Options index to 1
OPTIND=1
OPT_COUNTER=0
## If both of these are empty, we cannot continue
PROVISION=""
SCAN_ONLY=""

while getopts d:fpstvhH ARGS
do
	case "${ARGS}" in

        D|d)
            if [[ ! "${OPTARG}" == [0-2] ]]; then
                printf "%s\n" "ERROR: Debug Level is from 0 to 2"
                DEBUG="0"
            else
                DEBUG="${OPTARG}"
            fi
            OPT_COUNTER=$((OPT_COUNTER + 1))
			;;

		F|f)
			force="yes"
			OPT_COUNTER=$((OPT_COUNTER + 1))
			;;

        P|p)
            PROVISION="yes"
            ;;

        S|s)
            SCAN_ONLY="yes"
            OPT_COUNTER=$((OPT_COUNTER + 1))
			;;

		## If set to 'Y', script is in 'test mode', which should only be used during
        ## development and validation of modifications
		T|t)
            TEST_MODE="Y"
            OPT_COUNTER=$((OPT_COUNTER + 1))
			;;

		V|v)
            printf "%s\n" "$(basename $0) - Version: ${VER}"
            OPT_COUNTER=$((OPT_COUNTER + 1))
            exit 0
			;;

        H|h|*)
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
        echo Options Index is at: "${OPTIND}"
        echo Optionional Args Count is at: "${OPT_COUNTER}"
        echo Number of Args passed: "$#"
        echo Number of required Args passed:  "${REQ_PARAMS_COUNT}"
        ## exit 0
    fi

################################################################################
### Step 1b : Variables used globally in the script ############################
################################################################################

CAT=/bin/cat
CUT=/usr/bin/cut
TR=/usr/bin/tr
AWK=/usr/bin/awk
SED=/usr/bin/sed
SORT=/usr/bin/sort
GREP=/usr/bin/grep
EGREP=/usr/bin/egrep
MPATH_CMD=/sbin/multipath
EXEC_DIR=$(dirname $0)
DMSETUP=/sbin/dmsetup
DUTIL_CMD="${EXEC_DIR}/diskutil"
DATE=$(date "+%Y%m%d")
TIMESTAMP=$(date "+%T")
PID=$$
INFO_LOG="/tmp/setupASM-INFO-${DATE}.${PID}"
ERR_LOG="/tmp/setupASM-ERR-${DATE}.${PID}"
MPINFO="/tmp/multipath.${PID}"
SR_RPTS_DIR=/sa/teams/storage/site-local/completion-reports
SERVICE_DIR=/sa/info/services
EIR_TAB="${SERVICE_DIR}/etc/eir.tab"
DEV_COUNTER="0"
APP_NAME=""
LUN_RAW_INPUT_FILE=""
SR_NUM=""
SR_ENV=""
EIR_NUM=""
ALL_LUNS=()
DATA_LUN_LIST=()
FRA_LUN_LIST=()
OCR_LUN_LIST=()

################################################################################
### Step 1c : Variables used globally in the script ############################
################################################################################

## Only one argument should ever be required, per execution,
## as such, if more than one required argument has been specified,
## it is a good chance that conflicting instructions are being provided
## We do not want to allow for more than '1' required argument

if [[ "${REQ_PARAMS_COUNT}" -ge "2" ]]; then
	printf "%s\n" "ERROR: Conflicting arguments were selected."
	usage
	exit 192
elif [[ "${REQ_PARAMS_COUNT}" -eq "0" ]]; then
	printf "%s\n" "ERROR: At least one non-optional argument is required."
	usage
	exit 192

fi

if [[ ! "${PROVISION}" = "yes" ]]; then
    ## Looks like we are done here, since we do not
    ## need to do anything further, we will exit at this point
    exit 0
fi

[[ "${DEBUG}" -ge "2" ]] && sleep 3600 ## Added for troubleshooting purposes

################################################################################
### Step 2a : Functions called later throughout the script #####################
################################################################################
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

filecleanup ()

{
################################################################################
## We need to be keep our system clean, after we leave this script #############
################################################################################
## Any temporary files created should be removed once we are done
## log files remain untouched
## Use variables defined above instead of actual filenames, this
## if filenames ever change, we just need to worry about changing one line
printf "%s\n" "Cleaning up temporary files ..."
rm -f "${MPINFO}"
}

early_exit ()
{
################################################################################
## We may have to leave the script early at times ##############################
################################################################################
## If for any reason one of the functions returns a non-zero return code,
## we will call an early exit, during which we still want to make sure to
## clean-up temporary files and such

    filecleanup
    exit 1
}
get_env_eir ()

{
################################################################################
## We need to collect Environment and Application 'EIR' ########################
################################################################################
#SR_NUM=""
SR_ENV=""
local counter="0"

while [[ -z "${EIR_NUM}" ]]
    do
        linesep
        printf "%s" "Please enter Application EIR Number: "; read EIR_NUM

        ## To make sure that our EIR number is indeed 4 digits long, we create
        ## a variable which basically strips any alpha characters from the
        ## EIR_NUM variable, and we later test this 'EIR_NOALPHA' for its
        ## length, which should be '4' digits
        local EIR_NOALPHA=$(printf "${EIR_NUM}" | ${EGREP} -v "[[:alpha:]]")

        ## If the field was left blank, prompt user
        if [[ -z "${EIR_NUM}" ]]; then
            printf "%s\n" "[ERROR] EIR Number cannot remain blank. Try Again."
            EIR_NUM=""

        ## If the field is less or more than 4 characters, prompt user
        elif [[ "${#EIR_NOALPHA}" -ne "4" ]]; then
            if [[ "${#EIR_NOALPHA}" -gt "4" ]]; then
                printf "%s\n" "[ERROR] EIR Number should not be longer than 4 digits. Try Again."
            else
                printf "%s\n" "[ERROR] EIR Number should not be shorter than 4 digits. Try Again."
            fi
            EIR_NUM=""
        ## If EIR not a valid number, prompt user
        elif [[ ! "${EIR_NUM}" -eq "${EIR_NUM}" ]]; then
            printf "%s\n" "[ERROR] EIR Number does not appear to be valid. Try Again."
            EIR_NUM=""
        fi
    done

## We have four attempts to get the 'SR_ENV' variable populated, and after four
## attempts we will basically
while [[ -z "${SR_ENV}" ]]
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

## We need to validate whether or not we can read the 'EIR_TAB' file, and if we
## cannot, we basically have to prompt for the APP name, since we will not be
## able to derive the 'APP_NAME' by pulling it out of the 'EIR_TAB' file

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
################################################################################
## This function is used to get input from user on what SR number and ##########
## what the environment is for the storage request to be processed #############
################################################################################

local SR_NUM_LEN="7" ## Length of 'Storage Request' number, must be 7

[ "${DEBUG}" = "1" ] && printf "%s\t%s\n" "${TIMESTAP} Function name : get_request_num" >> "${INFO_LOG}"

local counter="0"

while [[ "${counter}" -lt 3 && -z "${SR_NUM}" ]]
    do
        printf "%s" "Please enter Storage Request Number (i.e. 9999): "; read SR_NUM
        if [[ -z "${SR_NUM}" ]]; then
            counter=$((counter+1))
            printf "%s\n\n" "[Try ${counter}] Looks like the Storage Request Number is missing. Please try again."
            local RET_CODE="1"
        fi
    done

## If 'SR_NUM' variable is set, we need to make sure that the length is 7 digits
if [[ ! -z "${SR_NUM}" ]]; then
    ## If length os 'SR_NUM' variable is not seven digits long, we pad it.

    if [[ "${#SR_NUM}" -ne "${SR_NUM_LEN}" ]]; then
        local OFFSET=$((${SR_NUM_LEN}-${#SR_NUM}))
        ## We need to re-write 'SR_NUM' variable with the padded zeros
        SR_NUM=$(printf "%${OFFSET}s" | "${TR}" ' ' '0')${SR_NUM}
    fi
fi



## If we return '1' from this function we do not have all the required info
## to continue with provisioning this request, at this point we should bail
## from the script and return '1'
return "${RET_CODE:-0}"
}

build_lun_arrays ()

{
################################################################################
## Build our LUN Array based on input file generated by the storage team #######
## Multiple storage request files are possible, as such we have to make sure ###
## that we can work with one or more than one files as input ###################
################################################################################

## When in test mode we will use local dir /tmp while searching for files
[[ "${TEST_MODE}" = "Y" ]] && SR_RPTS_DIR=/tmp/completion-reports

local GREP_OPTIONS="--color=none --no-filename"

## This is where we validate whether or not the report directory is present and
## if it is present whether or not it contains any data
if [[ -d "${SR_RPTS_DIR}/${SR_NUM}" && ! -z $(ls -A "${SR_RPTS_DIR}/${SR_NUM}") ]]; then
        # LUN_RAW_INPUT_FILE="${SR_RPTS_DIR}/${SR_NUM}/*"
        LUN_RAW_INPUT_FILE=($(ls ${SR_RPTS_DIR}/${SR_NUM}/*))
    else
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
        if [[ "${counter}" -eq 3 && -z "${LUN_RAW_INPUT_FILE}" ]]; then
            local RET_CODE="1"
            printf "%s\n" \
            "################################################################################" \
            "[CRITICAL] Unable to locate report file for SR ${SR_NUM} ########################" \
            "################################################################################"
            return "${RET_CODE}"
        fi
fi

## Read through list of files in the 'LUN_RAW_INPUT_FILE' array, and build
## another array called 'ALL_LUNS', which will contain list of each LUN, which
## is normally found in the last column of the Storage Report as supplied by the
## Storage Team - Jon Metzger was a master-mind behind developing the report
## files which this information is being extracted from

for line in "${LUN_RAW_INPUT_FILE[@]}"
    do
        ALL_LUNS+=( $(${EGREP} -v '^$|^#' ${line} | ${AWK} '{print $NF}' | ${SORT} -u) )
    done

## Now we want to build a separate array for each type of a LUN that we are
## provisioning, because depending upon the purpose for LUN, arguments passed
## to the main program will be different
## We expect to have at least three types of LUNs, and this could change, in
## which case it will be easy enough to expand this section

for line in "${ALL_LUNS[@]}"
    do
        printf "%s\n" "##############/ Please define Application for the following LUN /###############"
        ${CAT} "${LUN_RAW_INPUT_FILE[@]}" | ${EGREP} "${line}" | ${SED} -e "s/  */ /g"
        printf "%80s\n" " "|tr " " "#"
        ## We have to make sure that we reset the value of 'LUN_FUNCTION' for each LUN
        ## Normally, on our systems all LUNs begin with '3', which we have to prepend
        ## if we do not do this, LUN will not be provisioned correctly
        local line="3${line}"
        local LUN_FUNCTION=""
        local counter="0"
        ## If we need to include new purposes for LUNs which will require a different
        ## argument to be passed to the main program, all we have to do here is
        ## modify the 'printf' line that prompts user for input, and add another case
        ## statement 'case "${LUN_FUNCTION}" in'
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

## Just in case we have some mixed-case scenario, we want to make sure that any
## letters are transformed from :upper: to :lower: case, while not likely it is
## easy enough to account for this small possibility

## Individual ARRAY for DATA LUNs being provisioned to the cluster
DATA_LUN_LIST=( $(echo "${DATA_LUN_LIST[@]}" | ${TR} '[:upper:]' '[:lower:]') )
## Individual ARRAY for FRA LUNs being provisioned to the cluster
FRA_LUN_LIST=( $(echo "${FRA_LUN_LIST[@]}" | ${TR} '[:upper:]' '[:lower:]') )
## Individual ARRAY for OCR LUNs being provisioned to the cluster
OCR_LUN_LIST=( $(echo "${OCR_LUN_LIST[@]}" | ${TR} '[:upper:]' '[:lower:]') )

## We do a quick calculation here of number of LUNs to be provisioned
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
    linesep
    printf "%s\n" "[CRITICAL] Number of input LUNs ${TOTAL_ORIG_LUNS} not equal to assigned LUNs ${TOTAL_LUNS}"
    linesep
    local RET_CODE="1"
fi

return "${RET_CODE:-0}"
}


validate_lun_paths ()

{
################################################################################
## We read the multipath output file and extract devices for each multipath ####
## target in this format '0:0:0:0' expecting to get a list of 4 devices ########
## We want to be very conservative in this function and choose to run ##########
## instead of fight, because we believe that it is critical to have 4 live #####
## and active paths, otherwise there may some greater issuses that we are not ##
## really aware of #############################################################
## These are wrapped into one array, and for each item we validate that the ####
## device is functional, we are also expecting that multipath sees the device ##
## Our main goal in this function is to make sure that we have four paths ######
## existing for every LUN, since we normally should have four paths to #########
## each LUN both in Production and non-Production environments #################
################################################################################

## Only one argument should be passed to this function at a time, and should be
## each LUN from the list of LUNs that we built earlier

local EACH_LUN="$1"

## If we are testing this, 'TEST_MODE' flag will be set to 'Y' and we just
## leave this function returning zero

[[ "${TEST_MODE}" = "Y" ]] && return "0"

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
        ## Validation of Device-mapper block device, we have to make sure that
        ## block device '/dev/mapper/36000...' actually exists
        [[ ! -b "/dev/mapper/${EACH_LUN}" ]]; then
        loginfo "[CRITICAL] DEV[${counter}] missing Device-Mapper Block Device. [Check Device!]"
        local RET_CODE="1"; break
    else
        loginfo "[SUCCESS] LUN has a VALID Device-Mapper Device."
        local RET_CODE="0"
    fi

printf "%s\n" "${SEP_LINE}"

DEV_COUNTER=$((DEV_COUNTER+1))

## If we fail our validation tests above,
## there is no sense to continue and waste any more time
[[ "${RET_CODE}" -eq "1" ]] && return 1

## Here we create an ARRAY 'SINGLE_PATH_ARRAY', which will contain four paths for each LUN
## Our goal is to make sure that we have four paths to each LUN, in a running
## state, and if not, we likely need to stop and do some manual troubleshooting

SINGLE_PATH_ARRAY=($(${GREP} -A7 "${EACH_LUN}" "${MPINFO}" | ${EGREP} --regexp="([0-9]{0,2}:[0-9]{0,2})" | ${SED} -e "s/[\_]/ /g" -e "s/^  *//g" | cut -d" " -f1))
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
        ## If not, we should not continue because paths may be stale, broken,
        ## or disable for any number of reasons
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
################################################################################
## Function will use variables set by earlier functions ########################
## along with two positional arguments passed to function by main script #######
## to build argument list and pass these arguments to the main diskutil ########
## program, which will take care of the rest of the provisioning ###############
################################################################################
## ****** IMPORTANT ****** #####################################################
## Most of the changes in this script should occur in this function, because ###
## the script is really a wrapper for the main program and most of what it #####
## does has to do with gathering required information from various sources #####
## and structures that information in a form which is then passed to the main ##
## automation, which takes care of the formatting, labeling, etc ###############
################################################################################

local EACH_LUN="$1"
local ASM_FUNC="$2"

## If we are only testing, then we do not actually want to run the provisioning
## command, as such, we simply return what will be passed to the 'diskutil'
## program and return from this function with a return code '0'

if [[ "${TEST_MODE}" = "Y" ]]; then

    printf "%s\n" "ARGS which we will pass to the main script :" \
    "--disk=/dev/mapper/${EACH_LUN}" \
    "--type=${ASM_FUNC}" \
    "--request=${SR_NUM}" \
    "--environment=${SR_ENV}" \
    "--eir=${EIR_NUM}" \
    "--app=${APP_NAME}" \
    "--setup"
    return 0
else
    ## Uncomment when ready to begin using main program
    ${DUTIL_CMD} --setup \
    "--disk=/dev/mapper/${EACH_LUN}" \
    "--type=${ASM_FUNC}" \
    "--request=${SR_NUM}" \
    "--environment=${SR_ENV}" \
    "--eir=${EIR_NUM}" \
    "--app=${APP_NAME}"
    linesep

local RET_CODE="$?"
return "${RET_CODE:-0}"
fi


}

################################################################################
### Step 3 : Begin Execution of Main part of the script ########################
################################################################################

## If we passed the update option to the script, we are only going to scan ASM
## to update node's ASM configuration, assming LUNs were already provisioned
## on another node in the cluster
printf "%s\n" "Please, be patient... Gathering information from multipath."
"${MPATH_CMD}" -v2  >> "${INFO_LOG}"
"${MPATH_CMD}" -ll > "${MPINFO}"

## We need to gather information about the 'Storage Request' number, and purpose
## for each LUN in the report file
get_request_num || early_exit
get_env_eir || early_exit
build_lun_arrays || early_exit

## This is where we execute our verification function to confirm that
## we have correct number of paths for each LUN, if we do not,
## we are going to exit at this point to allow for manual troubleshooting

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

filecleanup

linesep
printf "%s\n" "Completed setup of New LUNs..."

if [[ "${WARN_ON_EXIT}" = "Y" ]]; then
    printf "%s\n" " However some issues were encountered."
    linesep
    exit 1
else
    linesep
    exit 0
fi

