## Preparation

```sh
kind create cluster
```

## Using a Tekton chain Task

```sh
kubectl apply --filename https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

(from https://tekton.dev/docs/installation/pipelines)

```sh
kubectl apply --filename https://storage.googleapis.com/tekton-releases/chains/latest/release.yaml
```

(from https://tekton.dev/docs/chains)

```sh
cosign generate-key-pair k8s://tekton-chains/signing-secrets
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.format": "slsa/v1"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.storage": "oci"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.format": "slsa/v1"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.storage": "oci"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.storage": "oci"}}'
kubectl delete po -n tekton-chains -l app=tekton-chains-controller
```

(from https://tekton.dev/docs/chains/signing/#generate-cosign-keypair)<br/>
(from https://tekton.dev/docs/chains/signed-provenance-tutorial/#configuring-tekton-chains)

```sh
kubectl apply --filename https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml
kubectl wait --for=condition=Available=True deployment/tekton-dashboard --namespace tekton-pipelines
kubectl --namespace tekton-pipelines port-forward svc/tekton-dashboard 9097:9097
```

(from https://tekton.dev/docs/dashboard/install/#installing-tekton-dashboard-on-kubernetes)

```sh
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

```sh
podman build -t quay.io/mmortari/demo20240704-mltrain-as-oci -f Containerfile .
podman push quay.io/mmortari/demo20240704-mltrain-as-oci
```

```sh
kubectl apply -f oml-chains.yml
```

```sh
DOCKERCONFIG_SECRET_NAME=dockerconfig-secret-name
tkn task start --use-param-defaults oml-chains
```

## Using a Tekton chain Pipeline

Use the commands below to build. NOTE: If you're not `mmortari` then you'll likely need to change
some of the values below. The image ref provided to the podman commands matches the image used in
the `oml-chains` Task. Don't forget to update that as well.

Build image and apply `oml-chains.yml` like above; then:

```sh
tkn pipeline start -f ./oml-pipeline.yml --use-param-defaults --showlog
```

Once the Pipeline completes, use `tkn pipelinerun describe --last` to inspect the results. 

<details>

```
% tkn pipelinerun describe --last        
Name:              oml-chains-run-hdfv6
Namespace:         default
Service Account:   default
Labels:
 tekton.dev/pipeline=oml-chains-run-hdfv6
Annotations:
 chains.tekton.dev/signed=true

🌡️  Status

STARTED         DURATION   STATUS
9 minutes ago   13s        Succeeded

⏱  Timeouts
 Pipeline:   1h0m0s

📝 Results

 NAME             VALUE
 ∙ IMAGE_URL      quay.io/mmortari/ml-iris:v1
 ∙ IMAGE_DIGEST   sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de

🗂  Taskruns

 NAME                                    TASK NAME        STARTED         DURATION   STATUS
 ∙ oml-chains-run-hdfv6-train-and-push   train-and-push   9 minutes ago   13s        Succeeded
```

</details>

You can also use `tkn taskrun describe --last` to inspect the results of the underlying TaskRun.
The `IMAGE` parameter is where the model image is pushed to. The TaskRun and PipelineRun results provide the exact digest.

Verify the image was signed and attested:

```
% cosign tree quay.io/mmortari/ml-iris:v1
📦 Supply Chain Security Related artifacts for an image: quay.io/mmortari/ml-iris:v1
└── 💾 Attestations for an image tag: quay.io/mmortari/ml-iris:sha256-bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de.att
   ├── 🍒 sha256:6e97706d3a96cd963783f0e1cacaa5f5ce9bc2e53b8deba4e1ce247b27bb04ec
   └── 🍒 sha256:de7349f5888fce2fea1e3d13b61bc5300b507417328aff982f24b35ec7c52152
└── 🔐 Signatures for an image tag: quay.io/mmortari/ml-iris:sha256-bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de.sig
   └── 🍒 sha256:2e844aa2f8da542cdcaac5d89b0c569d651e87e8593ce4e99bc4dbf52f5b3f94
```

There are two attestations. One for the TaskRun and one for the PipelineRun. The PipelineRun
attestation contains additional information, including the result of each TaskRun. For this reason
Enterprise Contract in Konflux only uses the PipelineRun attestation.

NOTE: Depending on your Tekton Chains configuration, you may only see one attestation. In Konflux,
for example, generating attestation for the TaskRun is disabled.

To inspect the contents of the SLSA Provenance attesattion for the PipelineRun, use the following:

```sh
cosign download attestation quay.io/mmortari/ml-iris:v1 \
  | jq '.payload | @base64d | fromjson | select(.predicate.buildType == "tekton.dev/v1beta1/PipelineRun")'
```

Notice how it is also possible to determine the exact dataset used during training.

<details>

