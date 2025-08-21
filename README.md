# local-kind-setup

> [!NOTE]
>
> This setup is developed to work on Apple MacBook and will need further updates to run similar setup on windows

## Pre-requisites

Below are pre-requisites needed for MacBook

1. Install [homebrew](https://brew.sh/)
2. Install latest version of [docker desktop](https://www.docker.com/products/docker-desktop/)
3. Install make, kind, stern, skaffold, kubectl, kubectx, helm via brew _(if not already installed)_

```sh
# remove any components already install from list below
brew install make kind stern skaffold kubernetes-cli kubectx helm

# (optional) disable skaffold metric collection
skaffold config set --global collect-metrics false

# (optional) disable skaffold update checking
skaffold config set --global update-check false
```

> [!NOTE]
>
> This guide does not cover the local devtools needed to build the code as it's not in scope of this setup such as jdk, gradle, ide(s), etc ...

## Setup instructions

From the [developer-setup](../developer-setup) folder under `docs`, run the below command to setup
the local environment

```sh
# to use latest version of kubernetes and istio
make install

# to use a specific version of kubernetes and istio, close to the version where application is to be deployed
# refer to https://hub.docker.com/r/kindest/node/tags for supported tags
# refer to https://github.com/istio/istio/releases for supported versions
make install KIND_VERSION=v1.27.3 ISTIO_VERSION=1.20.2

# to cleanup and start with a fresh cluster
make install CLEAN=true

# to cleanup and start with a fresh cluster with specific version
make install KIND_VERSION=v1.27.3 ISTIO_VERSION=1.20.2 CLEAN=true

# to delete the local kind cluster without creating a new one use
# all data stored on the kind cluster will be deleted (including any databases)
make cleanup
```

### Components installed as part of setup

The setup provides one step installation of below components

- [kind](https://kind.sigs.k8s.io/) cluster setup on Docker
- [kubernetes dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/)
- [istio](https://istio.io/latest/docs/)

### Validation

Once the installation is complete you should be able to see the available kubernetes context

```sh
# check if the kind container is running in docker
docker ps | grep kind

# check the new kubernetes context created
kubectx | grep -i kind

# use the below command to set context to use kubectl
kubectx kind-local

# edit the hosts file and add the below entry
sudo vi /etc/hosts

127.0.0.1 kind-registry api.internal web.internal
```

To access the kubernetes dashboard

```sh
# retrieve the admin user token from the kubernetes secret and save it for future use
kubectl get secret admin-user -n kubernetes-dashboard -o jsonpath={".data.token"} | base64 -d

# on a new terminal run the below command, this terminal needs to be running and can't be reused
kubectl proxy
```

Once the proxy has started use this [link](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/workloads?namespace=_all)

> [!NOTE]
>
> Incase of issues cross check if browser is redirecting to `https` as the dashboard is currently `http` only
>
> Dashboard secret token is only valid as long as the cluster is not cleaned/deleted, in case a new cluster is created you need to retrieve the token again
