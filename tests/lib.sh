#!/usr/bin/env bash
# Shared helpers for the docker-netxms test suites. Sourced, never executed.
#
# Provides a minimal assertion harness (no bats/pytest dependency: every check in
# these suites is a docker CLI call, so plain bash keeps the suites runnable on a
# bare ubuntu-latest runner with nothing installed), plus cleanup bookkeeping so a
# failed run does not leave containers, networks or images behind.

# shellcheck shell=bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Ubuntu suite of the base image, used only to query packages.netxms.org. Version
# assertions read the codename from the built image itself.
: "${TEST_CODENAME:=noble}"

_tests_run=0
_tests_failed=0
_cleanup_containers=()
_cleanup_networks=()
_cleanup_images=()

if [ -t 1 ]; then
    _c_bold=$'\033[1m'; _c_red=$'\033[31m'; _c_green=$'\033[32m'
    _c_yellow=$'\033[33m'; _c_off=$'\033[0m'
else
    _c_bold=""; _c_red=""; _c_green=""; _c_yellow=""; _c_off=""
fi

log()  { printf '\n%s==> %s%s\n' "$_c_bold" "$*" "$_c_off"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    %sWARN%s %s\n' "$_c_yellow" "$_c_off" "$*"; }

pass() {
    _tests_run=$((_tests_run + 1))
    printf '    %sPASS%s %s\n' "$_c_green" "$_c_off" "$1"
}

fail() {
    _tests_run=$((_tests_run + 1))
    _tests_failed=$((_tests_failed + 1))
    printf '    %sFAIL%s %s\n' "$_c_red" "$_c_off" "$1" >&2
    if [ $# -gt 1 ]; then
        printf '         %s\n' "$2" >&2
    fi
    return 0
}

# assert_eq <description> <expected> <actual>
assert_eq() {
    if [ "$2" = "$3" ]; then
        pass "$1"
    else
        fail "$1" "expected [$2] but got [$3]"
    fi
}

# assert_contains <description> <needle> <haystack>
assert_contains() {
    case "$3" in
        *"$2"*) pass "$1" ;;
        *) fail "$1" "[$2] not found in [$(printf '%s' "$3" | tr '\n' '/' | cut -c1-200)]" ;;
    esac
}

# assert_matches <description> <extended-regex> <value>
assert_matches() {
    if printf '%s' "$3" | grep -Eq "$2"; then
        pass "$1"
    else
        fail "$1" "[$3] does not match /$2/"
    fi
}

# assert_ok <description> <command...>
assert_ok() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc" "command failed: $*"
    fi
}

# assert_fails <description> <command...>
assert_fails() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        fail "$desc" "command unexpectedly succeeded: $*"
    else
        pass "$desc"
    fi
}

# summary <suite name> -- prints totals, returns 1 when anything failed
summary() {
    printf '\n%s--- %s: %d checks, %d failed ---%s\n' \
        "$_c_bold" "$1" "$_tests_run" "$_tests_failed" "$_c_off"
    [ "$_tests_failed" -eq 0 ]
}

# wait_for <timeout-seconds> <command...> -- polls until the command succeeds
wait_for() {
    local timeout="$1"; shift
    local deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if "$@" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

register_container() { _cleanup_containers+=("$1"); }
register_network()   { _cleanup_networks+=("$1"); }
register_image()     { _cleanup_images+=("$1"); }

cleanup() {
    if [ "${KEEP_ARTIFACTS:-0}" = "1" ]; then
        info "KEEP_ARTIFACTS=1 - leaving test containers, networks and images behind"
        return 0
    fi
    if [ "${#_cleanup_containers[@]}" -gt 0 ]; then
        docker rm -f "${_cleanup_containers[@]}" >/dev/null 2>&1 || true
    fi
    if [ "${#_cleanup_networks[@]}" -gt 0 ]; then
        for net in "${_cleanup_networks[@]}"; do
            docker network rm "$net" >/dev/null 2>&1 || true
        done
    fi
    if [ "${#_cleanup_images[@]}" -gt 0 ]; then
        docker rmi -f "${_cleanup_images[@]}" >/dev/null 2>&1 || true
    fi
}

require_docker() {
    if ! docker version >/dev/null 2>&1; then
        printf 'docker is not available or the daemon is not reachable\n' >&2
        exit 2
    fi
}

# pinned_version <Dockerfile> -- default of ARG NETXMS_VERSION, e.g. 6.2.3
pinned_version() {
    awk -F= '/^ARG NETXMS_VERSION=/ { print $2; exit }' "$REPO_ROOT/$1"
}

# image_codename <image> -- Ubuntu suite the image is built on, e.g. noble
image_codename() {
    docker run --rm "$1" lsb_release -sc 2>/dev/null | tr -d '\r'
}

# pkg_version <image> <package> -- installed version, e.g. 6.2.3-1+noble
pkg_version() {
    docker run --rm "$1" dpkg-query --showformat='${Version}' -W "$2" 2>/dev/null | tr -d '\r'
}

# held_packages <image> -- apt-mark hold list, one per line, sorted
held_packages() {
    docker run --rm "$1" apt-mark showhold 2>/dev/null | tr -d '\r' | sort
}

# available_versions <package> -- every version in packages.netxms.org for TEST_CODENAME
available_versions() {
    local url="https://packages.netxms.org/ubuntu/dists/${TEST_CODENAME}/main/binary-amd64/Packages.gz"
    curl -fsSL "$url" 2>/dev/null | gunzip 2>/dev/null | awk -v pkg="$1" '
        /^Package: / { current = $2 }
        /^Version: / { if (current == pkg) print $2 }
    ' | sed "s/+${TEST_CODENAME}\$//" | sort -Vu
}

# expected_pkg_version <NETXMS_VERSION> <codename> -- dpkg version the build should
# produce, mirroring the case statement in the Dockerfiles.
expected_pkg_version() {
    case "$1" in
        *-*) printf '%s+%s' "$1" "$2" ;;
        *) printf '%s-1+%s' "$1" "$2" ;;
    esac
}

# previous_version -- newest release below the one pinned in the Dockerfiles.
# Building it is the regression test for the strict "=" dependency on netxms-base:
# apt resolves those dependencies to the newest available unless every netxms-*
# package is pinned, so an older pin used to fail with "held broken packages".
previous_version() {
    local pinned versions candidate
    pinned="$(pinned_version Dockerfile.server)"
    versions="$(available_versions netxms-agent)"
    candidate="$(printf '%s\n' "$versions" | awk -F- -v p="${pinned%%-*}" '$1 != p' | tail -1)"
    printf '%s' "${candidate:-${TEST_PREVIOUS_VERSION:-6.2.2-1}}"
}

# revision_version -- newest release whose Debian revision is not -1, e.g. 6.2.0-2.
# Exercises the branch that accepts an explicit revision in NETXMS_VERSION.
revision_version() {
    local candidate
    candidate="$(available_versions netxms-agent | awk -F- '$2 != 1' | tail -1)"
    printf '%s' "${candidate:-${TEST_REVISION_VERSION:-6.2.0-2}}"
}
