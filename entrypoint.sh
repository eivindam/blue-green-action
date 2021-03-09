#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOY_PATH=$2

mkdir ~/.kube/
mkdir ~/.aws/

aws configure --profile test_deploy <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_REGION}
text
EOF

echo $KUBE_CONFIG | base64 -d > ~/.kube/config

kubectl apply -f $DEPLOY_PATH
