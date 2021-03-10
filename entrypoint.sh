#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOYMENT_NAME=$2
SERVICE_NAME=$3
NAMESPACE=$4
ACCEPTED_RESTARTS=$5
RESTART_WAIT=$6
VERSION=$7
DESTROY_OLD=1
DESTROY_FAILED=1
MODE=color
COLOR_EVEN=blue
COLOR_ODD=green

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
CURRENT_VERSION=$(kubectl get service $SERVICE_NAME -o=jsonpath='{.spec.selector.version}' --namespace=${NAMESPACE})

if [ "$CURRENT_VERSION" == "" ]; then
    echo "[DEPLOY] The service $DEPLOYMENT_NAME is missing, or another error occurred"

    exit 1
fi

if [ "$CURRENT_VERSION" == "$VERSION" ]; then
   echo "[DEPLOY] Both versions are the same: $VERSION"
   exit 0
fi

if [ $MODE == "color" ]; then    
    DESTROY_OLD=0
    DESTROY_FAILED=0
    
    POD_NAME=$(kubectl get pods --selector=version=$CURRENT_VERSION -o jsonpath='{.items[0].metadata.generateName}')

    if [ "$POD_NAME" =~ "$COLOR_EVEN" ]; then
        COLOR="$COLOR_ODD"
    else
        COLOR="$COLOR_EVEN"
    fi

    DEPLOY_NAME="$DEPLOYMENT_NAME-$COLOR"
else
    DEPLOY_NAME="$DEPLOYMENT_NAME-$CURRENT_VERSION"
fi

# Verify that deployment exists and get YAML definition
DEPLOY_YAML=$(kubectl get deployment $DEPLOY_NAME -o=yaml --namespace=${NAMESPACE})

if [ "$DEPLOY_YAML" == "" ]; then
    echo "[DEPLOY] The deployment $DEPLOY_NAME is missing, or another error occurred"

    exit 1
fi
# Rollout new version
echo $DEPLOY_YAML | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f -
kubectl rollout status deployment/$DEPLOY_NAME --namespace=${NAMESPACE}

# Wait for restarts
echo "[DEPLOY] Rollout done. Waiting $RESTART_WAIT seconds for restarts..."

sleep $RESTART_WAIT

# Check restarts
RESTARTS=$(kubectl get pods -l version="$VERSION" -n ${NAMESPACE} --no-headers -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | awk '{s+=$1}END{print s}')

if [ "$RESTARTS" -gt "$ACCEPTED_RESTARTS" ]; then
    # Unhealty, give some debug output and delete deployment    
    echo "[DEPLOY] $VERSION is unhealthy, removing version"
    echo "[DEPLOY] $(kubectl describe pods -l version="$VERSION" -n $NAMESPACE)"

    if [ "$DESTROY_OLD" != "" && "$DESTROY_OLD" != "0"]; then
        echo "[DEPLOY] Removing old version $CURRENT_VERSION"
        kubectl delete deployment $DEPLOY_NAME --namespace=${NAMESPACE}
    fi

    exit 1
else
    # Healty, activate version in service
    echo "[DEPLOY] Activating version $VERSION in service"
    kubectl get service $SERVICE_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f - 

    if []"$DESTROY_OLD" != "" && "$DESTROY_OLD" != "0"]; then
        echo "[DEPLOY] Removing old version $CURRENT_VERSION"
        kubectl delete deployment $DEPLOY_NAME --namespace=${NAMESPACE} 
    fi

    echo "[DEPLOY] $(kubectl get pods -l version="$VERSION" -n $NAMESPACE)"

    exit 0
fi
