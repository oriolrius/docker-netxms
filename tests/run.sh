#!/usr/bin/env bash
#
# Entry point for the docker-netxms test suites.
#
#   tests/run.sh                        # build + runtime against locally built images
#   tests/run.sh --suite build          # only the NETXMS_VERSION build matrix
#   tests/run.sh --suite runtime        # only the server/agent functional checks
#   tests/run.sh --suite published --tag v1.1.0
#
# Environment:
#   IMAGE_PREFIX     registry prefix for --suite published
#                    (default ghcr.io/oriolrius/docker-netxms)
#   KEEP_ARTIFACTS=1 leave test containers and images behind for inspection
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib.sh
. "$SCRIPT_DIR/lib.sh"
trap cleanup EXIT
require_docker

SUITE="local"
TAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --suite) SUITE="${2:-}"; shift 2 ;;
        --tag) TAG="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

failed=0

run_suite() {
    printf '\n%s########## %s ##########%s\n' "$_c_bold" "$1" "$_c_off"
    shift
    "$@" || failed=1
}

build_local_images() {
    log "Building images from the working tree"
    docker build -q -f "$REPO_ROOT/Dockerfile.server" -t netxms-test-local-server "$REPO_ROOT" >/dev/null &&
        docker build -q -f "$REPO_ROOT/Dockerfile.agent" -t netxms-test-local-agent "$REPO_ROOT" >/dev/null
}

case "$SUITE" in
    build)
        run_suite "build suite" "$SCRIPT_DIR/build.sh"
        ;;
    runtime)
        if build_local_images; then
            register_image netxms-test-local-server
            register_image netxms-test-local-agent
            run_suite "runtime suite" "$SCRIPT_DIR/runtime.sh" \
                netxms-test-local-server netxms-test-local-agent
        else
            printf 'failed to build the images under test\n' >&2
            failed=1
        fi
        ;;
    published)
        if [ -z "$TAG" ]; then
            printf -- '--suite published requires --tag <image-tag>\n' >&2
            exit 2
        fi
        run_suite "published suite" "$SCRIPT_DIR/published.sh" "$TAG"
        ;;
    local|all)
        run_suite "build suite" "$SCRIPT_DIR/build.sh"
        if build_local_images; then
            register_image netxms-test-local-server
            register_image netxms-test-local-agent
            run_suite "runtime suite" "$SCRIPT_DIR/runtime.sh" \
                netxms-test-local-server netxms-test-local-agent
        else
            printf 'failed to build the images under test\n' >&2
            failed=1
        fi
        ;;
    *)
        printf 'unknown suite: %s (build|runtime|published|all)\n' "$SUITE" >&2
        exit 2
        ;;
esac

if [ "$failed" -eq 0 ]; then
    printf '\n%sAll suites passed%s\n' "$_c_green" "$_c_off"
else
    printf '\n%sSome suites failed%s\n' "$_c_red" "$_c_off" >&2
fi
exit "$failed"
