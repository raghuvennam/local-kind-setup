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

# Install prometheus
# Config to move prometheus to /prometheus subpath, but that fails with kiali so we will not use it for now #
cp ${ISTIO_FOLDER}/samples/addons/prometheus.yaml ${ISTIO_FOLDER}/samples/addons/prometheus.yaml.bak
yq -i '(. | select(.kind == "Deployment") | .spec.template.spec.containers[]| select(.name == "prometheus-server"))|= (.args = (((.args // []) + ["--web.external-url=https://admin.internal/prometheus","--web.route-prefix=/prometheus"]) | unique)) ' ${ISTIO_FOLDER}/samples/addons/prometheus.yaml
# Update the health check path to match the new route prefix
sed -i -e 's|/-/ready|/prometheus/-/ready|g' -e 's|/-/healthy|/prometheus/-/healthy|g' ${ISTIO_FOLDER}/samples/addons/prometheus.yaml
# Apply the modified prometheus config
kubectl apply -f ${ISTIO_FOLDER}/samples/addons/prometheus.yaml

# Install grafana
cp ${ISTIO_FOLDER}/samples/addons/grafana.yaml ${ISTIO_FOLDER}/samples/addons/grafana.yaml.bak
# Patch only the Deployment, not all resources
# Add GF_SERVER_ROOT_URL and GF_SERVER_SERVE_FROM_SUB_PATH for subpath support
yq -i '(. | select(.kind == "Deployment") | .spec.template.spec.containers[] | select(.name == "grafana") | .env) |= ((. // []) + [{"name":"GF_SERVER_ROOT_URL","value":"https://admin.internal/grafana/"},{"name":"GF_SERVER_SERVE_FROM_SUB_PATH","value":"true"}])' ${ISTIO_FOLDER}/samples/addons/grafana.yaml
# update the prometheus URL in the grafana config
sed -i -e 's|url: http://prometheus:9090|url: http://prometheus:9090/prometheus/|g' ${ISTIO_FOLDER}/samples/addons/grafana.yaml
# Apply the modified grafana config
kubectl apply -f ${ISTIO_FOLDER}/samples/addons/grafana.yaml

# Install kiali
# Patch Kiali ConfigMap to set subpath URLs for Prometheus and Grafana
kubectl apply -f ${ISTIO_FOLDER}/samples/addons/kiali.yaml

# Set the URLs you want
export PROM_URL="http://prometheus.istio-system:9090/prometheus/"
export GRAFANA_INT_URL="http://grafana.istio-system:3000/grafana/"
export GRAFANA_EXT_URL="https://admin.internal/grafana/"

# Apply the new configuration to the Kiali ConfigMap
kubectl -n istio-system get cm kiali -o json \
| yq -o=yaml '
  .data = ( .data // {} )
  | .data["config.yaml"] = ( .data["config.yaml"] // "{}" )
  | (.data["config.yaml"] | from_yaml) as $config
  | $config.external_services = ($config.external_services // {})
  | $config.external_services.prometheus = ($config.external_services.prometheus // {})
  | $config.external_services.grafana = ($config.external_services.grafana // {})
  | $config.external_services.prometheus.url = env(PROM_URL)
  | $config.external_services.grafana.internal_url = env(GRAFANA_INT_URL)
  | $config.external_services.grafana.external_url = env(GRAFANA_EXT_URL)
  | .data["config.yaml"] = ($config | to_yaml)
' \
| kubectl apply -f -

# Delete Kiali to apply the new config
kubectl -n istio-system delete pod -l app.kubernetes.io/name=kiali

# Validate all pods are running in istio-system
kubectl wait -n istio-system --for=condition=ready pod --field-selector=status.phase!=Succeeded --timeout=5m

# Generate self-signed certs for admin.internal, web.internal, api.internal as SANs
CERT_DIR=../certs
mkdir -p $CERT_DIR
cat > $CERT_DIR/istio-ingress.cnf <<EOF
[req]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = admin.internal

[req_ext]
subjectAltName = @alt_names

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = admin.internal
DNS.2 = web.internal
DNS.3 = api.internal
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -config $CERT_DIR/istio-ingress.cnf \
    -extensions v3_req \
    -keyout $CERT_DIR/internal.key \
    -out $CERT_DIR/internal.crt

# Create Kubernetes TLS secret for Istio Gateway
kubectl create -n istio-ingress secret tls internal-cert \
    --key $CERT_DIR/internal.key \
    --cert $CERT_DIR/internal.crt --dry-run=client -o yaml | kubectl apply -f -

# Apply additional istio config and create application namespaces
cd ../
kubectl apply -k .

# show duration
duration=$SECONDS
echo "$((duration / 60)) minutes and $((duration % 60)) seconds elapsed."
