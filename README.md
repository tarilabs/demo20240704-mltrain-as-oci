## Preparation

```sh
kind create cluster
```

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
```

(from https://tekton.dev/docs/chains/signing/#generate-cosign-keypair)

--- 

OPTIONAL, to save key+psw locally

```sh
kubectl get secret signing-secrets -n tekton-chains -o jsonpath="{.data['cosign\.key']}" | base64 --decode > cosign.key
kubectl get secret signing-secrets -n tekton-chains -o jsonpath="{.data['cosign\.password']}" | base64 --decode > cosign.password
```

to restore:

```sh
kubectl create secret generic signing-secrets2 \
    --from-file=./cosign.key \
    --from-file=./cosign.password \
    --from-file=./cosign.pub
```

----

CONTINUES:

```sh
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.format": "slsa/v1"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.taskrun.storage": "oci"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.format": "slsa/v1"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.pipelinerun.storage": "oci"}}'
kubectl patch configmap chains-config -n tekton-chains -p='{"data":{"artifacts.oci.storage": "oci"}}'
kubectl delete pod -n tekton-chains -l app=tekton-chains-controller
```

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

## Using a Tekton chain Task

```sh
kubectl apply -f omlmd-chains.yml
```

```sh
DOCKERCONFIG_SECRET_NAME=dockerconfig-secret-name
tkn task start --use-param-defaults omlmd-chains
```

## Using a Tekton chain Pipeline

Use the commands below to build. NOTE: If you're not `mmortari` then you'll likely need to change
some of the values below. The image ref provided to the podman commands matches the image used in
the `omlmd-chains` Task. Don't forget to update that as well.

Build image and apply `omlmd-chains.yml` like above; then:

```sh
tkn pipeline start -f ./omlmd-pipeline.yml --use-param-defaults --showlog
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
exploratory work.

Production workflows must verify this data with `cosign verify-attestation`.

<details>

Example:

