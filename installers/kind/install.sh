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

# start local kind-registry
reg_name='kind-registry'
reg_port='5000'
if [ "$(docker inspect -f '{{.State.Running}}' ${reg_name} 2>/dev/null || true)" != 'true' ]; then
  docker run -d --restart=always -p "127.0.0.1:${reg_port}:5000" --network bridge --name "${reg_name}" registry:2
fi

if [ "$(kind get clusters | grep -wc local)" -eq 0 ]; then
  # create kind cluster
  if [ ${KIND_VERSION} == "LATEST" ]; then
    kind create cluster --name local --config - <<EOF
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    containerdConfigPatches:
    - |-
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
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
    containerdConfigPatches:
    - |-
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
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

  REGISTRY_DIR="/etc/containerd/certs.d/${reg_name}:${reg_port}"
  for node in $(kind get nodes --name local); do
    docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
    cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
  [host."http://${reg_name}:5000"]
EOF
  done

  if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
    docker network connect "kind" "${reg_name}"
  fi

  # Document the local registry
  # https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
  cat <<EOF | kubectl apply -f -
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: local-registry-hosting
    namespace: kube-public
  data:
    localRegistryHosting.v1: |
      host: "${reg_name}:${reg_port}"
      help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

  echo -e "\n\nWaiting 15 seconds, for cluster to be ready\n\n"
  sleep 15

  kubectl wait -A --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=3m

  # install kubernetes-dashboard
  kubectl apply -k ../../libraries/manifests/kubernetes-dashboard
  echo -e "\nkubernetes-dashboard installed"
  # Create rbac for kubernetes dashboard admin-user
  kubectl -n kubernetes-dashboard create serviceaccount admin-user
  kubectl -n kubernetes-dashboard create clusterrolebinding admin-user --clusterrole cluster-admin --serviceaccount=kubernetes-dashboard:admin-user
  sleep 5
  rm -f tmp/*
  kubectl wait -n kubernetes-dashboard --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=3m

else
  echo -e "\nKind cluster local already exists, not proceeding with clean install\n"
fi

# create a token secret for logging into dashboard
  cat <<EOF | kubectl apply -f -
  apiVersion: v1
  kind: Secret
  metadata:
    name: admin-user
    namespace: kubernetes-dashboard
    annotations:
      kubernetes.io/service-account.name: "admin-user"
  type: kubernetes.io/service-account-token
EOF

# show duration
duration=$SECONDS
echo "$(($duration / 60)) minutes and $(($duration % 60)) seconds elapsed."
