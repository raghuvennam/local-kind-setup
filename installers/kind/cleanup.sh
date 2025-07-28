#!/bin/bash

if [ "$(kind get clusters | grep -wc local)" -eq 1 ]; then
  # delete kind cluster
  echo -e "\nDeleting local kind cluster\n"
  kind delete cluster --name local || true
  sleep 5
else
  echo -e "\nNo local kind cluster found for cleanup, no action taken\n"
fi
