#!/bin/bash
set -o errexit
ISTIO_VERSION="${1}"

# starting timer
SECONDS=0

# Install istio
cd tmp
rm -rf istio* || true
ARCH=$(uname -a | awk '{print $NF}')

if [ "${ISTIO_VERSION}" == "LATEST" ]; then
    curl -sL https://istio.io/downloadIstio | TARGET_ARCH=${ARCH} sh -
    ISTIO_FOLDER=$(ls | grep istio | head -n1)
else
    ISTIO_FOLDER="istio-${ISTIO_VERSION}"
    curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} TARGET_ARCH=${ARCH} sh -
fi
export PATH=$PWD/${ISTIO_FOLDER}/bin:$PATH

kubectl create namespace istio-ingress || true
istioctl install -f ../meshConfig.yaml --skip-confirmation
sleep 5

# Install kiali
kubectl apply -f ${ISTIO_FOLDER}/samples/addons/kiali.yaml

# Install prometheus
kubectl apply -f ${ISTIO_FOLDER}/samples/addons/prometheus.yaml

# Install grafana
kubectl apply -f ${ISTIO_FOLDER}/samples/addons/grafana.yaml

# Validate all pods are running in istio-system
kubectl wait -n istio-system --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=5m

# enable additional istio config and create application namespaces
cd ../
kubectl apply -k .

# show duration
duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."
