#!/bin/bash
# Bonsai adapter for pinned maintenance handlers. No interactive sudo.
set -euo pipefail
[[ $EUID -ne 0 && $# -eq 1 ]] || exit 2
case "$1" in
 saved_state_cleanup|fix_broken_configs|login_items_audit|audit_system_maintenance|audit_network_optimization|audit_network_stack_optimize|audit_disk_permissions_repair|audit_spotlight_orphan_rules_cleanup|shared_file_list_repair|audit_quarantine_cleanup|audit_notification_cleanup|audit_coreduet_cleanup|cache_refresh|sqlite_vacuum|prevent_network_dsstore|legacy_overrides_audit|launch_agents_cleanup|spotlight_index_optimize|periodic_maintenance) ;;
 *) exit 2 ;;
esac
export MOLE_OPTIMIZE_SUDO_AVAILABLE=false MOLE_LOG_ROTATED=1 NO_COLOR=1
export MOLE_DRY_RUN=0 MO_DEBUG=0
source "$(dirname "$0")/lib/core/common.sh"
trap cleanup_temp_files EXIT
source "$(dirname "$0")/lib/optimize/maintenance.sh"
source "$(dirname "$0")/lib/manage/whitelist.sh"
source "$(dirname "$0")/lib/optimize/tasks.sh"
load_whitelist optimize
# Cache retirement uses the native, ownership/identity-checked Trash helper.
# This is the only admitted handler that calls safe_remove.
cache_recovery=$(mktemp_file "bonsai-cache-recovery")
safe_remove() {
 [[ "$MOLE_DRY_RUN" == 1 ]] && return 0
 "$BONSAI_TRASH_HELPER" "$1" >> "$cache_recovery" 2>&1
}

action="$1"
if [[ "$action" == audit_* ]]; then
 export MOLE_DRY_RUN=1
 action="${action#audit_}"
 printf 'Diagnostic preview only. No changes are applied by this task.\n'
fi
execute_optimization "$action"
outcome="${MOLE_OPTIMIZE_RESULT_OUTCOMES[0]}"
if [[ "$1" == audit_* && "$outcome" == applied ]]; then outcome=attention; fi
cat "$cache_recovery"
printf '\nBONSAI_TASK_RESULT\t%s\t%s\n' "$1" "$outcome"
