#!/usr/bin/env bash

# Linux Workstation Bootstrap
# Author: David Kariuki
#
# Command-line argument handling.
# This file:
# 1. Parses supported command-line options.
# 2. Stores command-line selections for the current session.
# 3. Rejects unknown or incomplete options before bootstrap processing begins.

# Runtime command-line state.
# These values describe the current execution and are not application configuration.
LWBS_DRY_RUN=false
LWBS_ASSUME_YES=false
LWBS_REQUESTED_DISTRO_PROFILE=""
LWBS_CLI_ACTION="run"

# Parse command-line arguments supplied to the bootstrap executable.
parse_arguments() {
    local distro_value

    while (($# > 0)); do
        case "$1" in
            --dry-run)
                # Preview intended actions without applying system changes.
                LWBS_DRY_RUN=true
                ;;

            -y | --yes)
                # Accept supported detected configuration without prompting.
                LWBS_ASSUME_YES=true
                ;;

            --distro)
                # --distro requires a separate distribution profile value.
                if (($# < 2)) || [[ -z "${2:-}" || "$2" == -* ]]; then
                    printf 'Error: %s requires a distribution profile.\n' \
                        "$1" >&2
                    return 2
                fi

                LWBS_REQUESTED_DISTRO_PROFILE="${2,,}"

                # Consume the distribution value together with the option.
                shift
                ;;

            --distro=*)
                # Support the --distro=ubuntu form in addition to --distro ubuntu.
                distro_value="${1#*=}"

                if [[ -z "$distro_value" ]]; then
                    printf 'Error: --distro requires a distribution profile.\n' \
                        >&2
                    return 2
                fi

                LWBS_REQUESTED_DISTRO_PROFILE="${distro_value,,}"
                ;;

            -h | --help)
                # Help is handled by the bootstrap layer after parsing completes.
                LWBS_CLI_ACTION="help"
                ;;

            --version)
                # Version output is handled without starting a bootstrap session.
                LWBS_CLI_ACTION="version"
                ;;

            -*)
                # Reject options that are not part of the supported CLI.
                printf 'Error: unknown option: %s\n' "$1" >&2
                return 2
                ;;

            *)
                # Positional arguments are not currently supported.
                printf 'Error: unexpected argument: %s\n' "$1" >&2
                return 2
                ;;
        esac

        shift
    done

    return 0
}