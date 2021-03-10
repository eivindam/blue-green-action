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

if [[ "$CURRENT_VERSION" == "" ]]; then
    echo "[DEPLOY] The service $DEPLOYMENT_NAME is missing, or another error occurred"

    exit 1
fi

if [[ "$CURRENT_VERSION" == "$VERSION" ]]; then
   echo "[DEPLOY] Both versions are the same: $VERSION"
   exit 0
fi

if [[ $MODE == "color" ]]; then    
    DESTROY_OLD=0
    DESTROY_FAILED=0
    
    POD_NAME=$(kubectl get pods --selector=version=$CURRENT_VERSION -o jsonpath='{.items[*].metadata.generateName}' | head -1)

    if [[ "$POD_NAME" == *"$COLOR_EVEN"* ]]; then
        NEW_COLOR="$COLOR_ODD"
        OLD_COLOR="$COLOR_EVEN"
    else
        NEW_COLOR="$COLOR_EVEN"
        OLD_COLOR="$COLOR_ODD"
    fi

    OLD_NAME="$DEPLOYMENT_NAME-$OLD_COLOR"
    NEW_NAME="$DEPLOYMENT_NAME-$NEW_COLOR"
else
    OLD_NAME="$DEPLOYMENT_NAME-$CURRENT_VERSION"
    NEW_NAME="$DEPLOYMENT_NAME-$VERSION"
fi

# Verify that deployment exists and get YAML definition
OLD_YAML=$(kubectl get deployment $OLD_NAME -o=yaml --namespace=${NAMESPACE})

if [[ "$OLD_YAML" == "" ]]; then
    echo "[DEPLOY] The deployment $OLD_NAME is missing, or another error occurred"

    exit 1
fi

NEW_YAML=$(kubectl get deployment $NEW_NAME -o=yaml --namespace=${NAMESPACE})

if [[ "NEW_YAML" == "" ]]; then
    echo "${OLD_YAML}" | sed -e "s/$CURRENT_VERSION/$VERSION/g" | sed -e "s/$OLD_COLOR/$NEW_COLOR/g" | kubectl apply --namespace=${NAMESPACE} -f -
else
    echo "${NEW_YAML}" | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f -
fi

kubectl rollout status deployment/$NEW_NAME --namespace=${NAMESPACE}

# Wait for restarts
echo "[DEPLOY] Rollout done. Waiting $RESTART_WAIT seconds for restarts..."

sleep $RESTART_WAIT

# Check restarts
RESTARTS=$(kubectl get pods -l version="$VERSION" -n ${NAMESPACE} --no-headers -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | awk '{s+=$1}END{print s}')

if [[ "$RESTARTS" -gt "$ACCEPTED_RESTARTS" ]]; then
    # Unhealty, give some debug output and delete deployment    
    echo "[DEPLOY] $VERSION is unhealthy, removing version"
    echo "[DEPLOY] $(kubectl describe pods -l version="$VERSION" -n $NAMESPACE)"

    if [[ "$DESTROY_OLD" != "" && "$DESTROY_OLD" != "0" ]]; then
        echo "[DEPLOY] Removing old version $CURRENT_VERSION"
        kubectl delete deployment $OLD_NAME --namespace=${NAMESPACE}
    fi

    exit 1
else
    # Healty, activate version in service
    echo "[DEPLOY] Activating version $VERSION in service"
    kubectl get service $SERVICE_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f - 

    if [[ "$DESTROY_OLD" != "" && "$DESTROY_OLD" != "0" ]]; then
        echo "[DEPLOY] Removing old version $CURRENT_VERSION"
        kubectl delete deployment $OLD_NAME --namespace=${NAMESPACE} 
    fi

    echo "[DEPLOY] $(kubectl get pods -l version="$VERSION" -n $NAMESPACE)"

    exit 0
fi
