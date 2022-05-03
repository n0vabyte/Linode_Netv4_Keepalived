#!/bin/bash

keepalived_log='/tmp/keepalived.state'
function check_state {
        local state=$1
        cat << EOF >> $keepalived_log
===================================
Date:  $(date +'%d-%b-%Y %H:%M:%S')
[INFO] Now $state

EOF
        if [[ "$state" == "Master" ]]; then
                sudo systemctl restart lelastic
        else
                sudo systemctl stop lelastic
        fi
}

function main {
        local state=$1
        case $state in
        Master)
                check_state Master;;
        Backup)
                check_state Backup;;
        Fault)
                check_state Fault;;
        *)
                echo "[ERR] Provided arguement is invalid"
        esac
}
main $1