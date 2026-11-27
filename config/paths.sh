# Shared destinations and skill names for install and uninstall.
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
vendor=${VENDOR_DIR:-"$repo/vendor"}
pi_skills=${PI_SKILLS_DIR:-"$HOME/.agents/skills"}
claude_skills=${CLAUDE_SKILLS_DIR:-"$HOME/.claude/skills"}
voice_dir=${CLAUDE_YOUTUBE_DIR:-"$HOME/.claude/youtube"}
agent_dir=${GENTLE_AGENT_DIR:-"$HOME/.gentle-shell/agent"}
skills=(yt-audit yt-chapters yt-comment yt-edit yt-package yt-plan yt-retention
        yt-script yt-seo yt-shorts yt-viral)

show_paths() {
    printf '%s\n' 'Override destinations with VENDOR_DIR, PI_SKILLS_DIR, CLAUDE_SKILLS_DIR,' \
        'CLAUDE_YOUTUBE_DIR, and GENTLE_AGENT_DIR.'
}
