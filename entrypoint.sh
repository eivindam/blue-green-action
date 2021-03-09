#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOY_PATH=$2
BRANCH_NAME=$(echo $GITHUB_REF | cut -d'/' -f 3)
GITHUB_SHA_SHORT=$(echo $GITHUB_SHA | cut -c1-7)
VERSION=${GITHUB_SHA_SHORT}
NAMESPACE=default
DEPLOY_NAME=websocket
SERVICE_NAME=websocket
ACCEPTED_RESTARTS=1
ROLLOUT_SLEEP=10

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

kubectl get deployment $DEPLOY_NAME-$CURRENT_VERSION -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f -
kubectl rollout status deployment/$DEPLOY_NAME-$VERSION --namespace=${NAMESPACE}

sleep $ROLLOUT_SLEEP

RESTARTS=$(kubectl get pods -l version="$VERSION" -n default --no-headers -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | awk '{s+=$1}END{print s}')

if [ "$RESTARTS" -gt "$ACCEPTED_RESTARTS" ]; then
   echo "[DEPLOY] $VERSION is unhealthy, removing version"
   echo "[DEPLOY] $(kubectl describe pods -l version="$VERSION" -n $NAMESPACE)"

   kubectl delete deployment $DEPLOY_NAME-$VERSION --namespace=${NAMESPACE}
else
   echo "[DEPLOY] Activating version $VERSION in service"
   kubectl get service $SERVICE_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f - 
     
   echo "[DEPLOY] Removing old version $CURRENT_VERSION"
   kubectl delete deployment $DEPLOY_NAME-$CURRENT_VERSION --namespace=${NAMESPACE} 

   echo "[DEPLOY] $(kubectl get pods -l version="$VERSION" -n $NAMESPACE)"
fi