```
% cosign verify-attestation quay.io/mmortari/ml-iris:v1 --insecure-ignore-tlog=true --key cosign.pub --type="slsaprovenance"                          
WARNING: Skipping tlog verification is an insecure practice that lacks of transparency and auditability verification for the attestation.

Verification for quay.io/mmortari/ml-iris:v1 --
The following checks were performed on each of these signatures:
  - The cosign claims were validated
  - The signatures were verified against the specified public key
{"payloadType":"application/vnd.in-toto+json","payload":"eyJfdHlwZSI6Imh0dHBzOi8vaW4tdG90by5pby9TdGF0ZW1lbnQvdjAuMSIsICJzdWJqZWN0IjpbeyJuYW1lIjoicXVheS5pby9tbW9ydGFyaS9tbC1pcmlzIiwgImRpZ2VzdCI6eyJzaGEyNTYiOiJiZjY0ZTg3N2MyNDY3MGNmNTE3ZjUyZGY0NzBiZWFmYzYxMTg0MDcwN2NmOGVlNDU1MzVjZDFkODMxMzc4NGRlIn19XSwgInByZWRpY2F0ZVR5cGUiOiJodHRwczovL3Nsc2EuZGV2L3Byb3ZlbmFuY2UvdjAuMiIsICJwcmVkaWNhdGUiOnsiYnVpbGRDb25maWciOnsic3RlcHMiOlt7ImFubm90YXRpb25zIjpudWxsLCAiYXJndW1lbnRzIjpudWxsLCAiZW50cnlQb2ludCI6IiMgUmVzb2x2ZSB0aGUgZGF0YXNldCByZWYgdG8gYSBkaWdlc3QuXG4jIFRPRE86IEhhbmRsZSB0aGUgY2FzZSB3aGVyZSBEQVRBU0VUIGFscmVhZHkgY29udGFpbnMgYSBkaWdlc3QuXG5EQVRBU0VUX0RJR0VTVD1cIiQoc2tvcGVvIGluc3BlY3QgLS1yYXcgXCJkb2NrZXI6Ly8ke0RBVEFTRVR9XCIgfCBzaGEyNTZzdW0gfCBhd2sgJ3twcmludGYgXCJzaGEyNTY6XCIkMX0nKVwiXG5cbmVjaG8gLW4gXCIke0RBVEFTRVRfRElHRVNUfVwiIHwgdGVlIC90ZWt0b24vcmVzdWx0cy9EQVRBU0VUX0RJR0VTVCAmJiBlY2hvXG5lY2hvIC1uIFwiJHtEQVRBU0VUfVwiIHwgdGVlIC90ZWt0b24vcmVzdWx0cy9EQVRBU0VUX1VSTCAmJiBlY2hvXG5cbnB5dGhvbiAvYXBwL3RyYWluX21vZGVsLnB5IC0taW1hZ2UgXCIke0lNQUdFfVwiIFxcXG4gIC0tZGF0YXNldCBcIiR7REFUQVNFVH1AJHtEQVRBU0VUX0RJR0VTVH1cIiBcXFxuICAtLXJlc3VsdHMtaW1hZ2UtdXJsLXBhdGggL3Rla3Rvbi9yZXN1bHRzL0lNQUdFX1VSTCBcXFxuICAtLXJlc3VsdHMtaW1hZ2UtZGlnZXN0LXBhdGggL3Rla3Rvbi9yZXN1bHRzL0lNQUdFX0RJR0VTVFxuXG5lY2hvIFwiT3V0IG9mIHB5LlwiXG5jYXQgL3Rla3Rvbi9yZXN1bHRzL0lNQUdFX1VSTFxuZWNob1xuY2F0IC90ZWt0b24vcmVzdWx0cy9JTUFHRV9ESUdFU1RcbmVjaG9cblxuZWNobyBcIlJlLWRvaW5nIHdpdGggc2tvcGVvLi4uXCJcbnNrb3BlbyBpbnNwZWN0IC0tcmF3IFwiZG9ja2VyOi8vJHtJTUFHRX1cIiB8IHNoYTI1NnN1bSB8IGF3ayAne3ByaW50ZiBcInNoYTI1NjpcIiQxfScgfCB0ZWUgL3Rla3Rvbi9yZXN1bHRzL0lNQUdFX0RJR0VTVFxuZWNobyBcIlwiXG5lY2hvIC1uIFwiJHtJTUFHRX1cIiB8IHRlZSAvdGVrdG9uL3Jlc3VsdHMvSU1BR0VfVVJMXG5lY2hvIFwiXCJcbiIsICJlbnZpcm9ubWVudCI6eyJjb250YWluZXIiOiJvbWwtdHJhaW4tYW5kLXB1c2giLCAiaW1hZ2UiOiJvY2k6Ly9xdWF5LmlvL21tb3J0YXJpL2RlbW8yMDI0MDcwNC1tbHRyYWluLWFzLW9jaUBzaGEyNTY6ZWI4NzkyNjg2ZGY0YTlkZDZjMmMyNjFkMjI2ZGJmZmIyZTcyODk3ODBlZTkxZmQ0ZmRlZWE4YWNlNjcwNjY5MyJ9fV19LCAiYnVpbGRUeXBlIjoidGVrdG9uLmRldi92MWJldGExL1Rhc2tSdW4iLCAiYnVpbGRlciI6eyJpZCI6Imh0dHBzOi8vdGVrdG9uLmRldi9jaGFpbnMvdjIifSwgImludm9jYXRpb24iOnsiY29uZmlnU291cmNlIjp7fSwgImVudmlyb25tZW50Ijp7ImFubm90YXRpb25zIjp7InBpcGVsaW5lLnRla3Rvbi5kZXYvcmVsZWFzZSI6IjU3NWIzNWMifSwgImxhYmVscyI6eyJhcHAua3ViZXJuZXRlcy5pby9tYW5hZ2VkLWJ5IjoidGVrdG9uLXBpcGVsaW5lcyIsICJ0ZWt0b24uZGV2L21lbWJlck9mIjoidGFza3MiLCAidGVrdG9uLmRldi9waXBlbGluZSI6Im9tbC1jaGFpbnMtcnVuLWhkZnY2IiwgInRla3Rvbi5kZXYvcGlwZWxpbmVSdW4iOiJvbWwtY2hhaW5zLXJ1bi1oZGZ2NiIsICJ0ZWt0b24uZGV2L3BpcGVsaW5lUnVuVUlEIjoiZDcxZWI1NmQtMzE4YS00YWJlLWFkNzctMGY3OTg4YjdlOTJmIiwgInRla3Rvbi5kZXYvcGlwZWxpbmVUYXNrIjoidHJhaW4tYW5kLXB1c2giLCAidGVrdG9uLmRldi90YXNrIjoib21sLWNoYWlucyJ9fSwgInBhcmFtZXRlcnMiOnsiREFUQVNFVCI6InF1YXkuaW8vbW1vcnRhcmkvbWwtaXJpczpkYXRhIiwgIklNQUdFIjoicXVheS5pby9tbW9ydGFyaS9tbC1pcmlzOnYxIn19LCAibWF0ZXJpYWxzIjpbeyJkaWdlc3QiOnsic2hhMjU2IjoiZWI4NzkyNjg2ZGY0YTlkZDZjMmMyNjFkMjI2ZGJmZmIyZTcyODk3ODBlZTkxZmQ0ZmRlZWE4YWNlNjcwNjY5MyJ9LCAidXJpIjoib2NpOi8vcXVheS5pby9tbW9ydGFyaS9kZW1vMjAyNDA3MDQtbWx0cmFpbi1hcy1vY2kifV0sICJtZXRhZGF0YSI6eyJidWlsZEZpbmlzaGVkT24iOiIyMDI0LTEwLTA5VDE1OjU0OjIyWiIsICJidWlsZFN0YXJ0ZWRPbiI6IjIwMjQtMTAtMDlUMTU6NTQ6MDlaIiwgImNvbXBsZXRlbmVzcyI6eyJlbnZpcm9ubWVudCI6ZmFsc2UsICJtYXRlcmlhbHMiOmZhbHNlLCAicGFyYW1ldGVycyI6ZmFsc2V9LCAicmVwcm9kdWNpYmxlIjpmYWxzZX19fQ==","signatures":[{"keyid":"SHA256:Y4cmlwgzt8bj7evep9/GBYwJZxLV2pgYyQzmsUeF2ks","sig":"MEUCIFwDIAPd6KW1YZ1rbN3kNYcu6M3UpovbQqewfg8sxP1kAiEAtOmCIlBFplzVHfeukFUVWxAdn2CST0tk78ApHgkgntM="}]}
{"payloadType":"application/vnd.in-toto+json","payload":"eyJfdHlwZSI6Imh0dHBzOi8vaW4tdG90by5pby9TdGF0ZW1lbnQvdjAuMSIsICJzdWJqZWN0IjpbeyJuYW1lIjoicXVheS5pby9tbW9ydGFyaS9tbC1pcmlzIiwgImRpZ2VzdCI6eyJzaGEyNTYiOiJiZjY0ZTg3N2MyNDY3MGNmNTE3ZjUyZGY0NzBiZWFmYzYxMTg0MDcwN2NmOGVlNDU1MzVjZDFkODMxMzc4NGRlIn19XSwgInByZWRpY2F0ZVR5cGUiOiJodHRwczovL3Nsc2EuZGV2L3Byb3ZlbmFuY2UvdjAuMiIsICJwcmVkaWNhdGUiOnsiYnVpbGRDb25maWciOnsidGFza3MiOlt7ImZpbmlzaGVkT24iOiIyMDI0LTEwLTA5VDE1OjU0OjIyWiIsICJpbnZvY2F0aW9uIjp7ImNvbmZpZ1NvdXJjZSI6e30sICJlbnZpcm9ubWVudCI6eyJhbm5vdGF0aW9ucyI6eyJwaXBlbGluZS50ZWt0b24uZGV2L3JlbGVhc2UiOiI1NzViMzVjIn0sICJsYWJlbHMiOnsiYXBwLmt1YmVybmV0ZXMuaW8vbWFuYWdlZC1ieSI6InRla3Rvbi1waXBlbGluZXMiLCAidGVrdG9uLmRldi9tZW1iZXJPZiI6InRhc2tzIiwgInRla3Rvbi5kZXYvcGlwZWxpbmUiOiJvbWwtY2hhaW5zLXJ1bi1oZGZ2NiIsICJ0ZWt0b24uZGV2L3BpcGVsaW5lUnVuIjoib21sLWNoYWlucy1ydW4taGRmdjYiLCAidGVrdG9uLmRldi9waXBlbGluZVJ1blVJRCI6ImQ3MWViNTZkLTMxOGEtNGFiZS1hZDc3LTBmNzk4OGI3ZTkyZiIsICJ0ZWt0b24uZGV2L3BpcGVsaW5lVGFzayI6InRyYWluLWFuZC1wdXNoIiwgInRla3Rvbi5kZXYvdGFzayI6Im9tbC1jaGFpbnMifX0sICJwYXJhbWV0ZXJzIjp7IkRBVEFTRVQiOiJxdWF5LmlvL21tb3J0YXJpL21sLWlyaXM6ZGF0YSIsICJJTUFHRSI6InF1YXkuaW8vbW1vcnRhcmkvbWwtaXJpczp2MSJ9fSwgIm5hbWUiOiJ0cmFpbi1hbmQtcHVzaCIsICJyZWYiOnsia2luZCI6IlRhc2siLCAibmFtZSI6Im9tbC1jaGFpbnMifSwgInJlc3VsdHMiOlt7Im5hbWUiOiJEQVRBU0VUX0RJR0VTVCIsICJ0eXBlIjoic3RyaW5nIiwgInZhbHVlIjoic2hhMjU2OjkzNDllYjMzNTM3M2QzNzU1OTY0NTZhYTlmYWYyODM4YTczYTdlM2Q0ZGNlZGJkMzM4YzU0ODA5MWI5MTlkZWUifSwgeyJuYW1lIjoiREFUQVNFVF9VUkwiLCAidHlwZSI6InN0cmluZyIsICJ2YWx1ZSI6InF1YXkuaW8vbW1vcnRhcmkvbWwtaXJpczpkYXRhIn0sIHsibmFtZSI6IklNQUdFX0RJR0VTVCIsICJ0eXBlIjoic3RyaW5nIiwgInZhbHVlIjoic2hhMjU2OmJmNjRlODc3YzI0NjcwY2Y1MTdmNTJkZjQ3MGJlYWZjNjExODQwNzA3Y2Y4ZWU0NTUzNWNkMWQ4MzEzNzg0ZGUifSwgeyJuYW1lIjoiSU1BR0VfVVJMIiwgInR5cGUiOiJzdHJpbmciLCAidmFsdWUiOiJxdWF5LmlvL21tb3J0YXJpL21sLWlyaXM6djEifV0sICJzZXJ2aWNlQWNjb3VudE5hbWUiOiJkZWZhdWx0IiwgInN0YXJ0ZWRPbiI6IjIwMjQtMTAtMDlUMTU6NTQ6MDlaIiwgInN0YXR1cyI6IlN1Y2NlZWRlZCIsICJzdGVwcyI6W3siYW5ub3RhdGlvbnMiOm51bGwsICJhcmd1bWVudHMiOm51bGwsICJlbnRyeVBvaW50IjoiIyBSZXNvbHZlIHRoZSBkYXRhc2V0IHJlZiB0byBhIGRpZ2VzdC5cbiMgVE9ETzogSGFuZGxlIHRoZSBjYXNlIHdoZXJlIERBVEFTRVQgYWxyZWFkeSBjb250YWlucyBhIGRpZ2VzdC5cbkRBVEFTRVRfRElHRVNUPVwiJChza29wZW8gaW5zcGVjdCAtLXJhdyBcImRvY2tlcjovLyR7REFUQVNFVH1cIiB8IHNoYTI1NnN1bSB8IGF3ayAne3ByaW50ZiBcInNoYTI1NjpcIiQxfScpXCJcblxuZWNobyAtbiBcIiR7REFUQVNFVF9ESUdFU1R9XCIgfCB0ZWUgL3Rla3Rvbi9yZXN1bHRzL0RBVEFTRVRfRElHRVNUICYmIGVjaG9cbmVjaG8gLW4gXCIke0RBVEFTRVR9XCIgfCB0ZWUgL3Rla3Rvbi9yZXN1bHRzL0RBVEFTRVRfVVJMICYmIGVjaG9cblxucHl0aG9uIC9hcHAvdHJhaW5fbW9kZWwucHkgLS1pbWFnZSBcIiR7SU1BR0V9XCIgXFxcbiAgLS1kYXRhc2V0IFwiJHtEQVRBU0VUfUAke0RBVEFTRVRfRElHRVNUfVwiIFxcXG4gIC0tcmVzdWx0cy1pbWFnZS11cmwtcGF0aCAvdGVrdG9uL3Jlc3VsdHMvSU1BR0VfVVJMIFxcXG4gIC0tcmVzdWx0cy1pbWFnZS1kaWdlc3QtcGF0aCAvdGVrdG9uL3Jlc3VsdHMvSU1BR0VfRElHRVNUXG5cbmVjaG8gXCJPdXQgb2YgcHkuXCJcbmNhdCAvdGVrdG9uL3Jlc3VsdHMvSU1BR0VfVVJMXG5lY2hvXG5jYXQgL3Rla3Rvbi9yZXN1bHRzL0lNQUdFX0RJR0VTVFxuZWNob1xuXG5lY2hvIFwiUmUtZG9pbmcgd2l0aCBza29wZW8uLi5cIlxuc2tvcGVvIGluc3BlY3QgLS1yYXcgXCJkb2NrZXI6Ly8ke0lNQUdFfVwiIHwgc2hhMjU2c3VtIHwgYXdrICd7cHJpbnRmIFwic2hhMjU2OlwiJDF9JyB8IHRlZSAvdGVrdG9uL3Jlc3VsdHMvSU1BR0VfRElHRVNUXG5lY2hvIFwiXCJcbmVjaG8gLW4gXCIke0lNQUdFfVwiIHwgdGVlIC90ZWt0b24vcmVzdWx0cy9JTUFHRV9VUkxcbmVjaG8gXCJcIlxuIiwgImVudmlyb25tZW50Ijp7ImNvbnRhaW5lciI6Im9tbC10cmFpbi1hbmQtcHVzaCIsICJpbWFnZSI6Im9jaTovL3F1YXkuaW8vbW1vcnRhcmkvZGVtbzIwMjQwNzA0LW1sdHJhaW4tYXMtb2NpQHNoYTI1NjplYjg3OTI2ODZkZjRhOWRkNmMyYzI2MWQyMjZkYmZmYjJlNzI4OTc4MGVlOTFmZDRmZGVlYThhY2U2NzA2NjkzIn19XX1dfSwgImJ1aWxkVHlwZSI6InRla3Rvbi5kZXYvdjFiZXRhMS9QaXBlbGluZVJ1biIsICJidWlsZGVyIjp7ImlkIjoiaHR0cHM6Ly90ZWt0b24uZGV2L2NoYWlucy92MiJ9LCAiaW52b2NhdGlvbiI6eyJjb25maWdTb3VyY2UiOnt9LCAiZW52aXJvbm1lbnQiOnsibGFiZWxzIjp7InRla3Rvbi5kZXYvcGlwZWxpbmUiOiJvbWwtY2hhaW5zLXJ1bi1oZGZ2NiJ9fSwgInBhcmFtZXRlcnMiOnsiREFUQVNFVCI6InF1YXkuaW8vbW1vcnRhcmkvbWwtaXJpczpkYXRhIiwgIklNQUdFIjoicXVheS5pby9tbW9ydGFyaS9tbC1pcmlzOnYxIn19LCAibWF0ZXJpYWxzIjpbeyJkaWdlc3QiOnsic2hhMjU2IjoiZWI4NzkyNjg2ZGY0YTlkZDZjMmMyNjFkMjI2ZGJmZmIyZTcyODk3ODBlZTkxZmQ0ZmRlZWE4YWNlNjcwNjY5MyJ9LCAidXJpIjoib2NpOi8vcXVheS5pby9tbW9ydGFyaS9kZW1vMjAyNDA3MDQtbWx0cmFpbi1hcy1vY2kifV0sICJtZXRhZGF0YSI6eyJidWlsZEZpbmlzaGVkT24iOiIyMDI0LTEwLTA5VDE1OjU0OjIyWiIsICJidWlsZFN0YXJ0ZWRPbiI6IjIwMjQtMTAtMDlUMTU6NTQ6MDlaIiwgImNvbXBsZXRlbmVzcyI6eyJlbnZpcm9ubWVudCI6ZmFsc2UsICJtYXRlcmlhbHMiOmZhbHNlLCAicGFyYW1ldGVycyI6ZmFsc2V9LCAicmVwcm9kdWNpYmxlIjpmYWxzZX19fQ==","signatures":[{"keyid":"SHA256:Y4cmlwgzt8bj7evep9/GBYwJZxLV2pgYyQzmsUeF2ks","sig":"MEUCIHdezWIH7rKnx/j/Ih/yLy+9hEd6mpd+pe5YexVncm84AiEAqn11hwzy9YH8ecvHg2TFkVOaGcC/6iN9N8COHVYSjXA="}]}
```

