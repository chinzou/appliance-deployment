#!/usr/bin/env bash

# Exist if command return non-zero status.
set -e

DISTRO_VERSION=${DISTRO_VERSION}
ARTIFACT_GROUP=${ARTIFACT_GROUP:-net.mekomsolutions}

PVC_MOUNTER_IMAGE=mdlh/alpine-rsync:3.11-3.1-1

BASE_DIR=$(dirname "$0")
BUILD_DIR=$BASE_DIR/target/build
RESOURCES_DIR=$BASE_DIR/target/resources
PACKAGING_UTILS_DIR=$PWD/resources/packaging_utils
IMAGES_FILE=$BUILD_DIR/images.txt

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

rm -rf $RESOURCES_DIR
mkdir -p $RESOURCES_DIR

echo "⚙️ Run Helm to substitute custom values..."
git clone git@github.com:ozone-his/ozone-analytics-helm.git $BUILD_DIR/ozone-analytics
dir1=$BASE_DIR
dir2=$PWD
helm template -f $BASE_DIR/analytics-values.yml analytics $BUILD_DIR/ozone-analytics --output-dir $RESOURCES_DIR/k8s --namespace analytics

# Get container images
cat /dev/null > $IMAGES_FILE
echo "⚙️ Add the $PVC_MOUNTER_IMAGE image"
echo "docker.io/$PVC_MOUNTER_IMAGE" >> $IMAGES_FILE

echo "⚙️ Parse the list of container images..."
grep -ri "image:" $RESOURCES_DIR/k8s  | awk -F': ' '{print $3}' | xargs | tr " " "\n" >> $IMAGES_FILE

temp_file=$(mktemp)
cp $IMAGES_FILE $temp_file
echo "⚙️ Remove duplicates..."
sort $temp_file | uniq > $IMAGES_FILE
rm ${temp_file}
echo "ℹ️ Images to be downloaded:"
cat $IMAGES_FILE

echo "🚀 Download container images..."
mkdir -p $BUILD_DIR/images
cat $IMAGES_FILE | $PACKAGING_UTILS_DIR/download-images.sh $BUILD_DIR/images

# Copy resources
echo "⚙️ Copy 'run.sh' and 'utils/'..."
cp -R $BASE_DIR/run.sh $BASE_DIR/manifests $BASE_DIR/utils $BUILD_DIR/images $RESOURCES_DIR/
