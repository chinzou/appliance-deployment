#!/usr/bin/env bash
set -e

kubectl="/usr/local/bin/k3s kubectl"
PWD=$(dirname "$0")
REGISTRY_IP=10.0.90.99
: "${NAMESPACE:=default}"

JOB_NAME=openmrs-db-restore
OPENMRS_SERVICE_NAME=openmrs
AUTORUNNER_WORKDIR=/opt/autorunner/workdir
ARCHIVE_PATH=${AUTORUNNER_WORKDIR}/dump.sql

mysql_app=`$kubectl get statefulsets.apps | grep 'mysql'`
if [ -n "$mysql_app" ] ; then
  echo "⚙️  Fetch MySQL credentials"
  DB_USERNAME=`$kubectl get configmap mysql-configs -o json | jq '.data.MYSQL_ROOT_USER' | tr -d '"'`
  DB_PASSWORD=`$kubectl get configmap mysql-configs -o json | jq '.data.MYSQL_ROOT_PASSWORD' | tr -d '"'`
  DB_NAME=openmrs

  echo "Remove previous job, if exists"
  $kubectl delete --ignore-not-found=true job ${JOB_NAME}

  echo "Stop the OpenMRS service"
  $kubectl scale deployment ${OPENMRS_SERVICE_NAME} --replicas 0

  echo "⚙️  Run MySQL restore job"
  cat <<EOF | $kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: "${JOB_NAME}"
  labels:
    app: db-restore
spec:
  template:
    spec:
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
      - name: restore-storage
        hostPath:
          path: ${ARCHIVE_PATH}
          type: File
      containers:
      - name: mysql-db-restore
        image: 10.0.90.99/mekomsolutions/mysql_backup:9ab7a24
        command: ["mysql"]
        args: ["-hmysql", "-u${DB_USERNAME}", "-p${DB_PASSWORD}", "${DB_NAME}", "-e", "source /opt/dump.sql"]
        env:
        volumeMounts:
        - name: restore-storage
          mountPath: /opt/dump.sql
      restartPolicy: Never
EOF
  echo "🕐 Wait for the job to complete... (timeou=1h)"
  $kubectl wait --for=condition=complete --timeout 3600s job/${JOB_NAME}
  echo "Completed."

  echo "Set OpenMRS index to be rebuilt"

  echo "🚀 Restart OpenMRS service"
  $kubectl scale deployment ${OPENMRS_SERVICE_NAME} --replicas 1

else
  echo "⚠️  MySQL service is not found, abort"
  exit 1
fi

echo "✅ Done."
