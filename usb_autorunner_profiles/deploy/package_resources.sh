#!/usr/bin/env bash
set -e

BASE_DIR=$(dirname "$0")
DISTRO_NAME=c2c
DISTRO_VERSION=1.0.0-SNAPSHOT
DISTRO_REVISION=1.0.0-20210514.150940-74
BUILD_DIR=$BASE_DIR/target/build
RESOURCES_DIR=$BASE_DIR/target/resources
IMAGES_FILE=$BUILD_DIR/images.txt
VALUES_FILE=$BUILD_DIR/k8s-description-files/src/bahmni-helm/values.yaml
DISTRO_VALUES_FILE=$RESOURCES_DIR/distro/k8s-services.yml
DEPLOYMENT_VALUES_FILE=$BASE_DIR/deployment-values.yml
K8S_DESCRIPTION_FILES_GIT_REF=master

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

rm -rf $RESOURCES_DIR
mkdir -p $RESOURCES_DIR

# Fetch distro
echo "⚙️ Download $DISTRO_NAME distro..."
wget https://nexus.mekomsolutions.net/repository/maven-snapshots/net/mekomsolutions/bahmni-distro-$DISTRO_NAME/$DISTRO_VERSION/bahmni-distro-$DISTRO_NAME-$DISTRO_REVISION.zip -O $BUILD_DIR/bahmni-distro-c2c.zip
mkdir -p $RESOURCES_DIR/distro
unzip $BUILD_DIR/bahmni-distro-c2c.zip -d $RESOURCES_DIR/distro

# Fetch K8s files
echo "⚙️ Clone K8s description files GitHub repo and checkout '$K8S_DESCRIPTION_FILES_GIT_REF'..."
rm -rf $BUILD_DIR/k8s-description-files
git clone https://github.com/mekomsolutions/k8s-description-files.git $BUILD_DIR/k8s-description-files
dir1=$BASE_DIR
dir2=$PWD
cd $BUILD_DIR/k8s-description-files && git checkout $K8S_DESCRIPTION_FILES_GIT_REF && cd $dir2

echo "⚙️ Run Helm to substitute custom values..."
helm template `[ -f $DISTRO_VALUES_FILE ] && echo "-f $DISTRO_VALUES_FILE"` `[ -f $DEPLOYMENT_VALUES_FILE ] && echo "-f $DEPLOYMENT_VALUES_FILE"` $DISTRO_NAME $BUILD_DIR/k8s-description-files/src/bahmni-helm --output-dir $RESOURCES_DIR/k8s

echo "⚙️ Parse the list of container images..."
cat /dev/null > $IMAGES_FILE
grep -ri "image:" $RESOURCES_DIR/k8s  | awk -F': ' '{print $3}' | xargs | tr " " "\n" >> $IMAGES_FILE

echo "⚙️ Read registry address from '$DEPLOYMENT_VALUES_FILE'"
registry_ip=$(grep -ri "docker_registry:" $DEPLOYMENT_VALUES_FILE | awk -F': ' '{print $2}' | tr -d " ")

temp_file=$(mktemp)
cp $IMAGES_FILE $temp_file
echo "⚙️ Override '$registry_ip' by 'docker.io'"
sed -e "s/${registry_ip}/docker.io/g" $IMAGES_FILE > $temp_file
echo "⚙️ Remove duplicates..."
sort $temp_file | uniq > $IMAGES_FILE
rm ${temp_file}
echo "ℹ️ Images to be downloaded:"
cat $IMAGES_FILE

echo "🚀 Download container images..."
set +e
cat $IMAGES_FILE | $BASE_DIR/download-images.sh $RESOURCES_DIR/images
set -e

echo "⚙️ Copy 'run.sh' and 'utils/'..."
cp -R $BASE_DIR/run.sh $BASE_DIR/utils $RESOURCES_DIR/
