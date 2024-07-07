podman build -t quay.io/mmortari/demo20240704-mltrain-as-oci -f Containerfile .
podman push quay.io/mmortari/demo20240704-mltrain-as-oci

kubectl apply -f oml-chains.yml

DOCKERCONFIG_SECRET_NAME=dockerconfig-secret-name
tkn task start --use-param-defaults --workspace name=source,emptyDir="" --workspace name=dockerconfig,secret=$DOCKERCONFIG_SECRET_NAME oml-chains
