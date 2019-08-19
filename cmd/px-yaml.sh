#!/bin/bash
#######################################################
## Author: alex.zheng@daocloud.io                    ##
## Disclaimer: Only use under DaoCloud's supervision ##
#######################################################

# Must run in the script directoy 
WORK_DIR="$( pwd )"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
TIMESTAMP=$( date +%Y-%m-%d_%H-%M-%S )

source ${SCRIPT_DIR}/../lib/bash_colors.sh
source ${SCRIPT_DIR}/../lib/confirm.sh
source ${SCRIPT_DIR}/../lib/shflags.sh 

DEFINE_string 'registry' 'daocloud.io/portworx' 'Docker registry address' 'r'
DEFINE_string 'tag' 'latest' 'Image tag' 't'
DEFINE_string 'file' './px-opts.txt' 'Path to PX config options file' 'f'
DEFINE_string 'policy' 'IfNotPresent' 'Image Pull Policy' 'p' 
DEFINE_string 'secret' 'NULL' 'Use secret' 's'
DEFINE_boolean 'csi' false 'Use CSI' 'c'

FLAGS_HELP=$( cat <<EOF
NAME:
  $0 - A script to create PX yaml files

$( clr_brown WARNING ):
  1. Only use this script after consulting DaoCloud
  2. PX production requires minimum 3 nodes
  3. All image must be stored in a registry; "docker load" will not work
  4. Offical yaml generator https://install.portworx.com/
   
USAGE:
  bash $0 [flags] [ACTION]
  bash $0 [ACTION] [flags]

ACTION:
   oci    -[rtpf] Create oci-monitor files
   gui    -[r]    Create lighthouse files
   mon    -[r]    Create prometheus files 
   sc     -[r]    Create StorageClass files        
   test   -[r]    Create test files 
   stork  -[r]    Create stork files
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

    # Parse actions 
    case ${ACTION} in
        oci     )        _oci       ;;
        gui     )        _gui       ;;
        mon     )        _mon       ;;
        sc      )        _sc        ;;
        test    )        _test      ;;
        stork   )        _stork     ;;
        *       )
            clr_red "ERROR: Invalid action" >&2
            flags_help
            exit 1
    esac
}

_oci() {
    _find_opts_file || exit 1

    clr_green "Create directory"
    mkdir -vp px-yamls/oci

    clr_green "Copy files"
    cp -vf ${SCRIPT_DIR}/../k8s/oci/* px-yamls/oci/
    if [ ${FLAGS_csi} -eq ${FLAGS_TRUE} ]; then
        cp -vf ${SCRIPT_DIR}/../k8s/csi/csi-ext.yaml px-yamls/oci/
    else 
        sed -i '/name: csi-driver-registrar/,/mountPath: \/csi/d' px-yamls/oci/oci-monitor.yaml
        rm -vfr px-yamls/oci/csi-ext.yaml
    fi 

    _modify_registry px-yamls/oci/*.yaml

    clr_green "Modify tag"
    sed -i "s#oci-monitor:.*#oci-monitor:${FLAGS_tag}#" px-yamls/oci/oci-monitor.yaml
    cat px-yamls/oci/oci-monitor.yaml | grep image: 

    _modify_image_pull_policy px-yamls/oci/*.yaml

    clr_green "Use PX options in ${FLAGS_file}"
    cat ${FLAGS_file} | awk '!/^#/ {print "            \""$1"\",\""$2"\","}' | sed 's/"",//g' > ._px_args.txt
# "-v","/etc/localtime:/etc/localtime:ro",
    cat <<EOF >> ._px_args.txt
            "--pull","${FLAGS_policy}",
EOF
    sed -i '/args\: \[/ r ._px_args.txt' px-yamls/oci/oci-monitor.yaml
    rm -fr ._px_args.txt

    cat px-yamls/oci/oci-monitor.yaml | awk -n '/args\: \[/,/\]/' | awk '{$1=$1};1'

    _location_ref "oci"
}


_gui() {
    clr_green "Create directory"
    mkdir -vp px-yamls/gui

    clr_green "Copy files"
    cp -vf ${SCRIPT_DIR}/../k8s/gui/* px-yamls/gui/

    _modify_registry px-yamls/gui/*.yaml

    _modify_image_pull_policy px-yamls/gui/*.yaml

    _location_ref "gui"
}

 
_mon() {
    clr_green "Create directory"
    mkdir -vp px-yamls/mon

    clr_green "Copy files"
    cp -vf ${SCRIPT_DIR}/../k8s/mon/* px-yamls/mon/

    _modify_registry px-yamls/mon/*.yaml

    _modify_image_pull_policy px-yamls/mon/*.yaml

    _location_ref "mon"
}

_sc() {
    clr_green "Create directory"
    mkdir -vp px-yamls/sc

    clr_green "Copy files"
    cp -vf ${SCRIPT_DIR}/../k8s/sc/* px-yamls/sc/

    _location_ref "sc"
}

_test() {
    clr_green "Create directory"
    mkdir -vp px-yamls/test

    clr_green "Copy files"
    cp -vf ${SCRIPT_DIR}/../k8s/test/* px-yamls/test/

    _modify_registry px-yamls/test/*.yaml

    _modify_image_pull_policy px-yamls/test/*.yaml

    _location_ref "test"
}

_find_opts_file() {
    if [ -f ${FLAGS_file} ]; then
        return 0
    else
        clr_red "ERROR: ${FLAGS_file} does not exist."
        return 1
    fi
}

_modify_registry() {
    clr_green "Modify registry"
    [ -z ${FLAGS_registry} ] || REGISTRY="$( echo ${FLAGS_registry} | sed 's:/*$::')/"
    sed -i "s#daocloud.io/portworx/#${REGISTRY}#g" $1
    cat $1| grep image: 
}

_modify_image_pull_policy() {
    clr_green "Modify image pull policy"
    sed -i "s#imagePullPolicy: .*#imagePullPolicy: ${FLAGS_policy}#g" $1
    cat $1 | grep imagePullPolicy
}

_location_ref() {
    clr_green "Created files at \"${WORK_DIR}/px-yamls/$1\""
}

FLAGS "$@" || exit $?
eval set -- "${FLAGS_ARGV}"

set -e -o pipefail
_main "$@"

cd "${WORK_DIR}"
