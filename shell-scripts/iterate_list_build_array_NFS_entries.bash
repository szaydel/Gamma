#!/bin/bash
##: Title       : Build array of NFS Srv IP + Share
##: Date Rel    : 12/27/2010
##: Date Upd    : 12/28/2010
##: Author      : "Sam Zaydel" <sam.zaydel@usps.gov>
##: Version     : 0.0.1
##: Release     : Alpha
##: Description : Script will be used to read contents of hcsservices-hostinfo-***
##              : and build an array of NFS Server IPs and shares, one for each
##              : server in the list. This will be
##: Options     : If script accepts options, list them
##: Filename    : Name of the script ()

myarr=("")

for a in $(cat input_file_list_of_servers)

    do
        line=$(cat hcsservices-hostinfo-${a}_*|grep "^##fstab##" \
        | sed -e "s/##[a-z].*##//g" \
        | egrep --color=none --regexp="(([0-9]{1,3}|\*)\.){3}([0-9]{1,3}|\*):" \
        | cut -d " " -f1)
        myarr+=($line)
    done

