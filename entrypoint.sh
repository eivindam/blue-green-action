#!/bin/bash

KUBE_CONFIG=$1
DEPLOY_PATH=$2

mkdir ~/.kube/
echo $KUBE_CONFIG | base64 --decode > ~/.kube/config

kubectl apply -f $DEPLOY_PATH
