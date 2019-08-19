# pxtools
Scripts to assist Portworx install and maintenance
Reference https://docs.portworx.com/

## Get from docker image
```
docker run --rm -v $(pwd):/drop daocloud.io/portworx/pxtools
```

## px-node.sh
```
$ cmd/px-node.sh --help
NAME:
  pxtools-mac/cmd/px-node.sh - A script to maintain PX nodes

WARNING:
  1. Only use this script after consulting DaoCloud
  2. Only use this script for Swarm, Mesos, and nodes without scheduler. NOT for K8s
  3. PX production requires minimum 3 nodes
  4. All image must be stored in a registry; "docker load" will not work

USAGE:
  bash pxtools-mac/cmd/px-node.sh [flags] [ACTION]
  bash pxtools-mac/cmd/px-node.sh [ACTION] [flags]

ACTION:
   prepare              Prepare OS enviroment
   install  -[ritfply]  Install a PX node
   upgrade  -[ritply]   Upgrade a PX node
   reconf   -[rftly]    Reconfigure a PX node DANGEROUS!
   remove   -[y]        Remove a PX node DANGEROUS!
   reset    -[y]        Wipe all PX signatures from a node DANGEROUS!
   backup               Backup PX configuration on a node

flags:
  -r,--registry:  Docker registry address (default: 'daocloud.io/portworx')
  -i,--image:  Image name (default: 'px-enterprise')
  -t,--tag:  Image tag (default: 'latest')
  -f,--file:  Path to PX config options file (default: './px-opts.txt')
  -p,--pull:  Force pull image (default: false)
  -l,--log:  Display logs (default: false)
  -y,--yes:  Answer yes to confirm (default: false)
  -h,--help:  show this help (default: false)
```

## px-etcd.sh
```
$ etcd/px-etcd.sh --help
NAME:
  pxtools-mac/etcd/px-etcd.sh - A script to maintain etcd cluster for PX

WARNING:
  1. Only use this script after consulting DaoCloud
  2. PX production requires a 3 or 5 nodes etcd cluster

USAGE:
  bash pxtools-mac/etcd/px-etcd.sh [flags] [ACTION]
  bash pxtools-mac/etcd/px-etcd.sh [ACTION] [flags]

ACTION:
   create    -[rtiecp]   Create a single-node etcd cluster from the local node
   join      -[rtiecp]   Join the local node to an existing etcd cluster
   remove    -[yf]       Remove the local node from the etcd cluster DANGEROUS!
   status                Check cluster health
   printenv  -[k]        Display environment variables
   upgrade   -[rt]       Upgrade the local node
   del_pwx   -[ak]       Delete PX keys DANGEROUS!
   hide_init_cluster     Hide "INITIAL_CLUSTER=" from env

flags:
  -r,--registry:  Docker registry address (default: 'daocloud.io/portworx')
  -t,--tag:  Image tag (default: 'latest')
  -i,--ip:  IP (default: '')
  -e,--peer_port:  Peer point (default: '19018')
  -c,--client_port:  Client point (default: '19019')
  -k,--key:  Key (default: '')
  -a,--all:  All (default: false)
  -p,--pull:  Enforce pull image (default: false)
  -y,--yes:  Answer yes to confirm (default: false)
  -f,--force:  Force (default: false)
  -d,--hide_init_cluster:  Hide INIT_CLUSTER= from env (default: false)
  -h,--help:  show this help (default: false)

```

## px-yaml.sh
```
$ cmd/px-yaml.sh -help
NAME:
  pxtools-mac/cmd/px-yaml.sh - A script to create PX yaml files

WARNING:
  1. Only use this script after consulting DaoCloud
  2. PX production requires minimum 3 nodes
  3. All image must be stored in a registry; "docker load" will not work
  4. Offical yaml generator https://install.portworx.com/

USAGE:
  bash pxtools-mac/cmd/px-yaml.sh [flags] [ACTION]
  bash pxtools-mac/cmd/px-yaml.sh [ACTION] [flags]

ACTION:
   oci    -[rtpf] Create oci-monitor files
   mon    -[r]    Create lighthouse and prometheus files
   sc     -[r]    Create StorageClass files
   test   -[r]    Create test files
   stork  -[r]    Create stork files

flags:
  -r,--registry:  Docker registry address (default: 'daocloud.io/portworx')
  -t,--tag:  Image tag (default: 'latest')
  -f,--file:  Path to PX config options file (default: './px-opts.txt')
  -p,--policy:  Image Pull Policy (default: 'IfNotPresent')
  -s,--secret:  Use secret (default: 'NULL')
  -c,--csi:  Use CSI (default: false)
  -h,--help:  show this help (default: false)
```
