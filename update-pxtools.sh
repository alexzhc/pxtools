#!/bin/bash
set -x

VERSION_SHORT=$(date +%Y-%m-%d)
VERSION_LONG=$(date +%Y-%m-%d-%H%M%S)

rm -fr pxtools-build/
mkdir -p pxtools-build/pxtools 
cp -vpr pxtools-mac/* pxtools-build/pxtools/
chmod -R 744 pxtools-build/pxtools

echo ${VERSION_LONG} >> pxtools-build/pxtools/version

cat <<EOF > pxtools-build/Dockerfile
FROM busybox
ARG version
COPY pxtools /pxtools
CMD sh -c "mv -vf /pxtools /drop; cat /drop/pxtools/version"
EOF

docker build pxtools-build \
--build-arg version=${VERSION_LONG} \
-t daocloud.io/portworx/pxtools:${VERSION_LONG}

docker push daocloud.io/portworx/pxtools:${VERSION_LONG}

docker rmi daocloud.io/portworx/pxtools:${VERSION_SHORT}
docker tag daocloud.io/portworx/pxtools:${VERSION_LONG} daocloud.io/portworx/pxtools:${VERSION_SHORT}
docker push daocloud.io/portworx/pxtools:${VERSION_SHORT} 

docker rmi daocloud.io/portworx/pxtools:latest
docker tag daocloud.io/portworx/pxtools:${VERSION_LONG} daocloud.io/portworx/pxtools:latest
docker push daocloud.io/portworx/pxtools:latest
