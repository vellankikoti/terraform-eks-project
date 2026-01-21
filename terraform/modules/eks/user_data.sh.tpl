#!/bin/bash
set -ex

# Bootstrap EKS node
/etc/eks/bootstrap.sh ${cluster_name} ${bootstrap_arguments}
