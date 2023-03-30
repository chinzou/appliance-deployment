#!/usr/bin/env bash
set -e

PROFILE_DIR=$(dirname "$0")
BUILD_DIR=$PROFILE_DIR/target/build
BUILD_RESOURCES_DIR=$PROFILE_DIR/target/resources
BASE_DIR=$(dirname "$0")
BUILD_DIR=$BASE_DIR/target/build
RESOURCES_DIR=$BASE_DIR/target/resources

# Utils
PACKAGING_UTILS_DIR=$PWD/resources/packaging_utils

IMAGES_FILE=$BUILD_DIR/images.txt

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

rm -rf $BUILD_RESOURCES_DIR
mkdir -p $BUILD_RESOURCES_DIR

echo "⚙️ Run Helm to substitute custom values..."
git clone git@github.com:ozone-his/ozone-analytics-helm.git $BUILD_DIR/ozone-analytics
dir1=$BASE_DIR
dir2=$PWD
helm template analytics $BUILD_DIR/ozone-analytics --output-dir $RESOURCES_DIR/k8s --namespace analytics

# Copy run.sh as a build resource
cp $PROFILE_DIR/run.sh $BUILD_DIR/

echo "⚙️ Parse the list of container images from the k8s folder ..."
# Init temporary dir
temp_file=$(mktemp)
# Empty/create file to hold the list of images
cat /dev/null > $IMAGES_FILE
grep -rih "image:" $PROFILE_DIR/k8s | awk -F': ' '{print $2}' | xargs | tr " " "\n" >> $IMAGES_FILE
cp $IMAGES_FILE $temp_file

echo "⚙️ Remove duplicates..."
sort $temp_file | uniq > $IMAGES_FILE
rm ${temp_file}
echo "ℹ️ Images to be downloaded:"
cat $IMAGES_FILE

echo "🚀 Download container images..."
mkdir -p $BUILD_RESOURCES_DIR/images
cat $IMAGES_FILE | $PACKAGING_UTILS_DIR/download-images.sh $BUILD_DIR/images

# Copy resources
echo "⚙️ Copy files..."
cp -R $PROFILE_DIR/run.sh $PROFILE_DIR/k8s $BUILD_DIR/images $BUILD_RESOURCES_DIR/
