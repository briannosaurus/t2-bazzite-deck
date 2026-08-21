#!/usr/bin/env bash
# Builds the t2-bazzite-deck image locally with podman. Does not push or
# publish anywhere, and does not touch rpm-ostree/bootc state on this host.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_NAME="${IMAGE_NAME:-localhost/t2-bazzite-deck}"
IMAGE_TAG="${IMAGE_TAG:-local}"
BASE_TAG="${BASE_TAG:-stable}"

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} (base tag: ${BASE_TAG})"
podman build \
    --build-arg "BASE_TAG=${BASE_TAG}" \
    -f Containerfile \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    .

cat <<EOF

Built ${IMAGE_NAME}:${IMAGE_TAG}. Nothing has been pushed or deployed.

To test this image on this machine WITHOUT pushing to any registry, see
README.md "Test" section -- it rebases into a new rpm-ostree deployment
pointing at this local image, leaving your current deployment and the
bazzite-deck:stable fallback deployment untouched and selectable at boot.
EOF
