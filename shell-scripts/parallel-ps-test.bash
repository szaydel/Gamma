#!/bin/bash
NUMBER_OF_PROCS=10
DEBUG=0
DELAY_P=2
WORK_DIR=/var/tmp
CMD_TO_EXEC=/usr/bin/ps
CMD_OPTS=-ef
CMD_WITH_OPTS="${CMD_TO_EXEC} ${CMD_OPTS}"
CMD_S=$(basename "${CMD_TO_EXEC}")
CONTROL_FILE="${WORK_DIR}/ps_test_start.flag"


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
                        OUTPUT_LOG="${WORK_DIR}/${CMD_S}-${COUNT}.log"
                        ERR_LOG="${WORK_DIR}/${CMD_S}-${COUNT}-err.log"
                        
                        ## (2) Actually execute process in a loop structure
                        [[ "${DEBUG}" -ge "1" ]] && echo "Counter is currently: ${COUNT}"
                        ## If debug is enabled 'ps' will not run
                        printf "%s\n" "STDOUT Log: ${OUTPUT_LOG}"
                        [[ "${DEBUG}" -ge "1" ]] || ${CMD_WITH_OPTS} > "${OUTPUT_LOG}" 2>"${ERR_LOG}" &
                        
                        ## (3) Establish return code from above, and if not '0'
                        ## then we stop, and remove our control file, without which script stops
                        RET_CODE = $?
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