```json
{
  "_type": "https://in-toto.io/Statement/v0.1",
  "subject": [
    {
      "name": "quay.io/mmortari/ml-iris",
      "digest": {
        "sha256": "bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de"
      }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v0.2",
  "predicate": {
    "buildConfig": {
      "tasks": [
        {
          "finishedOn": "2024-10-09T15:54:22Z",
          "invocation": {
            "configSource": {},
            "environment": {
              "annotations": {
                "pipeline.tekton.dev/release": "575b35c"
              },
              "labels": {
                "app.kubernetes.io/managed-by": "tekton-pipelines",
                "tekton.dev/memberOf": "tasks",
                "tekton.dev/pipeline": "oml-chains-run-hdfv6",
                "tekton.dev/pipelineRun": "oml-chains-run-hdfv6",
                "tekton.dev/pipelineRunUID": "d71eb56d-318a-4abe-ad77-0f7988b7e92f",
                "tekton.dev/pipelineTask": "train-and-push",
                "tekton.dev/task": "oml-chains"
              }
            },
            "parameters": {
              "DATASET": "quay.io/mmortari/ml-iris:data",
              "IMAGE": "quay.io/mmortari/ml-iris:v1"
            }
          },
          "name": "train-and-push",
          "ref": {
            "kind": "Task",
            "name": "oml-chains"
          },
          "results": [
            {
              "name": "DATASET_DIGEST",
              "type": "string",
              "value": "sha256:9349eb335373d375596456aa9faf2838a73a7e3d4dcedbd338c548091b919dee"
            },
            {
              "name": "DATASET_URL",
              "type": "string",
              "value": "quay.io/mmortari/ml-iris:data"
            },
            {
              "name": "IMAGE_DIGEST",
              "type": "string",
              "value": "sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de"
            },
            {
              "name": "IMAGE_URL",
              "type": "string",
              "value": "quay.io/mmortari/ml-iris:v1"
            }
          ],
          "serviceAccountName": "default",
          "startedOn": "2024-10-09T15:54:09Z",
          "status": "Succeeded",
          "steps": [
            {
              "annotations": null,
              "arguments": null,
              "entryPoint": "# Resolve the dataset ref to a digest.\n# TODO: Handle the case where DATASET already contains a digest.\nDATASET_DIGEST=\"$(skopeo inspect --raw \"docker://${DATASET}\" | sha256sum | awk '{printf \"sha256:\"$1}')\"\n\necho -n \"${DATASET_DIGEST}\" | tee /tekton/results/DATASET_DIGEST && echo\necho -n \"${DATASET}\" | tee /tekton/results/DATASET_URL && echo\n\npython /app/train_model.py --image \"${IMAGE}\" \\\n  --dataset \"${DATASET}@${DATASET_DIGEST}\" \\\n  --results-image-url-path /tekton/results/IMAGE_URL \\\n  --results-image-digest-path /tekton/results/IMAGE_DIGEST\n\necho \"Out of py.\"\ncat /tekton/results/IMAGE_URL\necho\ncat /tekton/results/IMAGE_DIGEST\necho\n\necho \"Re-doing with skopeo...\"\nskopeo inspect --raw \"docker://${IMAGE}\" | sha256sum | awk '{printf \"sha256:\"$1}' | tee /tekton/results/IMAGE_DIGEST\necho \"\"\necho -n \"${IMAGE}\" | tee /tekton/results/IMAGE_URL\necho \"\"\n",
              "environment": {
                "container": "oml-train-and-push",
                "image": "oci://quay.io/mmortari/demo20240704-mltrain-as-oci@sha256:eb8792686df4a9dd6c2c261d226dbffb2e7289780ee91fd4fdeea8ace6706693"
              }
            }
          ]
        }
      ]
    },
    "buildType": "tekton.dev/v1beta1/PipelineRun",
    "builder": {
      "id": "https://tekton.dev/chains/v2"
    },
    "invocation": {
      "configSource": {},
      "environment": {
        "labels": {
          "tekton.dev/pipeline": "oml-chains-run-hdfv6"
        }
      },
      "parameters": {
        "DATASET": "quay.io/mmortari/ml-iris:data",
        "IMAGE": "quay.io/mmortari/ml-iris:v1"
      }
    },
    "materials": [
      {
        "digest": {
          "sha256": "eb8792686df4a9dd6c2c261d226dbffb2e7289780ee91fd4fdeea8ace6706693"
        },
        "uri": "oci://quay.io/mmortari/demo20240704-mltrain-as-oci"
      }
    ],
    "metadata": {
      "buildFinishedOn": "2024-10-09T15:54:22Z",
      "buildStartedOn": "2024-10-09T15:54:09Z",
      "completeness": {
        "environment": false,
        "materials": false,
        "parameters": false
      },
      "reproducible": false
    }
  }
}
```

</details>

NOTE: `cosign download` does not verify the data has not been tampered with. It's good enough for
exploratory work. Production workflows should always access this data via something like
`cosign verify-attestation`.

## Enterprise Contract

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
