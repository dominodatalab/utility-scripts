#!/bin/sh

if [ $# -ne 1 ]; then
    echo "usage: $0 pv-name"
    exit 1
fi

pv_name=$1

pvc_namespace=$(kubectl get pv $pv_name -o jsonpath='{.spec.claimRef.namespace}')
pvc_name=$(kubectl get pv $pv_name -o jsonpath='{.spec.claimRef.name}')

if [ -z $pvc_namespace -o -z $pvc_name ]; then
    echo "could not find pvc: $pv_name"
    exit 1
fi

pod_name="salvage-$pv_name"

cat <<EOF
Creating PVC namespace: $pvc_namespace name: $pvc_name
Creating POD namespace: $pvc_namespace name $pod_name
EOF

cat <<EOF | kubectl create -f -
# Mounts a volume in a pod for inspection
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  namespace: $pvc_namespace
  name: $pvc_name
spec:
  accessModes:
  - ReadWriteOnce
  resources:
     requests:
       storage: 1Gi
  volumeName: $pv_name
---
kind: Pod
apiVersion: v1
metadata:
  namespace: $pvc_namespace
  name: $pod_name
spec:
  containers:
  - name: salvage
    image: ubuntu
    command: ["/bin/sh", "-ec", "while :; do echo '.'; sleep 60 ; done"]
    volumeMounts:
    - mountPath: /salvage
      name: salvaged-volume
  nodeSelector:
    dominodatalab.com/node-pool: default
  restartPolicy: Never
  volumes:
    - name: salvaged-volume
      persistentVolumeClaim:
        claimName: $pvc_name
EOF

cat <<EOF
Use:
  kubectl exec -it $pod_name -n $pvc_namespace bash
Recovered data will be in /salvage
When you are done, please remove the pod and pvc:
  kubectl delete -n $pvc_namespace pod/$pod_name
  # kubectl delete -n $pvc_namespace pvc/$pvc_name
Additionally, please clean up the PV when data has been recovered:
  kubectl delete pv $pv_name
If you wish to keep this PV to rebind later with this script, clear its claim ref:
  kubectl patch pv $pv_name --type=json -p='[{"op": "remove", "path": "/spec/claimRef/uid"}]'
EOF
