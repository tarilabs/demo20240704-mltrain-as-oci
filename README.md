# Using a Tekton chain Task

```
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

(from https://tekton.dev/docs/installation/pipelines)

```
kubectl apply --filename https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml
```

(from https://tekton.dev/docs/chains)

```
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml
kubectl --namespace tekton-pipelines port-forward svc/tekton-dashboard 9097:9097
```

(from https://tekton.dev/docs/dashboard/install/#installing-tekton-dashboard-on-kubernetes)

```
export NAMESPACE=default
export SERVICE_ACCOUNT_NAME=default
kubectl create secret generic docker-registry \
    --from-file=.dockerconfigjson=/Users/mmortari/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson \
    -n $NAMESPACE
kubectl patch serviceaccount $SERVICE_ACCOUNT_NAME \
  -p "{\"secrets\": [{\"name\": \"docker-registry\"}]}" -n $NAMESPACE
```

(from https://tekton.dev/docs/chains/authentication/)

```
podman build -t quay.io/mmortari/demo20240704-mltrain-as-oci -f Containerfile .
podman push quay.io/mmortari/demo20240704-mltrain-as-oci
```

```
kubectl apply -f oml-chains.yml
```

```
DOCKERCONFIG_SECRET_NAME=dockerconfig-secret-name
tkn task start --use-param-defaults --workspace name=source,emptyDir="" --workspace name=dockerconfig,secret=$DOCKERCONFIG_SECRET_NAME oml-chains
```

## Hacking

Use the commands below to build. NOTE: If you're not `lucarval` then you'll likely need to change
some of the values below. The image ref provided to the podman commands matches the image used in
the `oml-chains` Task. Don't forget to update that as well.

```bash
podman build -t quay.io/lucarval/mltrain:latest . && \
podman push quay.io/lucarval/mltrain:latest && \
kubectl apply -f oml-chains.yml && \
tkn pipeline start -f ./oml-pipeline.yml \
  --param IMAGE=quay.io/lucarval/demo-oml:latest \
  --param DATASET=quay.io/mmortari/ml-iris:data --showlog
```

Once the Pipeline completes, use `tkn pipelinerun describe` to inspect the results. You can also use
`tkn taskrun describe` to inspect the results of the underlying TaskRun. The `IMAGE` parameter is
where the model image is pushed to. The TaskRun and PipelineRun results provide the exact digest.

Verify the image was signed and attested:

```bash
🐚 cosign tree quay.io/lucarval/demo-oml:latest
📦 Supply Chain Security Related artifacts for an image: quay.io/lucarval/demo-oml:latest
└── 💾 Attestations for an image tag: quay.io/lucarval/demo-oml:sha256-085f8f536cdbc1befdb80e99378dee6cc1cdb651c4db10e07b7bc9e887bc4773.att
   ├── 🍒 sha256:e807f5d07cfd412e6c18652379f198a0f4f011094741add888f1c6a0705a6178
   └── 🍒 sha256:ce4ca67474f1a7a76ac3c651028df7834602b37f11171aaa3afc685d185e56c4
└── 🔐 Signatures for an image tag: quay.io/lucarval/demo-oml:sha256-085f8f536cdbc1befdb80e99378dee6cc1cdb651c4db10e07b7bc9e887bc4773.sig
   └── 🍒 sha256:0206c381dde15e5be640c4977e90b9cd3726b660aa9c781697839a4f034777a8
```

There are two attestations. One for the TaskRun and one for the PipelineRun. The PipelineRun
attestation contains additional information, including the result of each TaskRun. For this reason
Enterprise Contract in Konflux only uses the PipelineRun attestation.

NOTE: Depending on your Tekton Chains configuration, you may only see one attestation. In Konflux,
for example, generating attestation for the TaskRun is disabled.

To inspect the contents of the SLSA Provenance attesattion for the PipelineRun, use the following:

```bash
cosign download attestation quay.io/lucarval/demo-oml:latest \
  | jq '.payload | @base64d | fromjson | select(.predicate.buildType == "tekton.dev/v1beta1/PipelineRun")'
```

Notice how it is also possible to determine the exact dataset used during training.

NOTE: `cosign download` does not verify the data has not been tampered with. It's good enough for
exploratory work. Production workflows should always access this data via something like
`cosign verify-attestation`.

You can also use [Enterprise Contract](https://enterprisecontract.dev/) to verify the image is
signed, it has an assocaited SLSA Provenance attestation, and more. Use the script
[check.sh](policy/check.sh) for this.

NOTE: Modify the ruleData in [config.yaml](policy/config.yaml) to see what a failure looks like.

The image signatures that EC verifies are [Sigstore](https://www.sigstore.dev/) based signatures.
There are [different ways](https://blog.sigstore.dev/adopting-sigstore-incrementally-1b56a69b8c15/)
of using Sigstore. For simplicity sake, the test model image built from this repo was signed with a
long-lived key without Rekor integration. This means that we need to provide the public key when
validating the image with EC. Furthermore, the *private* key is never really stored anywhere. So if
running through the process of building the image again, a new key pair will be created. As such,
update the public key in the [check.sh](policy/check.sh) script. The public key is referring to the
file `cosign.pub` when executing: `cosign generate-key-pair k8s://tekton-chains/signing-secrets`from
the tutorial: <https://tekton.dev/docs/chains/signed-provenance-tutorial/#generate-a-key-pair>
