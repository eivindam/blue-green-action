#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOY_PATH=$2
BRANCH_NAME=$(echo $GITHUB_REF | cut -d'/' -f 3)
GITHUB_SHA_SHORT=$(echo $GITHUB_SHA | cut -c1-7)
VERSION=${GITHUB_SHA_SHORT}
NAMESPACE=default
DEPLOY_NAME=websocket

# Setup AWS Config
aws configure --profile test_deploy <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_REGION}
text
EOF

# Setup kubernetes config
mkdir ~/.kube/
echo $KUBE_CONFIG | base64 -d > ~/.kube/config

# Deploy
CURRENT_VERSION=$(kubectl get service $DEPLOY_NAME -o=jsonpath='{.spec.selector.version}' --namespace=${NAMESPACE})

if [ "$CURRENT_VERSION" == "$VERSION" ]; then
   echo "[DEPLOY] Both versions are the same: $VERSION"
   exit 0
fi

kubectl get deployment $DEPLOY_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f -
kubectl rollout status deployment/$DEPLOY_NAME --namespace=${NAMESPACE}

sleep 10

echo "[DEPLOY] $(kubectl get pods -l version="$VERSION" -n $NAMESPACE --no-headers)"

#activate kubectl get service $SERVICE_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$DEPLOY_VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f - 
