#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=config/paths.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/config/paths.sh"

if [[ ${1:-} == --help && $# == 1 ]]; then
    printf '%s\n' 'Usage: bash uninstall.sh' \
        'Remove the installed YouTube skills, agent, and TubeMaster MCP registration.' \
        'Keep the voice profile, Git checkouts, and configuration backups.'
    show_paths
    exit 0
elif (( $# )); then
    printf '%s\n' 'Usage: bash uninstall.sh' >&2
    exit 2
fi

python3 "$repo/config/update.py" uninstall "$agent_dir" "$vendor/tubemaster"
for skill_root in "$pi_skills" "$claude_skills"; do
    for skill in "${skills[@]}"; do
        target="$skill_root/$skill"
        source_skill="$vendor/youtube-agent-skill/skills/$skill"
        if [[ -d "$target" && ! -L "$target" && -d "$source_skill" ]] &&
            diff -qr -- "$source_skill" "$target" >/dev/null; then
            rm -rf -- "$target"
        fi
    done
done
agent="$agent_dir/agents/agent-youtube.md"
if cmp -s -- "$repo/agents/agent-youtube.md" "$agent"; then
    rm -- "$agent"
fi
printf '%s\n' 'Removed installed YouTube integrations; kept the voice profile, vendor checkouts, and backups.'
