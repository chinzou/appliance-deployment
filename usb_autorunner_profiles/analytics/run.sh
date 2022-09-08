#!/usr/bin/env bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )";
REGISTRY_IP=${REGISTRY_IP:-10.0.90.99}
kubectl_bin="/usr/local/bin/k3s kubectl"
: "${APPLIANCE_NAMESPACE:=appliance}"
ANALYTICS_NAMESPACE="analytics"

POD_NAME=$($kubectl_bin get pod -l app=registry -o jsonpath="{.items[0].metadata.name}" -n $APPLIANCE_NAMESPACE)
$kubectl_bin wait --for=condition=ready --timeout 1800s pod $POD_NAME -n $APPLIANCE_NAMESPACE

mkdir -p /mnt/disks/ssd1/analytics/parquet
mkdir -p /mnt/disks/ssd1/analytics/kafka

# Sync images to registry
echo "⚙️  Upload container images to the registry at $REGISTRY_IP..."
cd $SCRIPT_DIR/images/ && skopeo sync --scoped --dest-tls-verify=false --src dir --dest docker ./ $REGISTRY_IP

# Create namespace
echo "⚙️  Create namespace for analytics"
$kubectl_bin create namespace $ANALYTICS_NAMESPACE

echo "⚙️  Apply volumes manifests"
$kubectl_bin apply -f $SCRIPT_DIR/manifests

# Apply K8s Prometheus resources
echo "⚙️  Apply K8s Analytics manifests..."
$kubectl_bin apply -f $SCRIPT_DIR/k8s/ozone-analytics -R

echo "✅  Done."
