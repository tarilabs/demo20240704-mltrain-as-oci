#! /bin/bash
set -euo pipefail

IMAGE="${1:-quay.io/lucarval/demo-oml:latest}"

echo "👷 Checking ${IMAGE}"

cd "$(git rev-parse --show-toplevel)"

export RULES="$(pwd)//policy/rules"

# This is the public key used during testing with a kind cluster. It will need to be updated when
# verifying an image other than the default one, i.e.: this is the content of `cosign.pub` when
# executing: cosign generate-key-pair k8s://tekton-chains/signing-secrets from the tutorial:
# https://tekton.dev/docs/chains/signed-provenance-tutorial/#generate-a-key-pair
PUBLIC_KEY='-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEQmnuZzvNkoDf9G/CqFbq5sYw2aK/
LKLdobfjGnOSiq5k2L3lQXv+jNTkcDCgIUk1HZkkFd4TFvkzYxGlfs0EoQ==
-----END PUBLIC KEY-----'

config_path="$(mktemp --suffix .yaml)"

# A bit of a hack here to facilitate developemtn and CI. The config.yaml can be used as is, but it
# will use the policy rules already pushed to main.
echo '📓 Policy config updated to use local rules:'
< policy/config.yaml yq '.sources[0].policy[0] |= env(RULES)' | tee "${config_path}"

# The flag --ignore-rekor is used because when the image was signed, Rekor was not enabled in
# Chains. Without the flag EC will fail as a corresponding entry in Rekor will not be found.
echo '🔍 Validating image with EC'
ec validate image --ignore-rekor \
    --policy "${config_path}" --public-key <(echo "${PUBLIC_KEY}") --image "${IMAGE}" \
    --output text --show-successes
