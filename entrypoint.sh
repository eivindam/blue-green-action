#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOYMENT_NAME=$2
SERVICE_NAME=$3
NAMESPACE=$4
ROLLOUT_ACCEPTED_RESTARTS=$5
RESTART_WAIT=$6
VERSION=$7

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

# Check current version
CURRENT_VERSION=$(kubectl get service $DEPLOYMENT_NAME -o=jsonpath='{.spec.selector.version}' --namespace=${NAMESPACE})

if [ "$CURRENT_VERSION" == "$VERSION" ]; then
   echo "[DEPLOY] Both versions are the same: $VERSION"
   exit 0
fi

# Rollout new version
kubectl get deployment $DEPLOYMENT_NAME-$CURRENT_VERSION -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f -
kubectl rollout status deployment/$DEPLOYMENT_NAME-$VERSION --namespace=${NAMESPACE}

# Wait for restarts
echo "[DEPLOY] Rollout done. Waiting $RESTART_WAIT seconds for restarts..."

sleep $RESTART_WAIT

# Check restarts
RESTARTS=$(kubectl get pods -l version="$VERSION" -n ${NAMESPACE} --no-headers -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | awk '{s+=$1}END{print s}')

if [ "$RESTARTS" -gt "$ACCEPTED_RESTARTS" ]; then
    # Unhealty, give some debug output and delete deployment    
    echo "[DEPLOY] $VERSION is unhealthy, removing version"
    echo "[DEPLOY] $(kubectl describe pods -l version="$VERSION" -n $NAMESPACE)"

    kubectl delete deployment $DEPLOYMENT_NAME-$VERSION --namespace=${NAMESPACE}

    exit 1
else
    # Healty, activate version in service
    echo "[DEPLOY] Activating version $VERSION in service"
    kubectl get service $SERVICE_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f - 
     
    echo "[DEPLOY] Removing old version $CURRENT_VERSION"
    kubectl delete deployment $DEPLOYMENT_NAME-$CURRENT_VERSION --namespace=${NAMESPACE} 

    echo "[DEPLOY] $(kubectl get pods -l version="$VERSION" -n $NAMESPACE)"

    exit 0
fi


