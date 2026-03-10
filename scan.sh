#!/bin/sh
set -eu

IMAGE="${1:-openclaw-openclaw}"

if ! command -v trivy >/dev/null 2>&1; then
  echo "trivy nao encontrado. Instale manualmente:" >&2
  echo "  https://aquasecurity.github.io/trivy/latest/getting-started/installation/" >&2
  exit 1
fi

echo "=== Scan de vulnerabilidades: ${IMAGE} ==="
trivy image --severity HIGH,CRITICAL --ignore-unfixed "${IMAGE}"

echo ""
echo "=== Scan do Dockerfile ==="
trivy config --severity HIGH,CRITICAL .

echo ""
echo "=== Scan de secrets expostos ==="
trivy fs --scanners secret .
