#!/bin/bash
#######################################################
## Author: alex.zheng@daocloud.io                    ##
## Disclaimer: Only Use under DaoCloud's supervision ##
#######################################################

# Must run in the script directoy 
WORK_DIR="$( pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
TIMESTAMP=$( date +%Y-%m-%d_%H-%M-%S )
BACKUP_DIR=/var/local/pwx-etcd-backup/${TIMESTAMP}

source ${SCRIPT_DIR}/../lib/bash_colors.sh
source ${SCRIPT_DIR}/../lib/confirm.sh
source ${SCRIPT_DIR}/../lib/shflags.sh 

DEFINE_string 'registry' 'daocloud.io/portworx' 'Docker registry address' 'r'
DEFINE_string 'tag' 'latest' 'Image tag' 't'
DEFINE_string 'ip' '' 'IP' 'i'
DEFINE_string 'peer_port' '19018' 'Peer point' 'e'
DEFINE_string 'client_port' '19019' 'Client point' 'c'
DEFINE_string 'key' '' 'Key' 'k'
DEFINE_boolean 'all' false 'All' 'a'
DEFINE_boolean 'pull' false 'Enforce pull image' 'p'
DEFINE_boolean 'yes' false 'Answer "yes" to confirm' 'y'
DEFINE_boolean 'force' false 'Force' 'f'
DEFINE_boolean 'hide_init_cluster' false 'Hide "INIT_CLUSTER=" from env' 'd'

# Default parameters
: ${IMAGE:=etcd}
: ${DATA_DIR:=/var/local/pwx-etcd}
: ${CLUSTER_TOKEN:=pwx}
: ${TIMESTAMP:=$( date +%Y-%m-%d_%H-%M-%S )}

FLAGS_HELP=$( cat <<EOF
NAME:
  $0 - A script to maintain etcd cluster for PX

$( clr_brown WARNING ):
  1. Only use this script after consulting DaoCloud
  2. PX production requires a 3 or 5 nodes etcd cluster

USAGE:
  bash $0 [flags] [ACTION]
  bash $0 [ACTION] [flags]

ACTION:
   create   -[rtiecp]   Create a single-node etcd cluster from the local node
   join     -[rtiecp]   Join the local node to an existing etcd cluster
   remove   -[yf]       Remove the local node from the etcd cluster $( clr_red DANGEROUS! )
   status               Check cluster health
   printenv -[k]        Display environment variables
   upgrade  -[rt]       Upgrade the local node
   del_pwx  -[ak]       Delete PX keys $( clr_red DANGEROUS! )
   hide_init_cluster    Hide "INITIAL_CLUSTER=" from env         
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

    # Parse flags
    if [ -z "${FLAGS_registry}" ]; then
        IMAGE_ADDR=${IMAGE}:${FLAGS_tag}
    else
        IMAGE_ADDR=${FLAGS_registry}/${IMAGE}:${FLAGS_tag}
    fi     
    PEER_PORT=${FLAGS_peer_port}
    CLIENT_PORT=${FLAGS_client_port}

    # Parse actions 
    case ${ACTION} in
        create            )        _create            ;;
        join              )        _join              ;;
        remove            )        _remove            ;;
        status            )        _status            ;;
        upgrade           )        _upgrade           ;;
        printenv          )        _printenv          ;;
        del_pwx           )        _del_pwx           ;;
        hide_init_cluster )        _hide_init_cluster ;;   
        help              )        flags_help         ;;
        *                 )
            clr_red "ERROR: Invalid action" >&2
            flags_help
            exit 1
    esac
}

_create() { 
    [ -z ${FLAGS_ip} ] && clr_red "ERROR: Must provide an IP or Hostname by --ip" && exit 1

    # Check if IP is present on the local node 
    if ip a | grep -q "inet ${FLAGS_ip}\/"; then
        HOST_IP=${FLAGS_ip}
    else
        clr_red "ERROR: ${FLAGS_ip} is not present on this host"
        exit 1
    fi
    
    # Create cluster
    clr_green "Create etcd cluster"
    echo New node: http://${HOST_IP}:${CLIENT_PORT}
    EXISTING_CLUSTER=""
    CLUSTER_STATE=new
    _install
}

