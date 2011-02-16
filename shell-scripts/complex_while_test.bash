#!/bin/bash
DEBUG=0
WORK_DIR=/tmp
CONTROL_FILE="${WORK_DIR}/ps_test_start.flag"

while [[ -f "${CONTROL_FILE}" ]]
    do
        echo "Good"
        sleep 2
    done