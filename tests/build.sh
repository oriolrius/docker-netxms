#!/usr/bin/env bash
#
# Build suite: verifies that NETXMS_VERSION pins what it claims to pin.
#
# Every check here maps to a way the pinning has already broken once:
#   - the server image failing to build because netxmsd -v exits 1
#   - a pin older than the newest release failing on "held broken packages"
#   - a release whose Debian revision is not -1 being unreachable
#
# Usage: tests/build.sh
set -uo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap cleanup EXIT
require_docker

TAG_PREFIX="netxms-buildtest-$$"

# build_image <dockerfile> <NETXMS_VERSION|""> <tag> -- returns the build exit code
build_image() {
    local dockerfile="$1" version="$2" tag="$3"
    local args=(build -f "$REPO_ROOT/$dockerfile" -t "$tag")
    [ -n "$version" ] && args+=(--build-arg "NETXMS_VERSION=$version")
    register_image "$tag"
    docker "${args[@]}" "$REPO_ROOT"
}

# check_pinned <dockerfile> <NETXMS_VERSION> <label> <package...> -- build, then assert
# the requested version is what got installed and that every netxms-* package is held.
check_pinned() {
    local dockerfile="$1" version="$2" label="$3"; shift 3
    local packages=("$@")
    local tag="${TAG_PREFIX}-${label}"
    local codename expected held pkg installed

    log "$dockerfile with NETXMS_VERSION=$version"
    if ! build_image "$dockerfile" "$version" "$tag" >/dev/null 2>&1; then
        fail "$dockerfile builds with NETXMS_VERSION=$version" \
             "re-run manually: docker build --build-arg NETXMS_VERSION=$version -f $dockerfile ."
        return 0
    fi
    pass "$dockerfile builds with NETXMS_VERSION=$version"

    codename="$(image_codename "$tag")"
    expected="$(expected_pkg_version "$version" "$codename")"
    held="$(held_packages "$tag")"

    for pkg in "${packages[@]}"; do
        installed="$(pkg_version "$tag" "$pkg")"
        assert_eq "$pkg is $expected" "$expected" "$installed"
        assert_contains "$pkg is held against apt-get upgrade" "$pkg" "$held"
    done
}

log "Discovering versions from packages.netxms.org (${TEST_CODENAME})"
PINNED="$(pinned_version Dockerfile.server)"
PINNED_AGENT="$(pinned_version Dockerfile.agent)"
PREVIOUS="$(previous_version)"
REVISION="$(revision_version)"
info "pinned in Dockerfiles: $PINNED"
info "previous release:      $PREVIOUS"
info "non -1 revision:       $REVISION"

assert_eq "server and agent pin the same NetXMS version" "$PINNED" "$PINNED_AGENT"

SERVER_PACKAGES=(netxms-server netxms-agent netxms-base netxms-dbdrv-sqlite3)
AGENT_PACKAGES=(netxms-agent netxms-base netxms-dbdrv-sqlite3)

# The default pin: what a plain `docker build` / `docker compose build` produces.
check_pinned Dockerfile.server "$PINNED" "server-default" "${SERVER_PACKAGES[@]}"
check_pinned Dockerfile.agent "$PINNED" "agent-default" "${AGENT_PACKAGES[@]}"

# A pin older than the newest release. This is the case the pin exists for -- and the
# one that regressed when only the top-level package was pinned.
check_pinned Dockerfile.server "$PREVIOUS" "server-previous" "${SERVER_PACKAGES[@]}"
check_pinned Dockerfile.agent "$PREVIOUS" "agent-previous" "${AGENT_PACKAGES[@]}"

# A release that upstream shipped with a Debian revision other than -1.
check_pinned Dockerfile.agent "$REVISION" "agent-revision" "${AGENT_PACKAGES[@]}"

log "Dockerfile.agent with NETXMS_VERSION=latest"
if build_image Dockerfile.agent latest "${TAG_PREFIX}-agent-latest" >/dev/null 2>&1; then
    pass "unpinned build still works (NETXMS_VERSION=latest)"
    latest_installed="$(pkg_version "${TAG_PREFIX}-agent-latest" netxms-agent)"
    assert_matches "latest resolves to a real version" '^[0-9]+\.[0-9]+\.[0-9]+-' "$latest_installed"
    info "latest currently resolves to $latest_installed"
else
    fail "unpinned build still works (NETXMS_VERSION=latest)"
fi

log "A version that does not exist must fail the build, not the deployment"
assert_fails "NETXMS_VERSION=9.9.9 fails at build time" \
    build_image Dockerfile.agent 9.9.9 "${TAG_PREFIX}-agent-bogus"

# Regression guard: netxmsd -v prints the version and exits 1, so the build must not
# depend on its exit status. Keep this check if the pipeline in Dockerfile.server is
# ever "simplified" back to `netxmsd -v && \`.
log "netxmsd -v exit status is not load-bearing"
SERVER_TAG="${TAG_PREFIX}-server-default"
if docker image inspect "$SERVER_TAG" >/dev/null 2>&1; then
    version_output="$(docker run --rm "$SERVER_TAG" netxmsd -v 2>&1 | head -1)"
    assert_contains "netxmsd -v reports the pinned version" "NetXMS Server Version $PINNED" "$version_output"
    assert_fails "netxmsd -v still exits non-zero (why the build greps its output)" \
        docker run --rm "$SERVER_TAG" netxmsd -v
else
    fail "netxmsd -v exit status check" "server image was not built"
fi

summary "build suite"
