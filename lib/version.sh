#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Project version handling.
#
# VERSION is the single source of truth for the application version.
# Development and release versions both use Semantic Versioning.

LWBS_VERSION=""
LWBS_VERSION_FILE=""

version_is_semver() {
    local version="${1:-}"
    local semver_regex

    semver_regex='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$'

    [[ "$version" =~ $semver_regex ]]
}

version_is_stable_release() {
    local version="${1:-}"

    [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

version_tag_matches() {
    local tag="${1:-}"
    local version="${2:-}"

    [[ "$tag" == "v$version" ]]
}

load_project_version() {
    local version_file="${1:-}"
    local version

    local -a version_lines=()

    if [[ -z "$version_file" ]]; then
        if [[ -z "${LWBS_ROOT:-}" ]]; then
            printf 'Error: project root is unavailable for version resolution.\n' \
                >&2

            return 1
        fi

        version_file="$LWBS_ROOT/${LWBS_VERSION_FILE_NAME:-VERSION}"
    fi

    if [[ ! -r "$version_file" ]]; then
        printf 'Error: project version file is unavailable: %s\n' \
            "$version_file" >&2

        return 1
    fi

    mapfile -t version_lines <"$version_file"

    if ((${#version_lines[@]} != 1)); then
        printf 'Error: project version file must contain exactly one line.\n' \
            >&2

        return 1
    fi

    version="${version_lines[0]}"

    if [[ -z "$version" ||
        "$version" != "${version#"${version%%[![:space:]]*}"}" ||
        "$version" != "${version%"${version##*[![:space:]]}"}" ]]; then

        printf 'Error: project version contains invalid surrounding whitespace.\n' \
            >&2

        return 1
    fi

    if ! version_is_semver "$version"; then
        printf 'Error: project version is not valid Semantic Versioning: %s\n' \
            "$version" >&2

        return 1
    fi

    LWBS_VERSION="$version"
    LWBS_VERSION_FILE="$version_file"

    return 0
}
