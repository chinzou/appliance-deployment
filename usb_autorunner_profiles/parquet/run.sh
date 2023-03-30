#!/usr/bin/env bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )";
REGISTRY_IP=${REGISTRY_IP:-10.0.90.99}
kubectl_bin="/usr/local/bin/k3s kubectl"
: "${APPLIANCE_NAMESPACE:=appliance}"
ANALYTICS_NAMESPACE="analytics"

# Get USB mount point
usb_mount_point=`grep "mount_point" /etc/usb-autorunner/usbinfo | cut -d'=' -f2 | tr -d '"'`
parquet_folder=${usb_mount_point}/parquet-$(date +'%Y-%m-%d_%H-%M')/
mkdir -p $parquet_folder
echo "ℹ️ Parquet exports will be saved in '${parquet_folder}'"

# Sync images to registry
echo "⚙️  Upload container images to the registry at $REGISTRY_IP..."
for dir in $SCRIPT_DIR/images/*/ ; do
    cd $dir && skopeo sync --scoped --dest-tls-verify=false --src dir --dest docker ./ $REGISTRY_IP
done

# Create namespace
echo "⚙️  Create namespace for analytics"
$kubectl_bin create namespace $ANALYTICS_NAMESPACE

# Delete previous parquet job
echo "⚙️  Delete previous parquet jobs"
$kubectl_bin delete job -n analytics analytics-export --ignore-not-found

# Apply K8s Prometheus resources
echo "⚙️  Apply K8s Analytics manifests..."
$kubectl_bin apply -f $SCRIPT_DIR/k8s/ozone-analytics -R

# Generate K8s file
parquet_folder=$parquet_folder envsubst < $SCRIPT_DIR/k8s/parquet-export.yml.template > $SCRIPT_DIR/k8s/parquet-export.yml

# Apply K8s Prometheus resources
echo "⚙️  Apply K8s Parquet manifests..."
$kubectl_bin apply -n $ANALYTICS_NAMESPACE -f $SCRIPT_DIR/k8s -R

echo "✅  Done."
