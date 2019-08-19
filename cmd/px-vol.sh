

curl -L https://dce.daocloud.io/DaoCloud_Enterprise/3.0.4/os-requirements > /usr/local/bin/os-requirements
chmod +x /usr/local/bin/os-requirements

sudo bash -c "$(docker run --rm -i -v /var/run/docker.sock:/var/run/docker.sock 192.168.176.91/kube-system/dce:3.0.4-27070 join --controller-addr 192.168.176.91 --with-controller --with-registry)"
              