_join() {
    [ -z ${FLAGS_ip} ] && clr_red "ERROR: Must provide an IP or Hostname --ip" && exit 1

    REMOTE_IP=${FLAGS_ip}
    REMOTE_PORT=${CLIENT_PORT}

    REMOTE_API=http://${REMOTE_IP}:${REMOTE_PORT}

    clr_green "Curl ${REMOTE_API}/health"
    # Check remote IP and find local IP
    if curl -s ${REMOTE_API}/health; then
        echo
        HOST_IP=$( ip route get ${REMOTE_IP} | sed 's# #\n#g' | awk '/src/ {getline; print}' )  
        if [[ "${HOST_IP}" == "${REMOTE_IP}" ]]; then
            clr_red "ERROR: ${REMOTE_IP} should not be local"
            exit 1
        fi
    else
        clr_red "ERROR: etcd:${REMOTE_API} is unreachable"  
        exit 1        
    fi     

    # Check the local IP is already registered   
    if curl -s ${REMOTE_API}/v2/members | grep ${HOST_IP}; then
        clr_red "ERROR: This host is already registered to the cluster"
        exit 1
    fi
     
    # Register new member 
    clr_green "Register node ${HOST_IP} to etcd cluster"
    if curl -s ${REMOTE_API}/v2/members -XPOST -H "Content-Type: application/json" -d "{\"name\":\"px-etcd-${HOST_IP}-${CLIENT_PORT}\",\"peerURLs\":[\"http://${HOST_IP}:${PEER_PORT}\"]}"; then
        echo
    else
        clr_red "ERROR: Failed to register ${HOST_IP} to the cluster" 
        exit 1
    fi

    # Add cluster member
    clr_green "Join etcd cluster"
    echo New node: http://${HOST_IP}:${CLIENT_PORT}
    EXISTING_CLUSTER=$( curl -s ${REMOTE_API}/v2/members | sed 's#","peerURLs":\["#=#g; s#"#\n#g' | awk ' /px-etcd/ {print}' ORS=',' )
    CLUSTER_STATE=existing
    _install
}

_remove() {
    clr_red "ATTENTION: Will irreversibly delete all etcd data on this node!"
    
    confirm ${FLAGS_yes} || exit 1

    # Gracefully check and deregister
    if [ ${FLAGS_force} -eq ${FLAGS_FALSE} ]; then
        if /opt/pwx-etcd/bin/runc list | grep -qw "portworx-etcd .* running"; then 
            clr_green "Check local member status"
            LOCAL_MEMBER_SPEC=$( /opt/pwx-etcd/bin/runc exec portworx-etcd sh -c "etcdctl member list | grep -w \${ETCD_LISTEN_CLIENT_URLS}" )
            echo ${LOCAL_MEMBER_SPEC}
            LOCAL_MEMBER_ID=$( echo ${LOCAL_MEMBER_SPEC} | awk 'BEGIN {FS =":"}{print $1}' )
            /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl cluster-health | grep ${LOCAL_MEMBER_ID}
        
            clr_green "Deregister local member from etcd cluster"
            MEMBER_COUNT=$( /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl member list | wc -l )
            if [[ "${MEMBER_COUNT}" == "1" ]]; then
                clr_brown "WARN: this is the last member, the cluster will be destroyed"
            else
                /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl member remove ${LOCAL_MEMBER_ID}
            fi
        else 
            clr_brown "WARN: px-etcd seems not running on this host, use --force"
            exit 1
        fi
    else 
        clr_brown "WARN: Force remove an etcd member. Will not deregister it"
    fi

    # Stop service
    clr_brown "WARN: Stop and remove portworx-etcd.service"
    if [ -f /etc/systemd/system/portworx-etcd.service ]; then
        systemctl stop --now portworx-etcd
        rm -vf /etc/systemd/system/portworx-etcd.service
        systemctl daemon-reload
    fi
    
    # Backup config and data
    clr_brown "WARN: Backup config and data to /var/pwx-etcd-backup"
    mkdir -vp /var/pwx-etcd-backup
    mv -vf /opt/pwx-etcd/oci/config.json ${BACKUP_DIR}/config.json_${TIMESTAMP} || true
    mv -vf /var/local/pwx-etcd/data ${BACKUP_DIR}/data_${TIMESTAMP} || true  
    
    # Remove files
    clr_brown "WARN: Remove files"
    rm -vfr /opt/pwx-etcd/ | tail -1
    rm -vfr /var/local/pwx-etcd | tail -1   
}

