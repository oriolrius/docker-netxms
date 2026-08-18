#!/usr/bin/env bash
#
# Release suite: validates the images actually published to the registry for a tag.
# Run it from a checkout of that tag -- the expected NetXMS version is read from the
# Dockerfiles, so the images are checked against what the source says they contain.
#
# Usage: tests/published.sh <image-tag> [image-prefix]
#   tests/published.sh v1.1.0
#   tests/published.sh 3116f4 ghcr.io/oriolrius/docker-netxms
set -uo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap cleanup EXIT
require_docker

if [ $# -lt 1 ]; then
    printf 'usage: %s <image-tag> [image-prefix]\n' "$0" >&2
    exit 2
fi

IMAGE_TAG="$1"
IMAGE_PREFIX="${2:-${IMAGE_PREFIX:-ghcr.io/oriolrius/docker-netxms}}"
SERVER_IMAGE="${IMAGE_PREFIX}-server:${IMAGE_TAG}"
AGENT_IMAGE="${IMAGE_PREFIX}-agent:${IMAGE_TAG}"
EXPECTED_VERSION="$(pinned_version Dockerfile.server)"

log "Pulling published images for $IMAGE_TAG"
info "expected NetXMS version from the Dockerfiles: $EXPECTED_VERSION"

pulled=1
for image in "$SERVER_IMAGE" "$AGENT_IMAGE"; do
    if docker pull -q "$image" >/dev/null 2>&1; then
        pass "$image is published and pullable"
    else
        fail "$image is published and pullable" "docker pull $image failed"
        pulled=0
    fi
done

if [ "$pulled" -eq 0 ]; then
    summary "published suite"
    exit 1
fi

log "Contents of the published images"
SERVER_PACKAGES=(netxms-server netxms-agent netxms-base netxms-dbdrv-sqlite3)
AGENT_PACKAGES=(netxms-agent netxms-base netxms-dbdrv-sqlite3)

check_image_contents() { # <image> <package...>
    local image="$1"; shift
    local codename expected held installed pkg
    codename="$(image_codename "$image")"
    expected="$(expected_pkg_version "$EXPECTED_VERSION" "$codename")"
    held="$(held_packages "$image")"
    assert_eq "$image is built on ubuntu ${TEST_CODENAME}" "$TEST_CODENAME" "$codename"
    for pkg in "$@"; do
        installed="$(pkg_version "$image" "$pkg")"
        assert_eq "$(basename "$image"): $pkg is $expected" "$expected" "$installed"
        assert_contains "$(basename "$image"): $pkg is held" "$pkg" "$held"
    done
    assert_eq "$(basename "$image") is linux/amd64" "linux/amd64" \
        "$(docker image inspect "$image" --format '{{.Os}}/{{.Architecture}}')"
}

check_image_contents "$SERVER_IMAGE" "${SERVER_PACKAGES[@]}"
check_image_contents "$AGENT_IMAGE" "${AGENT_PACKAGES[@]}"

# A release tag and :latest should point at the same digest, unless something was
# pushed to main after the tag build. Informational: a later main build is legitimate.
if [ "$IMAGE_TAG" != "latest" ] && docker buildx version >/dev/null 2>&1; then
    log "Comparing $IMAGE_TAG with :latest"
    for repo in "${IMAGE_PREFIX}-server" "${IMAGE_PREFIX}-agent"; do
        tagged="$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "${repo}:${IMAGE_TAG}" 2>/dev/null)"
        latest="$(docker buildx imagetools inspect --format '{{.Manifest.Digest}}' "${repo}:latest" 2>/dev/null)"
        if [ -n "$tagged" ] && [ "$tagged" = "$latest" ]; then
            info "$(basename "$repo"): :latest matches :$IMAGE_TAG"
        else
            warn "$(basename "$repo"): :latest ($latest) differs from :$IMAGE_TAG ($tagged)"
        fi
    done
fi

log "Running the runtime suite against the published images"
if "$REPO_ROOT/tests/runtime.sh" "$SERVER_IMAGE" "$AGENT_IMAGE" "$EXPECTED_VERSION"; then
    pass "published images pass the runtime suite"
else
    fail "published images pass the runtime suite" "see the runtime suite output above"
fi

summary "published suite"
