#!/usr/bin/env bash

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]:-$0}"; )" &> /dev/null && pwd 2> /dev/null; )";
DISTRO_NAME=c2c
REGISTRY_IP=${REGISTRY_IP:-10.0.90.99}
SSD_MOUNT_POINT=/mnt/disks/ssd1/
kubectl_bin="/usr/local/bin/k3s kubectl"
: "${NAMESPACE:=default}"
TIMEZONE="America/Port-au-Prince"

echo "⌚️ Set the server time zone to '$TIMEZONE'"
timedatectl set-timezone $TIMEZONE

# Ensure registry directory exists
echo "⏱  Wait for the registry to be ready..."
mkdir -p $SSD_MOUNT_POINT/registry
POD_NAME=$($kubectl_bin get pod -l app=registry -o jsonpath="{.items[0].metadata.name}" -n $NAMESPACE)
$kubectl_bin wait --for=condition=ready --timeout 1800s pod $POD_NAME -n $NAMESPACE

# sync images to registry
echo "⚙️  Upload container images to the registry at $REGISTRY_IP..."
cd $SCRIPT_DIR/images/docker.io && skopeo sync --scoped --dest-tls-verify=false --src dir --dest docker ./ $REGISTRY_IP

# Remove Odoo 10
echo "⚙️  Removing 'Odoo 10' services and data..."
$kubectl_bin delete deployment.apps odoo
$kubectl_bin delete deployment.apps odoo-connect
$kubectl exec postgres-0 -- psql -Upostgres -c 'DROP DATABASE IF EXISTS odoo'

# Remove Odoo filestore
echo "⚙️  Remove Odoo filestore..."
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "remove-filestore"
  labels:
    app: remove-filestore
spec:
  template:
    spec:
      successfulJobsHistoryLimit: 0
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: role
                operator: In
                values:
                - database
      volumes:
      - name: filestore
        persistentVolumeClaim:
          claimName: data-pvc
      containers:
      - name: remove-filestore
        image: ${REGISTRY_IP}/busybox:1.33.1
        command: ["rm"]
        args: ["-rf", "/filestore/odoo/*", "/filestore/openmrs/openmrs_config_checksum"]
        env:
        volumeMounts:
        - name: filestore
          mountPath: /filestore
      restartPolicy: Never
EOF

# Remove Existing distro
echo "⚙️  Removing existing distro..."
cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "remove-distro"
  labels:
    app: remove-distro
spec:
  template:
    spec:
      successfulJobsHistoryLimit: 0
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: role
                operator: In
                values:
                - database
      volumes:
      - name: filestore
        persistentVolumeClaim:
          claimName: distro-pvc
      containers:
      - name: filestore-test
        image: ${REGISTRY_IP}/busybox:1.33.1
        command: ["rm"]
        args: ["-rf", "/distro/*"]
        env:
        volumeMounts:
        - name: distro
          mountPath: /distro
      restartPolicy: Never
EOF

# Apply config
echo "⚙️  Apply K8s description files: config/ ..."
$kubectl_bin apply -f $SCRIPT_DIR/k8s/bahmni-helm/templates/configs

echo "⚙️  Upload the distro..."
# Sending distro to volume
$SCRIPT_DIR/utils/upload-files.sh $REGISTRY_IP/mdlh/alpine-rsync:3.11-3.1-1 $SCRIPT_DIR/distro/ distro-pvc

echo "🧽 Delete the current 'openmrs' pod"
$kubectl_bin delete pods -l app=openmrs -n $NAMESPACE

echo "🧽 Delete the current 'odoo' pod"
$kubectl_bin delete pods -l app=odoo -n $NAMESPACE

echo "🧽 Delete the current 'openelis' pod"
$kubectl_bin delete pods -l app=openelis -n $NAMESPACE

# Apply K8s manifests
echo "⚙️  Apply K8s description files: common/ ..."
$kubectl_bin apply -f $SCRIPT_DIR/k8s/bahmni-helm/templates/common
echo "⚙️  Apply K8s description files: apps/ ..."
$kubectl_bin apply -f $SCRIPT_DIR/k8s/bahmni-helm/templates/apps/ -R

echo "✅  Done."