_upgrade() {
    UPGRADE=true
    clr_green "Upgrade etcd version to"
    echo ${IMAGE_ADDR}

    clr_green "Stop portworx-etcd.service"
    systemctl stop --now portworx-etcd

    clr_green "Backup oci files" 
    mv -vf /opt/pwx-etcd/oci/rootfs /opt/pwx-etcd/oci/rootfs_${TIMESTAMP}
    mkdir -vp /opt/pwx-etcd/oci/rootfs
    
    _extract_rootfs

    _start_service
    
    _status

    _cmd_ref
}

_extract_rootfs() {
    [ ${FLAGS_pull} -eq ${FLAGS_TRUE} ] || ${UPGRADE} && docker pull ${IMAGE_ADDR}
    printf "${IMAGE_ADDR}  "
    docker export $( docker create ${IMAGE_ADDR} ) | \
    tar -C /opt/pwx-etcd/oci/rootfs --checkpoint=200 --checkpoint-action=exec='printf "\b=>"' -xf -
    echo " /opt/pwx-etcd/oci/rootfs/"
}

_start_service() {
    clr_green "Start portworx-etcd.service"
    systemctl daemon-reload
    systemctl enable --now portworx-etcd
    sleep 5
    systemctl status portworx-etcd | grep -w "Loaded\|Active"

}

_status() { 
    clr_green "Check cluster health"
    /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl -v

    /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl cluster-health \
    | sed -r "s/( healthy)/$(clr_cyan \\1)/g; s/(degraded|unreachable)/$(clr_red \\1)/g" || true      

    /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl member list \
    | sed -r "s/(isLeader=true)/$(clr_cyan \\1)/g"  || true

    clr_green "For PX configuration:"
    /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl cluster-health \
    | awk '/http/ {print "etcd:"$NF}' \
    | paste -sd "," -
   
}

_printenv() {
    clr_green "Environment variables:"
    /opt/pwx-etcd/bin/runc exec portworx-etcd printenv ${FLAGS_key}
   
    clr_green "Recognized variables:"
    journalctl -lu portworx-etcd \
    | tac | grep -m1 -B100 "Started Portworx Etcd OCI Container" \
    | tac | grep "recognized and used environment variable ${FLAGS_key}"
}

_cmd_ref() {
    clr_green "Command reference"
    echo "$( clr_brown 'Watch log:' )        journalctl -fu portworx-etcd"
    echo "$( clr_brown 'Watch container:' )  /opt/pwx-etcd/bin/runc list"
    echo "$( clr_brown 'Check health:' )     /opt/pwx-etcd/bin/runc exec portworx-etcd etcdctl cluster-health"
}


