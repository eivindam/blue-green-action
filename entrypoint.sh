#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOY_PATH=$2

mkdir ~/.kube/
mkdir ~/.aws/

#printf "[profile test_deploy]\nregion=%s\n" > ~/.aws/config
#printf "[test_deploy]\naws_access_key_id=%s\naws_secret_access_key=%s\n" $AWS_REGION $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY > ~/.aws/credentials

aws configure set default.region "eu-west-1"

echo $KUBE_CONFIG | base64 -d > ~/.kube/config

kubectl apply -f $DEPLOY_PATH
