#!/bin/bash
#######################################################
## Author: alex.zheng@daocloud.io                    ##
## Disclaimer: Only use under DaoCloud's supervision ##
#######################################################

WORK_DIR="$( pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
TIMESTAMP=$( date +%Y-%m-%d_%H-%M-%S )
BACKUP_DIR=/var/local/pwx-backup/${TIMESTAMP}

source ${SCRIPT_DIR}/../lib/bash_colors.sh
source ${SCRIPT_DIR}/../lib/confirm.sh
source ${SCRIPT_DIR}/../lib/refresh.sh
source ${SCRIPT_DIR}/../lib/shflags.sh 

DEFINE_string 'registry' 'daocloud.io/portworx' 'Docker registry address' 'r'
DEFINE_string 'image' 'px-enterprise' 'Image name' 'i'
DEFINE_string 'tag' 'latest' 'Image tag' 't'
DEFINE_string 'file' './px-opts.txt' 'Path to PX config options file' 'f'
DEFINE_boolean 'pull' false 'Force pull image' 'p'
DEFINE_boolean 'log' false 'Display logs' 'l'
DEFINE_boolean 'yes' false 'Answer "yes" to confirm' 'y'

FLAGS_HELP=$( cat <<EOF
NAME:
  $0 - A script to maintain PX nodes

$( clr_brown WARNING ):
  1. Only use this script after consulting DaoCloud
  2. Only use this script for Swarm, Mesos, and nodes without scheduler. NOT for K8s
  3. PX production requires minimum 3 nodes
  4. All image must be stored in a registry; "docker load" will not work
   
USAGE:
  bash $0 [flags] [ACTION]
  bash $0 [ACTION] [flags]

ACTION:
   prepare              Prepare OS enviroment
   install  -[ritfply]  Install a PX node
   upgrade  -[ritply]   Upgrade a PX node
   reconf   -[rftly]    Reconfigure a PX node $( clr_red DANGEROUS! )
   remove   -[y]        Remove a PX node $( clr_red DANGEROUS! )
   reset    -[y]        Wipe all PX signatures from a node $( clr_red DANGEROUS! )
   backup               Backup PX configuration on a node
EOF
)  

# Parse cmdline arguments
_main() {
    # Parse args
    if [ $# -eq 0 ]; then
        clr_red "ERROR: Missing action."
        flags_help
        exit 1
    elif [ $# -gt 1 ]; then
        clr_red "ERROR: Only one action is allowed."
        flags_help
        exit 1
    fi
    ACTION=$1 
    
    UPGRADE=false

    if [ -z "${FLAGS_registry}" ]; then
        IMAGE_ADDR=${FLAGS_image}:${FLAGS_tag}
    else
        IMAGE_ADDR=${FLAGS_registry}/${FLAGS_image}:${FLAGS_tag}
    fi     

    # Parse actions 
    case ${ACTION} in
        prepare         )        _prepare       ;;
        install         )        _install       ;;
        upgrade         )        _upgrade       ;;
        reconf          )        _reconf        ;;
        reset           )        _reset         ;;
        remove          )        _remove        ;;
        backup          )        _backup        ;;
        help            )        flags_help     ;;
        *               )
            clr_red "ERROR: Invalid action" >&2
            flags_help
            exit 1
    esac
}

_prepare() {
    clr_green "Set vm.dirty_bytes to 120MB"
    sed -i.bak '/vm\.dirty_bytes/d' /etc/sysctl.conf
    echo vm.dirty_bytes = $(( 120 * 1024 ** 2)) >> /etc/sysctl.conf
    sysctl -p | grep vm.dirty_bytes

    KERNEL_VERSION=$( uname -r )
    
    clr_green "Current OS kernel: ${KERNEL_VERSION}"
    clr_red "Recommend the latest RHEL Kernel!"

    clr_green "Check kernel-headers and kernel-devel"
    for i in '' '-ml' '-lt' ; do
        KERNEL_PREFIX=kernel${i}
        if rpm -q "${KERNEL_PREFIX}-${KERNEL_VERSION}" > /dev/null; then 
            echo $_
            if rpm -q "${KERNEL_PREFIX}-headers-${KERNEL_VERSION}"; then
                HAS_HEADERS=true 
            else 
                clr_red "ERROR: Must install $_"
                HAS_HEADERS=false
            fi 
            if rpm -q "${KERNEL_PREFIX}-devel-${KERNEL_VERSION}"; then
                HAS_DEVEL=true
            else
                clr_red "ERROR: Must install $_"
                HAS_HEADERS=false
            fi
            ${HAS_HEADERS} && ${HAS_DEVEL} || exit 1 
            break
        fi
    done

    clr_green "Check hostname resolution"
    if ! ping -c 1 -W 1 $( hostname ); then
        clr_red "Hostname must be resolvable, check /etc/hosts!"
        exit 1
    fi 

    if [ ${FLAGS_pull} -eq ${FLAGS_TRUE} ]; then 
        clr_green "Pull ${IMAGE_ADDR}"
        docker pull ${IMAGE_ADDR}
    fi
}


