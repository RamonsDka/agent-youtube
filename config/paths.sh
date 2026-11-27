# shellcheck shell=bash
# Shared destinations and skill names for install and uninstall.
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
vendor=${VENDOR_DIR:-"$repo/vendor"}
# Resolve once, so a relative VENDOR_DIR behaves the same from any directory.
if [[ -d $vendor ]]; then
    vendor=$(cd -- "$vendor" && pwd -P)
fi
# shellcheck disable=SC2034 # used by the scripts that source this file
pi_skills=${PI_SKILLS_DIR:-"$HOME/.agents/skills"}
# shellcheck disable=SC2034 # used by the scripts that source this file
claude_skills=${CLAUDE_SKILLS_DIR:-"$HOME/.claude/skills"}
# shellcheck disable=SC2034 # used by the scripts that source this file
voice_dir=${CLAUDE_YOUTUBE_DIR:-"$HOME/.claude/youtube"}
agent_dir=${GENTLE_AGENT_DIR:-"$HOME/.gentle-shell/agent"}
# shellcheck disable=SC2034 # used by the scripts that source this file
skills=(yt-audit yt-chapters yt-comment yt-edit yt-package yt-plan yt-retention
        yt-script yt-seo yt-shorts yt-viral)

show_paths() {
    printf '%s\n' 'Override destinations with VENDOR_DIR, PI_SKILLS_DIR, CLAUDE_SKILLS_DIR,' \
        'CLAUDE_YOUTUBE_DIR, and GENTLE_AGENT_DIR.'
}

# skill_state INSTALLED VENDOR_COPY: absent | symlink | vendor-missing | unmodified | modified.
# "Unmodified" means identical to the hash recorded in the manifest at install time, or,
# when none was recorded, to the copy in the vendor checkout.
skill_state() {
    python3 "$repo/config/update.py" skill-state --agent-dir "$agent_dir" \
        --skill "$(basename -- "$1")" --path "$1" --vendor-copy "$2"
}
