#!/usr/bin/env bash
# Download a tested ARM64 release and retain the local aliases used by boot/workers.
set -euo pipefail
release_sha="${1:?Expected full release SHA}"
shift
[[ "$release_sha" =~ ^[0-9a-f]{40}$ ]] || { echo 'Expected a full Git SHA' >&2; exit 1; }
[ "$#" -gt 0 ] || { echo 'Expected image service names' >&2; exit 1; }
registry="${SASHFRAME_IMAGE_REGISTRY:-ghcr.io/keiranjprice101}"
for service in "$@"; do
    case "$service" in
        sashframe-app|sashframe-photo-processor|sashframe-calendar-sync) ;;
        *) echo "Unexpected image service: $service" >&2; exit 1 ;;
    esac
    remote_image="$registry/$service:sha-$release_sha"
    local_image="$service:${release_sha:0:8}"
    if ! docker image inspect "$remote_image" >/dev/null 2>&1; then
        if ! docker pull --platform linux/arm64 "$remote_image"; then
            echo "Release image unavailable: $remote_image. Check that its GitHub Actions run finished successfully." >&2
            exit 1
        fi
    fi
    platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$remote_image")"
    [ "$platform" = linux/arm64 ] || { echo "Unexpected image platform: $platform" >&2; exit 1; }
    remote_id="$(docker image inspect --format '{{.Id}}' "$remote_image")"
    local_id="$(docker image inspect --format '{{.Id}}' "$local_image" 2>/dev/null || true)"
    if [ "$remote_id" != "$local_id" ]; then
        docker tag "$remote_image" "$local_image"
        echo "Prepared image: $local_image"
    fi
done
