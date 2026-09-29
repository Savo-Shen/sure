#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-savo-ledger}"
COMMIT_SHA="$(git rev-parse --short HEAD)"
IMAGE="${IMAGE_REPOSITORY}:savo-ledger-${COMMIT_SHA}"
ARCHIVE="${IMAGE_REPOSITORY}-${COMMIT_SHA}.tar.gz"

echo "Building ${IMAGE} for linux/amd64..."
docker buildx build \
  --platform linux/amd64 \
  --build-arg BUILD_COMMIT_SHA="$COMMIT_SHA" \
  --tag "$IMAGE" \
  --load \
  .

echo "Exporting ${IMAGE} to ${ARCHIVE}..."
docker save "$IMAGE" | gzip > "$ARCHIVE"
echo "Created ${ROOT_DIR}/${ARCHIVE}"
