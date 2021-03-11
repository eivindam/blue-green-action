#!/bin/bash

set -x

KUBE_CONFIG=$1
DEPLOYMENT_NAME=$2
SERVICE_NAME=$3
NAMESPACE=$4
ACCEPTED_RESTARTS=$5
RESTART_WAIT=$6
VERSION=$7
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

echo "[DEPLOY] Checking active version.."

# Check current version
CURRENT_VERSION=$(kubectl get service ${SERVICE_NAME} -o=jsonpath='{.spec.selector.version}' -n ${NAMESPACE})

if [[ "${CURRENT_VERSION}" == "" ]]; then
    echo "[DEPLOY] The service ${SERVICE_NAME} is missing, or another error occurred"

    exit 1
else
    echo "[DEPLOY] The active version for ${SERVICE_NAME} is ${CURRENT_VERSION}"
fi

if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
   echo "[DEPLOY] The version is already active inn the service: ${VERSION}"

   exit 0
fi

POD_NAME=$(kubectl get pods --selector=version=${CURRENT_VERSION} -o jsonpath='{.items[*].metadata.generateName}' | head -1)

if [[ "${POD_NAME}" == *"${COLOR_EVEN}"* ]]; then
    NEW_COLOR="${COLOR_ODD}"
    OLD_COLOR="${COLOR_EVEN}"
else
    NEW_COLOR="${COLOR_EVEN}"
    OLD_COLOR="${COLOR_ODD}"
fi

OLD_NAME="${DEPLOYMENT_NAME}-${OLD_COLOR}"
NEW_NAME="${DEPLOYMENT_NAME}-${NEW_COLOR}"

# Verify that current deployment exists and get YAML definition
OLD_YAML=$(kubectl get deployment ${OLD_NAME} -o=yaml -n ${NAMESPACE})

if [[ "${OLD_YAML}" == "" ]]; then
    echo "[DEPLOY] The deployment ${OLD_NAME} is missing, or another error occurred"

    exit 1
fi

# Check for the new deployment. Create it if it doesn't exist, or patch it with version to redeploy.
NEW_YAML=$(kubectl get deployment ${NEW_NAME} -o=yaml -n ${NAMESPACE})

if [[ "${NEW_YAML}" == "" ]]; then
    echo "[DEPLOY] Creating new deployment for ${NEW_NAME} based on ${OLD_NAME}"
   
    echo "${OLD_YAML}" | sed -e "s/${CURRENT_VERSION}/${VERSION}/g" | sed -e "s/${OLD_COLOR}/${NEW_COLOR}/g" | kubectl apply -n ${NAMESPACE} -f -
else
    echo "[DEPLOY] Patching deployment ${NEW_NAME} with version ${VERSION}. This triggers a redeploy."
    
    kubectl patch deployment ${NEW_NAME} -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"version\": \"${VERSION}\"}}}}}"
fi

echo "[DEPLOY] Waiting for rollout..."

kubectl rollout status deployment ${NEW_NAME} -n ${NAMESPACE}

# Wait for restarts
echo "[DEPLOY] Rollout done. Waiting ${RESTART_WAIT} seconds for restarts..."

sleep $RESTART_WAIT

# Check restarts
RESTARTS=$(kubectl get pods -l version="${VERSION}" -n ${NAMESPACE} --no-headers -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' | awk '{s+=$1}END{print s}')

if [[ "${RESTARTS}" -gt "${ACCEPTED_RESTARTS}" ]]; then
    # Unhealty, give some debug output and delete deployment    
    echo "[DEPLOY] ${NEW_NAME} with version ${VERSION} is unhealthy. The service will not be changed."
    echo "[DEPLOY] Pods:"

    echo "$(kubectl describe pods -l version="${VERSION}" -n ${NAMESPACE})"

    exit 1
else
    # Healty, activate version in service
    echo "[DEPLOY] ${NEW_NAME} with version ${VERSION} is healthy, activating in service"
    #kubectl get service $SERVICE_NAME -o=yaml --namespace=${NAMESPACE} | sed -e "s/$CURRENT_VERSION/$VERSION/g" | kubectl apply --namespace=${NAMESPACE} -f - 
    kubectl patch svc ${SERVICE_NAME} -p "{\"spec\":{\"selector\": {\"version\": \"${VERSION}\"}}}"

    echo "[DEPLOY] Pods:"
    
    echo "$(kubectl get pods -l version="${VERSION}" -n ${NAMESPACE})"

    exit 0
fi
