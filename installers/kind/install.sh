#!/bin/bash
set -o errexit
KIND_VERSION="${1:-LATEST}"
CLEAN_KIND_CLUSTER="${2:-FALSE}"

# starting timer
SECONDS=0

if [ "${CLEAN_KIND_CLUSTER}" == "true" ] || [ "${CLEAN_KIND_CLUSTER}" == "TRUE" ] ; then
  # delete kind cluster
  kind delete cluster --name local || true
  sleep 5
fi

if [ "$(kind get clusters | grep -wc local)" -eq 0 ]; then
  # create kind cluster
  if [ "${KIND_VERSION}" == "LATEST" ]; then
    kind create cluster --name local --config - <<EOF
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF
  else
    kind create cluster --name local --image kindest/node:${KIND_VERSION} --config - <<EOF
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF
  fi

  # start local docker-registry-proxy
  if [ "$(docker inspect -f '{{.State.Running}}' docker_registry_proxy 2>/dev/null || true)" != 'true' ]; then
    docker run -d --restart=always --name docker_registry_proxy \
      --net kind --hostname docker-registry-proxy \
      -p 0.0.0.0:3128:3128 \
      -e ENABLE_MANIFEST_CACHE=true \
      -v $(pwd)/docker_mirror_cache:/docker_mirror_cache \
      -v $(pwd)/docker_mirror_certs:/ca \
      rpardini/docker-registry-proxy:0.6.5
      sleep 5 # wait for the proxy to start
  fi

  SETUP_URL=http://docker-registry-proxy:3128/setup/systemd
  pids=""
  for NODE in $(kind get nodes --name local); do
    docker exec "$NODE" sh -c "\
        curl -s $SETUP_URL \
        | sed s/docker\\.service/containerd\\.service/g \
        | sed '/Environment/ s/$/ \"NO_PROXY=127.0.0.0\/8,10.0.0.0\/8,172.16.0.0\/12,192.168.0.0\/16\"/' \
        | bash" & pids="$pids $!" # Configure every node in background
  done
  wait $pids # Wait for all configurations to end

  echo -e "\n\nWaiting 15 seconds, for cluster to be ready\n\n"
  sleep 15

  kubectl wait -A --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=3m
else
  echo -e "\nKind cluster local already exists, not proceeding with clean install\n"
fi

# Install kubernetes dashboard using helm charts
# Add kubernetes-dashboard repository
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
# Deploy a Helm Release named "kubernetes-dashboard" using the kubernetes-dashboard chart
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

# create a service account and secret for logging into dashboard
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: "admin-user"
type: kubernetes.io/service-account-token
EOF
# retrieve the token for the admin-user
echo -e "\nStore below token to login to dashboard\n"
kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath="{.data.token}" | base64 -d
echo -e "\n\n"
kubectl wait -n kubernetes-dashboard --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=3m

# show duration
duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."
