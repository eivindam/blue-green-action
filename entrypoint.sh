#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOY_PATH=$2

mkdir ~/.kube/
echo $KUBE_CONFIG | base64 -D > ~/.kube/config

kubectl apply -f $DEPLOY_PATH