</details>

## Enterprise Contract

You can also use [Enterprise Contract](https://enterprisecontract.dev/) to verify the image is
signed, it has an assocaited SLSA Provenance attestation, and more. Use the script
[check.sh](policy/check.sh) for this.

<details>

```
👷 Checking quay.io/mmortari/ml-iris:v1
📓 Policy config updated to use local rules:
---
sources:
  - policy:
      - /Users/mmortari/git/demo20240704-mltrain-as-oci//policy/rules
      - github.com/enterprise-contract/ec-policies//policy/lib
      - github.com/enterprise-contract/ec-policies//policy/release/lib/
    data:
      - oci::quay.io/konflux-ci/tekton-catalog/data-acceptable-bundles:latest
      - github.com/release-engineering/rhtap-ec-policy//data
    ruleData:
      allowed_dataset_prefixes:
        - quay.io/mmortari/
🔍 Validating image with EC
Success: true
Result: SUCCESS
Violations: 0, Warnings: 0, Successes: 4
Component: Unnamed
ImageRef: quay.io/mmortari/ml-iris@sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de

Results:
✓ [Success] builtin.attestation.signature_check
  ImageRef: quay.io/mmortari/ml-iris@sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de

✓ [Success] builtin.attestation.syntax_check
  ImageRef: quay.io/mmortari/ml-iris@sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de

✓ [Success] builtin.image.signature_check
  ImageRef: quay.io/mmortari/ml-iris@sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de

✓ [Success] dataset.permitted
  ImageRef: quay.io/mmortari/ml-iris@sha256:bf64e877c24670cf517f52df470beafc611840707cf8ee45535cd1d8313784de
```

</details>

NOTE: Modify the ruleData in [config.yaml](policy/config.yaml) to see what a failure looks like.

The image signatures that EC verifies are [Sigstore](https://www.sigstore.dev/) based signatures.
There are [different ways](https://blog.sigstore.dev/adopting-sigstore-incrementally-1b56a69b8c15/)
of using Sigstore. For simplicity sake, the test model image built from this repo was signed with a
long-lived key without Rekor integration. This means that we need to provide the public key when
validating the image with EC. Furthermore, the *private* key is never really stored anywhere. So if
running through the process of building the image again, a new key pair will be created. As such,
update the public key in the [check.sh](policy/check.sh) script. The public key is referring to the
file `cosign.pub` when executing: `cosign generate-key-pair k8s://tekton-chains/signing-secrets`from
the tutorial: <https://tekton.dev/docs/chains/signed-provenance-tutorial/#generate-a-key-pair>.
The `allowed_dataset_prefixes` is defined [in the rego file](./policy/rules/dataset.rego).

## WIP

for local tests

```
docker run --privileged -it quay.io/buildah/stable
```

using task

note.
remember to regenerate :v1, otherwise attestation check will fail.

<details>

```
PUBLIC_KEY=$(cat cosign.pub)
tkn pipeline start --use-param-defaults -f omlmd-pipeline-to-modelcar.yml \
--param PUBLIC_KEY="$(cat cosign.pub)" --showlog \
--workspace name=workspace1,volumeClaimTemplateFile=workspace-template.yaml
PipelineRun started: omlmd-pipeline-to-modelcar-run-vrb5h
Waiting for logs to be available...
[omlmd-to-modelcar : compute-digests] sha256:c7b4d6caf0ea0fca3cda6ac5782bb54571ee8af8b19c0d0ddde1f7de2f6834f2
[omlmd-to-modelcar : compute-digests] quay.io/mmortari/ml-iris@sha256:c7b4d6caf0ea0fca3cda6ac5782bb54571ee8af8b19c0d0ddde1f7de2f6834f2

[omlmd-to-modelcar : verify] Using file cosign.pub as public key:
[omlmd-to-modelcar : verify] -----BEGIN PUBLIC KEY-----
[omlmd-to-modelcar : verify] MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE+VyrlukykhDVLKU6Hd1tFTf5BG2X
[omlmd-to-modelcar : verify] QWApQAD7z+pPXln+X/UqJ/sWwVw4QoVMqMT+HNTz6KTxCd9gw848SiNjsw==
[omlmd-to-modelcar : verify] -----END PUBLIC KEY-----
[omlmd-to-modelcar : verify] WARNING: Skipping tlog verification is an insecure practice that lacks of transparency and auditability verification for the attestation.
[omlmd-to-modelcar : verify] Error: no matching attestations: accepted signatures do not match threshold, Found: 0, Expected 1
[omlmd-to-modelcar : verify] main.go:74: error during command execution: no matching attestations: accepted signatures do not match threshold, Found: 0, Expected 1

failed to get logs for task omlmd-to-modelcar : container step-verify has failed  : [{"key":"OCIARTIFACT_DIGEST","value":"sha256:c7b4d6caf0ea0fca3cda6ac5782bb54571ee8af8b19c0d0ddde1f7de2f6834f2","type":1},{"key":"OCIARTIFACT_REF","value":"quay.io/mmortari/ml-iris@sha256:c7b4d6caf0ea0fca3cda6ac5782bb54571ee8af8b19c0d0ddde1f7de2f6834f2","type":1},{"key":"StartedAt","value":"2024-10-21T10:05:52.740Z","type":3}]
```

</details>

```sh
kubectl apply -f buildah-subject.yaml
kubectl apply -f omlmd-to-modelcar.yml
kubectl apply -f omlmd-pipeline-to-modelcar.yml
```

```
PUBLIC_KEY=$(cat cosign.pub)

tkn task start --use-param-defaults -f omlmd-to-modelcar.yml \
--param PUBLIC_KEY="$(cat cosign.pub)" --showlog \
--workspace name=workspace1,emptyDir=""

kubectl apply -f omlmd-to-modelcar.yml
```

```
PUBLIC_KEY=$(cat cosign.pub)
tkn pipeline start omlmd-pipeline-to-modelcar --use-param-defaults \
--param PUBLIC_KEY="$(cat cosign.pub)" \
--param OCIARTIFACT_IMAGE=quay.io/mmortari/ml-iris:v1 \
--showlog \
--workspace name=workspace1,volumeClaimTemplateFile=workspace-template.yaml
```

```
% cosign tree quay.io/mmortari/ml-iris:v1-modelcar                           
📦 Supply Chain Security Related artifacts for an image: quay.io/mmortari/ml-iris:v1-modelcar
└── 💾 Attestations for an image tag: quay.io/mmortari/ml-iris:sha256-9a3543b4fb5a05a2ba8a0079ce54c59581ce26df94dd73dd9665f509388c87a3.att
   ├── 🍒 sha256:b43aa29bdb4dc038309a28834caa452d8d9974a2f0e5753c1d914a7250ce30a7
   └── 🍒 sha256:c693c5479b66ff5902b6db4734425012e00a1c26b3706f9a7350cb8b7d583c40
└── 🔐 Signatures for an image tag: quay.io/mmortari/ml-iris:sha256-9a3543b4fb5a05a2ba8a0079ce54c59581ce26df94dd73dd9665f509388c87a3.sig
   └── 🍒 sha256:93a22c8868655804a227ace63798412b3ef442517194f26e04ae15bbc673037e
```

Notice `subject` for OCI-Dist 1.1 referrers API (optional)

```
% skopeo inspect --raw docker://quay.io/mmortari/ml-iris:v1-modelcar | jq
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:e16171a9a15d60fc203035a68552726f58cc1b7f702708a29cfcca5688c08e95",
      "size": 919,
      "platform": {
        "architecture": "arm64",
        "os": "linux",
        "variant": "v8"
      }
    }
  ],
  "subject": {
    "mediaType": "application/vnd.oci.image.manifest.v1+json",
    "digest": "sha256:dec449be52c45a217a9d6b424173458f1cb627f8da3f26668dfa6724130072f8",
    "size": 1034
  }
}
```
