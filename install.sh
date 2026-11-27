#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=config/paths.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/config/paths.sh"

if [[ ${1:-} == --help && $# == 1 ]]; then
    printf '%s\n' 'Usage: bash install.sh' \
        'Install the pinned YouTube skills, agent, and TubeMaster MCP registration.' \
        'Use YT_SKILL_REPO or TUBEMASTER_REPO for alternate Git sources; SKIP_NPM=1 skips npm install.'
    show_paths
    exit 0
elif (( $# )); then
    printf '%s\n' 'Usage: bash install.sh' >&2
    exit 2
fi

yt_pin=a2feb2104981a375ffd4f87ee04f4f5344ac43c6
tube_pin=a8497dcd50630c701c5dae5e5e17dfcc9e6819e9

clone_pin() {
    local destination=$1 url=$2 pin=$3
    if [[ -d "$destination/.git" ]]; then
        if [[ -n $(git -C "$destination" status --porcelain --untracked-files=no) ]]; then
            printf 'Refusing to change a checkout with tracked edits: %s\n' "$destination" >&2
            return 1
        fi
        git -C "$destination" fetch -- "$url" "$pin"
    else
        git clone --no-checkout -- "$url" "$destination"
    fi
    git -C "$destination" switch --detach "$pin"
}

mkdir -p -- "$vendor"
vendor=$(cd -- "$vendor" && pwd -P)
clone_pin "$vendor/youtube-agent-skill" "${YT_SKILL_REPO:-https://github.com/jakeschincariol/youtube-agent-skill.git}" "$yt_pin"
clone_pin "$vendor/tubemaster" "${TUBEMASTER_REPO:-https://github.com/Gentleman-Programming/tubemaster.git}" "$tube_pin"
if [[ ${SKIP_NPM:-0} != 1 ]]; then
    (cd -- "$vendor/tubemaster" && npm install)
fi

python3 "$repo/config/update.py" install "$agent_dir" "$vendor/tubemaster"
mkdir -p -- "$pi_skills" "$claude_skills" "$voice_dir" "$agent_dir/agents"
for skill_root in "$pi_skills" "$claude_skills"; do
    for skill in "${skills[@]}"; do
        rm -rf -- "$skill_root/$skill"
        cp -R -- "$vendor/youtube-agent-skill/skills/$skill" "$skill_root/$skill"
    done
done
voice="$voice_dir/voice.md"
if [[ ! -e "$voice" && ! -L "$voice" ]]; then
    cp -n -- "$vendor/youtube-agent-skill/templates/voice.md" "$voice"
fi
cp --remove-destination -- "$repo/agents/agent-youtube.md" "$agent_dir/agents/agent-youtube.md"

printf 'Installed 11 skills in %s and %s.\n' "$pi_skills" "$claude_skills"
printf 'Installed agent-youtube and registered TubeMaster MCP in %s.\n' "$agent_dir"
printf 'Voice profile: %s\n' "$voice"
printf 'Manual step: configure Google OAuth in %s/.env.local and sign in using the TubeMaster CLI.\n' "$vendor/tubemaster"
printf 'https://github.com/Gentleman-Programming/tubemaster/blob/%s/docs/getting-started.md\n' "$tube_pin"
