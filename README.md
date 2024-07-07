kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
from https://tekton.dev/docs/installation/pipelines/

kubectl apply --filename https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml
from https://tekton.dev/docs/chains/

from: https://tekton.dev/docs/dashboard/install/#installing-tekton-dashboard-on-kubernetes
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml
kubectl --namespace tekton-pipelines port-forward svc/tekton-dashboard 9097:9097

from: https://tekton.dev/docs/chains/authentication/
export NAMESPACE=default
export SERVICE_ACCOUNT_NAME=default
kubectl create secret generic docker-registry \
    --from-file=.dockerconfigjson=/Users/mmortari/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson \
    -n $NAMESPACE
kubectl patch serviceaccount $SERVICE_ACCOUNT_NAME \
  -p "{\"secrets\": [{\"name\": \"docker-registry\"}]}" -n $NAMESPACE

podman build -t quay.io/mmortari/demo20240704-mltrain-as-oci -f Containerfile .
podman push quay.io/mmortari/demo20240704-mltrain-as-oci

kubectl apply -f oml-chains.yml

DOCKERCONFIG_SECRET_NAME=dockerconfig-secret-name
tkn task start --use-param-defaults --workspace name=source,emptyDir="" --workspace name=dockerconfig,secret=$DOCKERCONFIG_SECRET_NAME oml-chains
