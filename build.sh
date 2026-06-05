#!/usr/bin/env bash
# =============================================================================
# build.sh — build & push the Kubeflow notebook image
# Usage: ./build.sh [registry/image:tag]
# =============================================================================
set -euo pipefail

IMAGE="${1:-your-registry/kubeflow-notebook:cuda12.9-py3.12}"

echo "▶ Building $IMAGE"
docker build \
  --platform linux/amd64 \
  --network=host \
  --build-arg NB_USER=jovyan \
  --build-arg NB_UID=1000 \
  -t "$IMAGE" \
  -f Dockerfile \
  .

echo "▶ Pushing $IMAGE"
docker push "$IMAGE"

echo "✅ Done — use in Kubeflow as: $IMAGE"
