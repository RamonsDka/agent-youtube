#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=config/paths.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/config/paths.sh"

usage() {
    printf '%s\n' 'Usage: bash install.sh [--force] [--help]'
}

show_help() {
    usage
    printf '%s\n' \
        'Install the pinned YouTube skills, the agent, and the TubeMaster MCP registration.' \
        '' \
        'Options:' \
        '  --force   overwrite skills, the agent file, and config entries you modified;' \
        '            each is backed up beside the original first' \
        '  --help    show this help' \
        '' \
        'Environment:' \
        '  VENDOR_DIR, PI_SKILLS_DIR, CLAUDE_SKILLS_DIR, CLAUDE_YOUTUBE_DIR, GENTLE_AGENT_DIR' \
        '            override destinations (defaults: ./vendor, ~/.agents/skills, ~/.claude/skills,' \
        '            ~/.claude/youtube, ~/.gentle-shell/agent)' \
        '  YT_SKILL_REPO, TUBEMASTER_REPO' \
        '            alternate Git sources for the two pinned upstream repos' \
        '  SKIP_NPM=1' \
        '            skip the npm step in the TubeMaster checkout (npm ci with a lockfile)' \
        '  AGENT_YOUTUBE_MODEL' \
        '            model for the agent (default: unset, so your configured default applies)' \
        '  AGENT_YOUTUBE_EFFORT' \
        '            low|medium|high|max (default high); `thinking` in the agent file and' \
        '            `effort` in subagents.json' \
        '  AGENT_YOUTUBE_OPERATOR=1' \
        '            also allow mutating TubeMaster tools (upload, apply, playlists, social);' \
        '            the default install is read-only' \
        '' \
        'The agent prompt is rendered with the resolved voice path (CLAUDE_YOUTUBE_DIR/voice.md)' \
        'and the resolved Pi skills directory (PI_SKILLS_DIR).' \
        'Requires git, python3, npm, and node 20.9 or newer; yt-dlp and watch-video are optional.'
}

force=0
for arg in "$@"; do
    case $arg in
        --help) show_help; exit 0 ;;
        --force) force=1 ;;
        *) usage >&2; exit 2 ;;
    esac
done

# Pre-flight: nothing is changed until these pass.
for tool in git python3 npm node; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'error: required tool not found: %s\n' "$tool" >&2; exit 1; }
done
node_version=$(node --version 2>/dev/null || true)
if [[ $node_version =~ ^v?([0-9]+)\.([0-9]+) ]] &&
    (( BASH_REMATCH[1] > 20 || (BASH_REMATCH[1] == 20 && BASH_REMATCH[2] >= 9) )); then
    :
else
    printf 'error: node 20.9 or newer is required (found: %s)\n' "${node_version:-unknown}" >&2
    exit 1
fi
for tool in yt-dlp watch-video; do
    command -v "$tool" >/dev/null 2>&1 ||
        printf 'warning: %s not found; the agent will work without it (video analysis and public listings are limited)\n' "$tool" >&2
done

yt_pin=a2feb2104981a375ffd4f87ee04f4f5344ac43c6
tube_pin=a8497dcd50630c701c5dae5e5e17dfcc9e6819e9

# Check installed skills against the vendor tree as it is now, before clone_pin moves it.
stamp=$(date -u +%Y%m%dT%H%M%SZ).$$
modified=() keep_aside=()
for skill_root in "$pi_skills" "$claude_skills"; do
    for skill in "${skills[@]}"; do
        state=$(skill_state "$skill_root/$skill" "$vendor/youtube-agent-skill/skills/$skill")
        case $state in
            absent | unmodified) ;;
            *) modified+=("$skill_root/$skill ($state)"); keep_aside+=("$skill_root/$skill") ;;
        esac
    done
