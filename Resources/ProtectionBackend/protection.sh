#!/bin/bash
# Bonsai adapter: calls unchanged Mole protection functions, pinned to
# c430bac637929ebede043df81d3bef319428309c (GPL-3.0).
# Read-only string classification. No path operations, network, or deletion.
set -euo pipefail
source "$(dirname "$0")/app_protection_data.sh"
APPLE_UNINSTALLABLE_REGEX=""
SYSTEM_CRITICAL_REGEX=""
bundle_matches_pattern() {
    local bundle_id="$1"
    local pattern="$2"

    [[ -z "$pattern" ]] && return 1

    # Use bash [[  ]] for glob pattern matching (works with variables in bash 3.2+)
    # shellcheck disable=SC2053  # allow glob pattern matching
    if [[ "$bundle_id" == $pattern ]]; then
        return 0
    fi
    return 1
}

build_regex_var() {
    local var_name="$1"
    shift
    local regex=""
    for pattern in "$@"; do
        # Escape dots . -> \.
        local p="${pattern//./\\.}"
        # Convert * to .*
        p="${p//\*/.*}"
        # Start and end anchors
        p="^${p}$"

        if [[ -z "$regex" ]]; then
            regex="$p"
        else
            regex="$regex|$p"
        fi
    done
    # eval: indirect write by name; bash 3.2 has no nameref
    eval "$var_name=\"\$regex\""
}

_ensure_uninstall_regex() {
    if [[ -z "$SYSTEM_CRITICAL_REGEX" ]]; then
        build_regex_var APPLE_UNINSTALLABLE_REGEX "${APPLE_UNINSTALLABLE_APPS[@]}"
        build_regex_var SYSTEM_CRITICAL_REGEX "${SYSTEM_CRITICAL_BUNDLES[@]}"
    fi
}

should_protect_from_uninstall() {
    local bundle_id="$1"

    _ensure_uninstall_regex

    if [[ "$bundle_id" =~ $APPLE_UNINSTALLABLE_REGEX ]]; then
        return 1
    fi

    if [[ "$bundle_id" =~ $SYSTEM_CRITICAL_REGEX ]]; then
        return 0
    fi

    return 1
}

official_uninstaller_vendor() {
    local bundle_id="${1:-}"
    local display_name="${2:-}"
    local app_path="${3:-}"
    local normalized_bundle normalized_name normalized_path
    normalized_bundle=$(printf '%s' "$bundle_id" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    normalized_name=$(printf '%s' "$display_name" | LC_ALL=C tr '[:upper:]' '[:lower:]')
    normalized_path=$(basename "${app_path:-}")
    normalized_path="${normalized_path%.[aA][pP][pP]}"
    normalized_path=$(printf '%s' "$normalized_path" | LC_ALL=C tr '[:upper:]' '[:lower:]')

    local rule vendor prefixes fragments prefix fragment
    local -a _prefixes _fragments
    for rule in "${OFFICIAL_UNINSTALLER_RULES[@]}"; do
        IFS='|' read -r vendor prefixes fragments <<< "$rule"
        IFS=',' read -r -a _prefixes <<< "$prefixes"
        for prefix in "${_prefixes[@]}"; do
            [[ -n "$prefix" && "$normalized_bundle" == "$prefix"* ]] && {
                printf '%s\n' "$vendor"
                return 0
            }
        done

        IFS=',' read -r -a _fragments <<< "$fragments"
        for fragment in "${_fragments[@]}"; do
            if [[ -n "$fragment" ]] &&
                { [[ "$normalized_name" == *"$fragment"* ]] || [[ "$normalized_path" == *"$fragment"* ]]; }; then
                printf '%s\n' "$vendor"
                return 0
            fi
        done
    done

    return 1
}
[[ $# -le 512 ]] || exit 2
for id in "$@"; do
    [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || exit 2
    protected=0
    if should_protect_from_uninstall "$id"; then protected=1; fi
    vendor=$(official_uninstaller_vendor "$id" "" "" || true)
    [[ -z "$vendor" ]] || protected=1
    printf '%s\t%s\t%s\n' "$id" "$protected" "$vendor"
done
