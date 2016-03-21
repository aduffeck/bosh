#!/bin/sh

set -eux

#
# target/authenticate
#

bosh -n target "$TARGET"
bosh login "$USERNAME" "$PASSWORD"
DIRECTOR_UUID=`bosh status --uuid`

cat > manifest.yml <<EOF
---
director_uuid: "$DIRECTOR_UUID"
update:
  canaries: 1
  max_in_flight: 1
  canary_watch_time: 1000 - 90000
  update_watch_time: 1000 - 90000
jobs: []
EOF


#
# stemcell metadata/upload
#

tar -xzf stemcell/*.tgz $( tar -tzf stemcell/*.tgz | grep 'stemcell.MF' )
STEMCELL_OS=$( grep -E '^operating_system: ' stemcell.MF | awk '{print $2}' | tr -d "\"'" )
STEMCELL_VERSION=$( grep -E '^version: ' stemcell.MF | awk '{print $2}' | tr -d "\"'" )

bosh upload stemcell --skip-if-exists stemcell/*.tgz

cat >> manifest.yml <<EOF
stemcells:
- alias: default
  os: "$STEMCELL_OS"
  version: "$STEMCELL_VERSION"
EOF


#
# release metadata/upload
#

EXPORT_RELEASES=""

echo "releases:" >> manifest.yml

for RELEASE_DIR in $( find . -maxdepth 1 -name '*-release' ) ; do
  cd $RELEASE_DIR

  # extract our true name and version
  tar -xzf *.tgz $( tar -tzf *.tgz | grep 'release.MF' )
  RELEASE_NAME=$( grep -E '^name: ' release.MF | awk '{print $2}' | tr -d "\"'" )

  RELEASE_VERSION=$( grep -E '^version: ' release.MF | awk '{print $2}' | tr -d "\"'" )

  bosh upload release --skip-if-exists *.tgz

  cd ../

  # include ourselves in the manifest
  cat >> manifest.yml <<EOF
- name: "$RELEASE_NAME"
  version: "$RELEASE_VERSION"
EOF

  # remember to export us later
  EXPORT_RELEASES="$EXPORT_RELEASES $RELEASE_NAME/$RELEASE_VERSION"
done


#
# compilation deployment
#

DEPLOYMENT_NAME=$STEMCELL_OS-$STEMCELL_VERSION-compilation

echo "name: $DEPLOYMENT_NAME" >> manifest.yml

bosh deployment manifest.yml

bosh -n deploy

#
# compile/export all releases
#

for EXPORT_RELEASE in $EXPORT_RELEASES ; do
  bosh export release $EXPORT_RELEASE $STEMCELL_OS/$STEMCELL_VERSION

  if [ "$(echo $EXPORT_RELEASE | sed -e s/bosh\\/.*/true/ )" == "true" ]; then
    mv *.tgz compiled-releases/$(find *.tgz | sed s/release-bosh/bosh-release/)
  else
    mv *.tgz compiled-releases
  fi
done

#
# cleanup
#

bosh -n delete deployment $DEPLOYMENT_NAME