_install() {
    # Copy files
    clr_green "Copy control files"
    mkdir -vp /opt/pwx-etcd/bin 
    mkdir -vp /opt/pwx-etcd/oci/rootfs 
    mkdir -vp /var/local/pwx-etcd/data
    cp -vf ${SCRIPT_DIR}/runc /opt/pwx-etcd/bin/
    cp -vf ${SCRIPT_DIR}/px-etcd-config.json /opt/pwx-etcd/oci/config.json
    cp -vf ${SCRIPT_DIR}/portworx-etcd.service /etc/systemd/system/

    # Extract roofts 
    clr_green "Extract OCI rootfs" 
    _extract_rootfs

    # Generate enivronment variables
    cat > etcd_env.txt <<EOF
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TERM=xterm",
            "GOMAXPROCS=8",
            "ETCD_DATA_DIR=/.pwx-etcd/data",
            "ETCD_ADVERTISE_CLIENT_URLS=http://${HOST_IP}:${CLIENT_PORT}",
            "ETCD_LISTEN_PEER_URLS=http://${HOST_IP}:${PEER_PORT}",
            "ETCD_LISTEN_CLIENT_URLS=http://${HOST_IP}:${CLIENT_PORT}",
            "ETCD_INITIAL_ADVERTISE_PEER_URLS=http://${HOST_IP}:${PEER_PORT}",
            "ETCD_INITIAL_CLUSTER=${EXISTING_CLUSTER}px-etcd-${HOST_IP}-${CLIENT_PORT}=http://${HOST_IP}:${PEER_PORT}",
            "ETCD_INITIAL_CLUSTER_STATE=${CLUSTER_STATE}",
            "ETCD_INITIAL_CLUSTER_TOKEN=${CLUSTER_TOKEN}",
            "ETCD_AUTO_COMPACTION_RETENTION=3",
            "ETCD_QUOTA_BACKEND_BYTES=$(( 8 * 1024 ** 3))",
            "ETCD_SNAPSHOT_COUNT=5000",
            "ETCDCTL_ENDPOINTS=http://${HOST_IP}:${CLIENT_PORT}"
EOF

    # Generate config.json
    sed -i "s#_PX_ETCD_NAME_#px-etcd-${HOST_IP}-${CLIENT_PORT}#" /opt/pwx-etcd/oci/config.json
    sed -i "s#_PX_ETCD_DATA_DIR_#${DATA_DIR}#" /opt/pwx-etcd/oci/config.json
    sed -i '/"env": \[/ r etcd_env.txt' /opt/pwx-etcd/oci/config.json
    rm -fr etcd_env.txt 
   
    # Verify config.json
    clr_green "Set OCI args"
    grep -A3 '\"args\"\: \[' /opt/pwx-etcd/oci/config.json
    clr_green "Set OCI datadir binding"
    grep -A7 -B1 '"destination": "/.pwx-etcd/data"' /opt/pwx-etcd/oci/config.json
    clr_green "Set OCI env"
    grep -A16 '\"env\"\: \[' /opt/pwx-etcd/oci/config.json 

    # Start portworx-etcd.service
    _start_service    

    # Check cluster health 
    _status

    # Tips
    _cmd_ref

    # Hide init_cluster
    [ ${FLAGS_hide_init_cluster} -eq ${FLAGS_TRUE} ] && FLAGS_yes=true && _hide_init_cluster
}

_hide_init_cluster() {
    clr_brown "WARN: Remove initial_cluster environmental variables" 
    sed -i '/ETCD_INITIAL_CLUSTER=/d' /opt/pwx-etcd/oci/config.json
    sed -i 's/ETCD_INITIAL_CLUSTER_STATE=new/ETCD_INITIAL_CLUSTER_STATE=existing/' /opt/pwx-etcd/oci/config.json

    clr_brown "WARN: Restart portworx-etcd.service"    
    confirm ${FLAGS_yes} || exit 1
    systemctl restart portworx-etcd
    sleep 3
    _printenv 
}

_del_pwx() {
    clr_red "ATTENTION: Will ireversibly delete user data!"

    if [ ${FLAGS_all} -eq ${FLAGS_TRUE} ]; then
        PX_UID=""
        clr_brown "WARN: Delete all pwx/ entries!"
    elif [ ! -z ${FLAGS_key} ]; then
        PX_UID=${FLAGS_key}
        clr_brown "WARN: Delete pwx/${PX_UID} entries!"
    else
        clr_red "ERROR: Need to provide PX cluster UID or use --all"
        exit 1
    fi

    confirm ${FLAGS_yes} || exit 1

    clr_brown "Check number of etcd entries for PX cluser UID: ${PX_UID}"
    /opt/pwx-etcd/bin/runc exec -e ETCDCTL_API=3 \
    portworx-etcd etcdctl get --prefix "pwx/${PX_UID}" | wc -l

    clr_brown "Delete etcd entries for PX cluster UID: ${PX_UID}"
    /opt/pwx-etcd/bin/runc exec -e ETCDCTL_API=3 \
    portworx-etcd etcdctl del --prefix "pwx/${PX_UID}"

    clr_brown "Check number of etcd entries for PX cluster UID: ${PX_UID}"
    /opt/pwx-etcd/bin/runc exec -e ETCDCTL_API=3 \
    portworx-etcd etcdctl get --prefix "pwx/${PX_UID}" | wc -l
}

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

set -e -o pipefail
_main "$@"

cd "${WORK_DIR}"