_install() {
    _prepare

    ${UPGRADE} || _find_opts_file || exit 1

    if ${UPGRADE}; then
        clr_green "Upgrade PX to ${FLAGS_tag}"
        clr_red "Stop portworx.service"
        systemctl disable --now portworx
        systemctl status portworx || true
    fi

    clr_green "Extracting ${IMAGE_ADDR}"
    docker run \
    --entrypoint /runc-entry-point.sh \
    --rm -i \
    --privileged=true \
    -v /opt/pwx:/opt/pwx \
    -v /etc/pwx:/etc/pwx \
    ${IMAGE_ADDR} --upgrade

    ${UPGRADE} ||  _config

    clr_green "Start portworx.service"
    systemctl daemon-reload
    systemctl enable --now portworx 

    _status_or_log
}

_upgrade() {
    UPGRADE=true
    _install
}

_config() {
    _backup
    rm -vfr /opt/pwx/oci/config.json /etc/pwx/config.json

    clr_green "Use PX option file: ${FLAGS_file}"
    PX_OPTS=$( cat ${FLAGS_file} | grep -v "^#" | grep . )
    # add local timezone
    PX_OPTS+=" -v /etc/localtime:/etc/localtime:ro"
    
    clr_green "Configure PX with following options"
    echo "${PX_OPTS}"
    echo
    /opt/pwx/bin/px-runc install ${PX_OPTS}
}

_reconf() {
    _find_opts_file || exit 1    
    
    clr_red "WILL restart portworx; use with caution!"
    confirm ${FLAGS_yes} || exit 1
 
    _backup

    clr_brown "Stop portworx.service"
    systemctl stop --now portworx 

    _config

    clr_brown "Start portworx.service"
    systemctl daemon-reload
    systemctl enable --now portworx

    _status_or_log
}

_reset() {
    clr_red "WILL IREVERSIBLY DELETE USER DATA, USE WITH CAUTION !"    
    confirm ${FLAGS_yes} || exit 1    

    _backup

    clr_brown "Stop portworx.service"
    systemctl stop --now portworx
    
    clr_brown "Wipe config and disks"
    pxctl service node-wipe --all || \
    clr_red "Unable to wipe signatures by pxctl, please do it manually"

    clr_brown "Remove config files" 
    [ -d /etc/pwx ] && chattr -Ri /etc/pwx
    rm -vfr /etc/pwx | tail -1
    rm -vfr /opt/pwx/oci/config.json 
}

_remove() {
   _reset

   clr_brown "Remove oci root files"
   ( rm -vfr /opt/pwx || true ) | refresh

   clr_brown "Remove systemd files"
   systemctl disable --now portworx || true
   rm -vfr /etc/systemd/system/portworx.service
   systemctl daemon-reload   
}

_backup() {
    clr_brown "Back up old configuration if there is"
    if [[ -d /etc/pwx || -d /opt/pwx/oci ]]; then
        mkdir -vp ${BACKUP_DIR}/opt_pwx_oci
        ( cp -vpr /etc/pwx ${BACKUP_DIR}/etc_pwx || true ) | head -1
        cp -vp /opt/pwx/oci/config.json ${BACKUP_DIR}/opt_pwx_oci/ || true
    fi 
}


_find_opts_file() {
    if [ -f ${FLAGS_file} ]; then
        return 0
    else
        clr_red "ERROR: ${FLAGS_file} does not exist."
        return 1
    fi
}

_cmd_ref() {
    clr_green "Command reference"
    echo "$( clr_brown 'Watch log:' )        journalctl -fu portworx*"
    echo "$( clr_brown 'Watch container:' )  /opt/pwx/bin/runc list"
    echo "$( clr_brown 'Check health:' )     pxctl status"
}

_status_or_log() {
     if [ ${FLAGS_log} -eq ${FLAGS_TRUE} ]; then
        clr_green "View PX logs (Ctrl-c to exit)"
        trap "echo; _cmd_ref" SIGINT
        journalctl -fu portworx*
    else 
        sleep 5
        systemctl status portworx || true
        _cmd_ref
    fi
}

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

set -e -o pipefail
_main "$@"

cd "${WORK_DIR}"
