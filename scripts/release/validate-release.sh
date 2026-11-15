#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Release validation utility.
#
# Validates that a repository state is suitable for publishing a stable
# Linux Workstation Bootstrap release.
#
# This file:
# 1. Validates the Git tag format used for published releases.
# 2. Loads the authoritative project version from the VERSION file.
# 3. Requires stable release versions to follow Semantic Versioning.
# 4. Verifies that the Git tag exactly matches the project version.
# 5. Ensures the repository working tree is clean before release packaging.
# 6. Fails early when release metadata or repository state is inconsistent.
#
# Release validation does not create tags, modify VERSION, package artifacts,
# or publish GitHub releases. Those responsibilities remain separate.
#
# Stable release tags use:
#
#   vMAJOR.MINOR.PATCH
#
# Example:
#
#   VERSION = 0.2.0
#   Git tag = v0.2.0
#
# Development versions such as 0.2.0-dev are intentionally rejected from
# stable release publication.

set -Eeuo pipefail

RELEASE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_ROOT="$(cd -- "$RELEASE_SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../lib/version.sh
source "$RELEASE_ROOT/lib/version.sh"

release_validate_tag_format() {
    local tag="${1:-}"

    [[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

release_validate_tag_matches_version() {
    local tag="${1:-}"
    local version="${2:-}"

    release_validate_tag_format "$tag" &&
        version_is_stable_release "$version" &&
        version_tag_matches "$tag" "$version"
}

release_require_clean_tree() {
    local repository_root="${1:-$RELEASE_ROOT}"
    local status_output

    if status_output="$(
        git \
            -C "$repository_root" \
            status \
            --porcelain \
            --untracked-files=all
    )"; then
        :
    else
        printf 'Error: unable to determine repository working-tree state.\n' \
            >&2

        return 1
    fi

    [[ -z "$status_output" ]]
}

release_validation_main() {
    local tag="${1:-}"

    if [[ -z "$tag" ]]; then
        printf 'Usage: %s <release-tag>\n' \
            "${BASH_SOURCE[0]}" >&2

        return 2
    fi

    if ! release_validate_tag_format "$tag"; then
        printf 'Error: release tag must use vMAJOR.MINOR.PATCH format.\n' \
            >&2

        return 1
    fi

    if ! load_project_version "$RELEASE_ROOT/VERSION"; then
        return 1
    fi

    if ! version_is_stable_release "$LWBS_VERSION"; then
        printf 'Error: VERSION must contain a stable Semantic Version for release publication: %s\n' \
            "$LWBS_VERSION" >&2

        return 1
    fi

    if ! release_validate_tag_matches_version \
        "$tag" \
        "$LWBS_VERSION"; then

        printf 'Error: release tag %s does not match VERSION %s.\n' \
            "$tag" \
            "$LWBS_VERSION" >&2

        return 1
    fi

    if ! release_require_clean_tree "$RELEASE_ROOT"; then
        printf 'Error: release repository state is not clean.\n' >&2

        return 1
    fi

    printf 'Release validation passed: %s\n' "$tag"

    return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    release_validation_main "$@"
fi
