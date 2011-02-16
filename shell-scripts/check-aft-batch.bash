#!/bin/bash
DIV=$(printf "%80s\n" | tr ' ' '+')
GREP_OPTIONS="-r -E --color=never"
HCS_INFO=/etc/hcs.info
HCSINFO_FIELDS="hcsServiceClass|hcsServiceDetail|hcsServiceApp|hcsServiceEIR|hcsServiceEnv|hcsServiceIP|hcsServiceTeam|hcsServiceSupportGroup"

if [[ $(egrep -i "batch|aft" /etc/hcs.info) ]]; then
        echo "${DIV}"
        echo $(hostname)
        egrep "${HCSINFO_FIELDS}" "${HCS_INFO}"
        echo "${DIV}"
        exit
    else
        exit 1
fi

