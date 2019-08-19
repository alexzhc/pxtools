#! /bin/bash 
set -e -o pipefail

NAMESPACE=$1
APPNAME=$2
TIMESTAMP=$( date -u  +%Y-%m-%dT%H:%M:%SZ )

if [ "$#" -ne 2 ]; then
    echo "dce-app-reg.sh <namesapce> <appname>"
    exit 1
fi


docker exec dce_etcd_1 etcdctl set /DCE/v1/app/${NAMESPACE}/${APPNAME} \
"{\"kind\": \"App\", \"spec\": {\"links\": [], \"selector\": {\"match_expressions\": null, \"match_labels\": {\"dce.daocloud.io/app\": \"${APPNAME}\"}}}, \"api_version\": \"v1\", \"metadata\": {\"name\": \"${APPNAME}\", \"owner_references\": null, \"generation\": null, \"namespace\": \"${NAMESPACE}\", \"labels\": null, \"generate_name\": null, \"deletion_timestamp\": null, \"cluster_name\": null, \"finalizers\": null, \"deletion_grace_period_seconds\": null, \"initializers\": null, \"self_link\": null, \"resource_version\": null, \"creation_timestamp\": \"${TIMESTAMP}\", \"annotations\": null, \"uid\": null}}" 
