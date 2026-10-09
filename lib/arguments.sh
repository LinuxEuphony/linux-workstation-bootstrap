#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Command-line argument handling.
# This file:
# 1. Parses supported command-line options.
# 2. Stores command-line selections for the current session.
# 3. Rejects unknown or incomplete options before bootstrap processing begins.

LWBS_DRY_RUN=false
LWBS_ASSUME_YES=false
LWBS_REQUESTED_DISTRO_PROFILE=""
LWBS_CLI_ACTION="run"

parse_arguments() {
    local distro_value

    while (($# > 0)); do
        case "$1" in
            --dry-run)
                LWBS_DRY_RUN=true
                ;;

            -y | --yes)
                # Explicitly approve supported non-interactive confirmations,
                # including detected distro selection and execution plans.
                LWBS_ASSUME_YES=true
                ;;

            --distro)
                if (($# < 2)) || [[ -z "${2:-}" || "$2" == -* ]]; then
                    printf 'Error: %s requires a distribution profile.\n' \
                        "$1" >&2
                    return 2
                fi

                LWBS_REQUESTED_DISTRO_PROFILE="${2,,}"
                shift
                ;;

            --distro=*)
                distro_value="${1#*=}"

                if [[ -z "$distro_value" ]]; then
                    printf 'Error: --distro requires a distribution profile.\n' \
                        >&2
                    return 2
                fi

                LWBS_REQUESTED_DISTRO_PROFILE="${distro_value,,}"
                ;;

            -h | --help)
                LWBS_CLI_ACTION="help"
                ;;

            --version)
                LWBS_CLI_ACTION="version"
                ;;

            -*)
                printf 'Error: unknown option: %s\n' "$1" >&2
                return 2
                ;;

            *)
                printf 'Error: unexpected argument: %s\n' "$1" >&2
                return 2
                ;;
        esac

        shift
    done

    return 0
}