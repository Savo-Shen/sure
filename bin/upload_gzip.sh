#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REMOTE="${REMOTE:-savo-prod}"
DEST="${DEST:-/opt/savo-ledger}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-savo-ledger}"
COMMIT_SHA="$(git rev-parse --short HEAD)"
IMAGE="${IMAGE_REPOSITORY}:savo-ledger-${COMMIT_SHA}"
ARCHIVE="${IMAGE_REPOSITORY}-${COMMIT_SHA}.tar.gz"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "${ARCHIVE} not found; run bin/build_gzip.sh first" >&2
  exit 1
fi

echo "Uploading ${ARCHIVE} to ${REMOTE}..."
rsync -h --progress --partial "$ARCHIVE" "$REMOTE:/tmp/$ARCHIVE"

if [[ "${1:-}" != "--reload" ]]; then
  echo
  echo "Uploaded. To load and deploy on ${REMOTE}:"
  echo "  bin/upload_gzip.sh --reload"
  exit 0
fi

echo "Loading ${IMAGE} and recreating web/worker on ${REMOTE}..."
ssh "$REMOTE" \
  "set -eu; \
   sudo docker load < /tmp/${ARCHIVE}; \
   cd ${DEST}; \
   sudo cp compose.yml compose.yml.before-${COMMIT_SHA}; \
   sudo sed -i -E 's#image:[[:space:]]*${IMAGE_REPOSITORY}:[^[:space:]]+#image: ${IMAGE}#g' compose.yml; \
   sudo docker compose config --quiet; \
   sudo docker compose up -d --force-recreate web worker; \
   sudo docker compose ps; \
   rm -f /tmp/${ARCHIVE}"
