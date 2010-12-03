#!/bin/bash
##: Title       : Generic loop script to create multiple instances of a process
##: Date Rel    : 11/30/2010
##: Date Upd    : 12/02/2010
##: Author      : "Sam Zaydel" <sam.zaydel@usps.gov>
##: Version     : 0.1.0
##: Release     : Beta
##: Description : Script used to spin-up a number of instances of same process
##:             : in an infinite loop, as long as the control file is in place
##: Options     : 
##: Filename    : ps-test.bash
###############################################################################
### NOTES: ####################################################################
###############################################################################
# Kinman recommended sending processes to background as an option, instead of
# a requirement, and 'SEND_TO_BG' flag was added for this reason.
# Date/Time are not written to the head of the logs when they are created,
# this should be added.
###############################################################################
NUMBER_OF_PROCS=10
DEBUG=0
DELAY_P=2
WORK_DIR=/var/tmp
## Provide full path to command and define options in CMD_OPTS
CMD_TO_EXEC=/usr/bin/ps
CMD_OPTS=-ef
CMD_WITH_OPTS="${CMD_TO_EXEC} ${CMD_OPTS}"
CMD_S=$(basename "${CMD_TO_EXEC}")
## Without the control file, script will not execute and exit with RC1
CONTROL_FILE="${WORK_DIR}/ps_test_start.flag"
## Should the command being iterated be executed in the background?
## Set the flag to yes, in order to background the command
SEND_TO_BG="n"

    if [[ "${SEND_TO_BG}" = "y" ]]; then
        ## Send process to background if enabled
        BG_FLAG="&"
    else
        BG_FLAG=""
    fi

    if [[ ! -f "${CONTROL_FILE}" ]]
        then
            printf "%s\n" "Control File ${CONTROL_FILE} is missing. Refuse to run without it."
            exit 1
    else
        while [[ -f "${CONTROL_FILE}" ]]
            do
                COUNT="${NUMBER_OF_PROCS}"
                while [[ "${COUNT}" -gt 0 ]]
                    do
                        ## (1) Create Log files to capture 'ps' and error output
                        OUTPUT_LOG="${WORK_DIR}/${CMD_S}-test-${COUNT}.log"
                        ERR_LOG="${WORK_DIR}/${CMD_S}-test-${COUNT}-err.log"
                        
                        ## (2) Actually execute process in a loop structure
                        [[ "${DEBUG}" -ge "1" ]] && echo "Counter is currently: ${COUNT}"
                        
                        ## Use lines below for any debugging, and make sure the
                        ## DEBUG variable is set to 1 or higher
                        [[ "${DEBUG}" -ge "1" ]] && echo "Do something here" # Normally not used
                        [[ "${DEBUG}" -ge "1" ]] && echo "Do something here" # Normally not used
                        ## If debug is enabled 'ps' will not run
                        [[ "${DEBUG}" -ge "1" ]] || ${CMD_WITH_OPTS} > "${OUTPUT_LOG}" 2>"${ERR_LOG}" ${BG_FLAG}

                        ## (3) Establish return code from above, and if not '0'
                        ## then we stop, and remove our control file, without which script stops
                        RET_CODE=$?
                        if [[ "${RET_CODE}" -ne "0" ]]
                            then
                                COUNT="0"
                                rm "${CONTROL_FILE}"
                            else 
                                COUNT=$((${COUNT} - 1))
                        fi
                    
                    done
                sleep "${DELAY_P}"
            done
    fi
exit "${RET_CODE:-0}"