done
if (( ${#modified[@]} && ! force )); then
    printf '%s\n' 'error: these installed skills differ from the previous install and would be overwritten:' >&2
    printf '  %s\n' "${modified[@]}" >&2
    printf '%s\n' 'Keep them and remove them from the way, or rerun with --force (each is moved to <skill>.bak.<timestamp> first).' >&2
    exit 1
fi

# Validate configs and the agent file before anything is created or cloned.
check_args=(--agent-dir "$agent_dir" --tubemaster "$vendor/tubemaster" --template "$repo/agents/agent-youtube.md"
    --voice "$voice_dir/voice.md" --skills-dir "$pi_skills" --check)
if (( force )); then
    check_args+=(--force)
fi
python3 "$repo/config/update.py" install "${check_args[@]}"

verify_pin() {
    git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null
}

clone_pin() {
    local destination=$1 url=$2 pin=$3
    if [[ -e "$destination/.git" ]]; then
        if [[ -n $(git -C "$destination" status --porcelain --untracked-files=no) ]]; then
            printf 'Refusing to change a checkout with tracked edits: %s\n' "$destination" >&2
            return 1
        fi
        if ! git -C "$destination" fetch -- "$url" "$pin"; then
            # Some servers refuse a fetch by commit id; get every branch and tag instead.
            git -C "$destination" fetch -- "$url" '+refs/heads/*:refs/remotes/origin/*' 'refs/tags/*:refs/tags/*' || true
        fi
    else
        git clone --no-checkout -- "$url" "$destination"
    fi
    if ! verify_pin "$destination" "$pin"; then
        printf 'error: commit %s is not available from %s\n' "$pin" "$url" >&2
        return 1
    fi
    if ! git -C "$destination" switch --detach "$pin"; then
        printf 'error: cannot check out %s in %s; untracked files may be in the way, move them aside and rerun\n' "$pin" "$destination" >&2
        return 1
    fi
}

mkdir -p -- "$vendor"
vendor=$(cd -- "$vendor" && pwd -P)
clone_pin "$vendor/youtube-agent-skill" "${YT_SKILL_REPO:-https://github.com/jakeschincariol/youtube-agent-skill.git}" "$yt_pin"
clone_pin "$vendor/tubemaster" "${TUBEMASTER_REPO:-https://github.com/Gentleman-Programming/tubemaster.git}" "$tube_pin"
if [[ ${SKIP_NPM:-0} != 1 ]]; then
    if [[ -f "$vendor/tubemaster/package-lock.json" ]]; then
        (cd -- "$vendor/tubemaster" && npm ci)
    else
        (cd -- "$vendor/tubemaster" && npm install)
    fi
fi

mkdir -p -- "$pi_skills" "$claude_skills" "$voice_dir" "$agent_dir"
voice="$(cd -- "$voice_dir" && pwd -P)/voice.md"
pi_skills_abs=$(cd -- "$pi_skills" && pwd -P)

for skill_root in "$pi_skills" "$claude_skills"; do
    for skill in "${skills[@]}"; do
        target="$skill_root/$skill"
        if [[ -e $target || -L $target ]]; then
            moved=0
            for aside in ${keep_aside[@]+"${keep_aside[@]}"}; do
                if [[ $aside == "$target" ]]; then
                    mv -- "$target" "$target.bak.$stamp"
                    moved=1
                fi
            done
            if (( ! moved )); then
                rm -rf -- "$target"
            fi
        fi
        cp -R -- "$vendor/youtube-agent-skill/skills/$skill" "$target"
    done
done
if [[ ! -e "$voice" && ! -L "$voice" ]]; then
    cp -- "$vendor/youtube-agent-skill/templates/voice.md" "$voice"
fi

# Registers the config entries and the agent file, and records a hash of each copied skill.
update_args=(--agent-dir "$agent_dir" --tubemaster "$vendor/tubemaster"
    --template "$repo/agents/agent-youtube.md" --voice "$voice" --skills-dir "$pi_skills_abs")
for skill in "${skills[@]}"; do
    update_args+=(--skill "$skill")
done
if (( force )); then
    update_args+=(--force)
fi
python3 "$repo/config/update.py" install "${update_args[@]}"

printf 'Installed %d skills in %s and %s.\n' "${#skills[@]}" "$pi_skills" "$claude_skills"
printf 'Installed agent-youtube and registered TubeMaster MCP in %s.\n' "$agent_dir"
printf 'Voice profile: %s\n' "$voice"
printf 'Manual step: configure Google OAuth in %s/.env.local and sign in using the TubeMaster CLI.\n' "$vendor/tubemaster"
printf 'https://github.com/Gentleman-Programming/tubemaster/blob/%s/docs/getting-started.md\n' "$tube_pin"
