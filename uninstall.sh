#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=config/paths.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/config/paths.sh"

usage() {
    printf '%s\n' 'Usage: bash uninstall.sh [--help]'
}

for arg in "$@"; do
    case $arg in
        --help)
            usage
            printf '%s\n' \
                'Remove the installed YouTube skills, agent, and TubeMaster MCP registration.' \
                'Only items that still match what the installer wrote are removed. Modified or' \
                'symlinked skills, a modified agent file, and skills whose vendor copy is missing' \
                'are kept and listed on stderr. The voice profile, Git checkouts, and configuration' \
                'backups are always kept.'
            show_paths
            exit 0
            ;;
        *) usage >&2; exit 2 ;;
    esac
done

kept=0
if ! update_out=$(python3 "$repo/config/update.py" uninstall --agent-dir "$agent_dir"); then
    exit 1
fi
[[ -z $update_out ]] || printf '%s\n' "$update_out"
if [[ $update_out == *skipped* ]]; then
    kept=1
fi

for skill_root in "$pi_skills" "$claude_skills"; do
    for skill in "${skills[@]}"; do
        target="$skill_root/$skill"
        state=$(skill_state "$target" "$vendor/youtube-agent-skill/skills/$skill")
        case $state in
            absent) ;;
            unmodified)
                rm -rf -- "$target"
                printf 'removed: %s\n' "$target"
                ;;
            *)
                reason=$state
                [[ $state != vendor-missing ]] || reason="vendor copy missing in $vendor"
                printf 'warning: kept %s (%s)\n' "$target" "$reason" >&2
                printf 'skipped (%s): %s\n' "$state" "$target"
                kept=1
                ;;
        esac
    done
done

if (( kept )); then
    printf '%s\n' 'Removed installed YouTube integrations, but some items were kept (see warnings above); kept the voice profile, vendor checkouts, and backups.'
else
    printf '%s\n' 'Removed installed YouTube integrations; kept the voice profile, vendor checkouts, and backups.'
fi
